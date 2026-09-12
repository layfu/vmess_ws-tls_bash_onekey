package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"time"
)

type api struct {
	store     *store
	cfg       *Config
	onlineWin int64
	geo       *geoLookup
	server    *serverLocator
}

type userInfo struct {
	Protocol      string `json:"protocol"`
	Username      string `json:"username"`
	Uplink        int64  `json:"uplink"`
	Downlink      int64  `json:"downlink"`
	Total         int64  `json:"total"`
	LifetimeUp    int64  `json:"lifetime_up"`
	LifetimeDown  int64  `json:"lifetime_down"`
	LifetimeTotal int64  `json:"lifetime_total"`
	LastSeen      int64  `json:"last_seen"`
	Online        bool   `json:"online"`
}

func (a *api) overview(w http.ResponseWriter, r *http.Request) {
	totals, err := a.store.totals()
	if err != nil {
		writeErr(w, err)
		return
	}
	now := time.Now()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location()).Unix()
	monthly, err := a.store.monthlyTotals(monthStart)
	if err != nil {
		writeErr(w, err)
		return
	}
	users := make([]userInfo, 0, len(totals))
	var totalUp, totalDown int64
	for _, t := range totals {
		monthUp, monthDown := int64(0), int64(0)
		if m, ok := monthly[t.Protocol+"|"+t.Username]; ok {
			monthUp, monthDown = m.Uplink, m.Downlink
		}
		users = append(users, userInfo{
			Protocol:      t.Protocol,
			Username:      t.Username,
			Uplink:        monthUp,
			Downlink:      monthDown,
			Total:         monthUp + monthDown,
			LifetimeUp:    t.Uplink,
			LifetimeDown:  t.Downlink,
			LifetimeTotal: t.Uplink + t.Downlink,
			LastSeen:      t.LastSeen,
			Online:        t.LastSeen > 0 && now.Unix()-t.LastSeen <= a.onlineWin,
		})
		totalUp += monthUp
		totalDown += monthDown
	}
	writeJSON(w, map[string]any{
		"users":      users,
		"total_up":   totalUp,
		"total_down": totalDown,
		"updated_at": now.Unix(),
	})
}

type hourlyPoint struct {
	Hour     int64 `json:"hour"`
	Uplink   int64 `json:"uplink"`
	Downlink int64 `json:"downlink"`
}

func (a *api) traffic(w http.ResponseWriter, r *http.Request) {
	hours, _ := strconv.Atoi(r.URL.Query().Get("hours"))
	if hours <= 0 || hours > 24*7 {
		hours = 24
	}
	since := time.Now().Add(-time.Duration(hours) * time.Hour)
	totals, err := a.store.totals()
	if err != nil {
		writeErr(w, err)
		return
	}
	series := map[string][]hourlyPoint{}
	for _, t := range totals {
		rows, err := a.store.hourly(t.Protocol, t.Username, since)
		if err != nil {
			continue
		}
		pts := make([]hourlyPoint, 0, len(rows))
		for _, r := range rows {
			pts = append(pts, hourlyPoint{Hour: r.Hour, Uplink: r.Uplink, Downlink: r.Downlink})
		}
		series[t.Protocol+":"+t.Username] = pts
	}
	writeJSON(w, map[string]any{"series": series})
}

type connInfo struct {
	TS        int64  `json:"ts"`
	Protocol  string `json:"protocol"`
	Username  string `json:"username"`
	Source    string `json:"source"`
	SourceGeo string `json:"source_geo"`
	Target    string `json:"target"`
	Status    string `json:"status"`
}

func (a *api) connections(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 50
	}
	if limit > 1000 {
		limit = 1000
	}
	protocols := r.URL.Query()["protocol"]
	usernames := r.URL.Query()["username"]
	statuses := r.URL.Query()["status"]
	rows, err := a.store.connections(limit, protocols, usernames, statuses)
	if err != nil {
		writeErr(w, err)
		return
	}
	out := make([]connInfo, 0, len(rows))
	for _, r := range rows {
		ci := connInfo{TS: r.TS, Protocol: r.Protocol, Username: r.Username, Source: r.Source, Target: r.Target, Status: r.Status}
		if a.geo != nil {
			ci.SourceGeo = a.geo.lookup(r.Source)
		}
		out = append(out, ci)
	}
	writeJSON(w, map[string]any{"connections": out})
}

