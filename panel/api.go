package main

import (
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"time"
)

type api struct {
	store     *store
	cfg       *Config
	onlineWin int64
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
	ResetAt       int64  `json:"reset_at"`
	Online        bool   `json:"online"`
}

func (a *api) overview(w http.ResponseWriter, r *http.Request) {
	totals, err := a.store.totals()
	if err != nil {
		writeErr(w, err)
		return
	}
	now := time.Now().Unix()
	users := make([]userInfo, 0, len(totals))
	var totalUp, totalDown int64
	for _, t := range totals {
		periodUp := t.Uplink - t.ResetUplink
		periodDown := t.Downlink - t.ResetDownlink
		users = append(users, userInfo{
			Protocol:      t.Protocol,
			Username:      t.Username,
			Uplink:        periodUp,
			Downlink:      periodDown,
			Total:         periodUp + periodDown,
			LifetimeUp:    t.Uplink,
			LifetimeDown:  t.Downlink,
			LifetimeTotal: t.Uplink + t.Downlink,
			LastSeen:      t.LastSeen,
			ResetAt:       t.ResetAt,
			Online:        t.LastSeen > 0 && now-t.LastSeen <= a.onlineWin,
		})
		totalUp += periodUp
		totalDown += periodDown
	}
	writeJSON(w, map[string]any{
		"users":      users,
		"total_up":   totalUp,
		"total_down": totalDown,
		"updated_at": now,
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
	TS       int64  `json:"ts"`
	Protocol string `json:"protocol"`
	Username string `json:"username"`
	Source   string `json:"source"`
	Target   string `json:"target"`
}

func (a *api) connections(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 200
	}
	if limit > 1000 {
		limit = 1000
	}
	protocol := r.URL.Query().Get("protocol")
	username := r.URL.Query().Get("username")
	rows, err := a.store.connections(limit, protocol, username)
	if err != nil {
		writeErr(w, err)
		return
	}
	out := make([]connInfo, 0, len(rows))
	for _, r := range rows {
		out = append(out, connInfo{TS: r.TS, Protocol: r.Protocol, Username: r.Username, Source: r.Source, Target: r.Target})
	}
	writeJSON(w, map[string]any{"connections": out})
}

type historyDay struct {
	Day      int64 `json:"day"`
	Uplink   int64 `json:"uplink"`
	Downlink int64 `json:"downlink"`
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
			"days":       []historyDay{},
			"users":      []historyUser{},
		})
		return
	}
	protocol := q.Get("protocol")
	username := q.Get("username")
	rows, err := a.store.hourlyRange(start, end, protocol, username)
	if err != nil {
		writeErr(w, err)
		return
	}

	var totalUp, totalDown int64
	dayMap := map[int64]*historyDay{}
	userMap := map[string]*historyUser{}
	for _, r := range rows {
		totalUp += r.Uplink
		totalDown += r.Downlink

		day := localMidnight(r.Hour)
		d := dayMap[day]
		if d == nil {
			d = &historyDay{Day: day}
			dayMap[day] = d
		}
		d.Uplink += r.Uplink
		d.Downlink += r.Downlink

		key := r.Protocol + ":" + r.Username
		u := userMap[key]
		if u == nil {
			u = &historyUser{Protocol: r.Protocol, Username: r.Username}
			userMap[key] = u
		}
		u.Uplink += r.Uplink
		u.Downlink += r.Downlink
	}

	days := make([]historyDay, 0, len(dayMap))
	for _, d := range dayMap {
		days = append(days, *d)
	}
	sort.Slice(days, func(i, j int) bool { return days[i].Day < days[j].Day })

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
		"days":       days,
		"users":      users,
	})
}

// localMidnight converts an hourly bucket (Unix seconds, UTC-truncated) into
// the local calendar day's midnight Unix timestamp for day-based grouping.
func localMidnight(hour int64) int64 {
	t := time.Unix(hour, 0).Local()
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location()).Unix()
}

func (a *api) reset(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		writeJSON(w, map[string]string{"error": "method not allowed"})
		return
	}
	now := time.Now().Unix()
	if err := a.store.resetAllTraffic(now); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, map[string]any{"reset_at": now})
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