type routeNode struct {
	Lat    float64          `json:"lat"`
	Lng    float64          `json:"lng"`
	Region string           `json:"region"`
	Count  int64            `json:"count"`
	Status map[string]int64 `json:"status"`
}

// routes aggregates recent connections into coarse client locations for the
// globe: one node per region with per-status counts, plus the server hub.
func (a *api) routes(w http.ResponseWriter, r *http.Request) {
	hours, _ := strconv.Atoi(r.URL.Query().Get("hours"))
	if hours <= 0 || hours > 24*7 {
		hours = 24
	}
	since := time.Now().Add(-time.Duration(hours) * time.Hour).Unix()
	rows, err := a.store.connectionStats(since)
	if err != nil {
		writeErr(w, err)
		return
	}

	type agg struct {
		region   string
		lat, lng float64
		count    int64
		status   map[string]int64
	}
	type point struct {
		region   string
		lat, lng float64
		ok       bool
	}
	cache := map[string]point{}
	byKey := map[string]*agg{}
	for _, row := range rows {
		if a.geo == nil {
			continue
		}
		p, seen := cache[row.Source]
		if !seen {
			region, lat, lng, ok := a.geo.lookupPoint(row.Source)
			p = point{region: region, lat: lat, lng: lng, ok: ok}
			cache[row.Source] = p
		}
		if !p.ok {
			continue
		}
		key := fmt.Sprintf("%.3f,%.3f", p.lat, p.lng)
		n := byKey[key]
		if n == nil {
			n = &agg{region: p.region, lat: p.lat, lng: p.lng, status: map[string]int64{}}
			byKey[key] = n
		}
		n.count += row.Count
		status := row.Status
		if status == "" {
			status = "unknown"
		}
		n.status[status] += row.Count
	}

	nodes := make([]routeNode, 0, len(byKey))
	for _, n := range byKey {
		nodes = append(nodes, routeNode{
			Lat:    n.lat,
			Lng:    n.lng,
			Region: n.region,
			Count:  n.count,
			Status: n.status,
		})
	}
	sort.Slice(nodes, func(i, j int) bool {
		if nodes[i].Count != nodes[j].Count {
			return nodes[i].Count > nodes[j].Count
		}
		return nodes[i].Region < nodes[j].Region
	})
	const maxNodes = 24
	if len(nodes) > maxNodes {
		nodes = nodes[:maxNodes]
	}

	writeJSON(w, map[string]any{
		"server":       a.server.get(),
		"nodes":        nodes,
		"window_hours": hours,
		"updated_at":   time.Now().Unix(),
	})
}

type historyUser struct {
	Protocol string `json:"protocol"`
	Username string `json:"username"`
	Uplink   int64  `json:"uplink"`
	Downlink int64  `json:"downlink"`
}

func (a *api) history(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	start, _ := strconv.ParseInt(q.Get("start"), 10, 64)
	end, _ := strconv.ParseInt(q.Get("end"), 10, 64)
	now := time.Now().Unix()
	if end <= 0 || end > now {
		end = now
	}
	if start <= 0 {
		start = end - 30*24*3600
	}
	if start >= end {
		writeJSON(w, map[string]any{
			"total_up":   int64(0),
			"total_down": int64(0),
			"users":      []historyUser{},
		})
		return
	}
	protocols := q["protocol"]
	usernames := q["username"]
	rows, err := a.store.hourlyRange(start, end, protocols, usernames)
	if err != nil {
		writeErr(w, err)
		return
	}

	var totalUp, totalDown int64
	userMap := map[string]*historyUser{}
	for _, r := range rows {
		totalUp += r.Uplink
		totalDown += r.Downlink

		key := r.Protocol + ":" + r.Username
		u := userMap[key]
		if u == nil {
			u = &historyUser{Protocol: r.Protocol, Username: r.Username}
			userMap[key] = u
		}
		u.Uplink += r.Uplink
		u.Downlink += r.Downlink
	}

	users := make([]historyUser, 0, len(userMap))
	for _, u := range userMap {
		users = append(users, *u)
	}
	sort.Slice(users, func(i, j int) bool {
		if users[i].Protocol != users[j].Protocol {
			return users[i].Protocol < users[j].Protocol
		}
		return users[i].Username < users[j].Username
	})

	writeJSON(w, map[string]any{
		"total_up":   totalUp,
		"total_down": totalDown,
		"users":      users,
	})
}

func (a *api) configs(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{"configs": loadAllConfigs(a.cfg)})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, err error) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusInternalServerError)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}
