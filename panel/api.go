package main

import (
	"encoding/json"
	"net"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
)

type api struct {
	store     *store
	cfg       *Config
	onlineWin int64
	geo       *geoLookup
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

type topoNode struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Kind  string `json:"kind"`
	Count int64  `json:"count"`
}

type topoLink struct {
	Source string `json:"source"`
	Target string `json:"target"`
	Status string `json:"status"`
	Count  int64  `json:"count"`
}

const topoTopN = 10

// topology aggregates recent connections into a layered routing graph:
// user -> protocol -> server -> outbound status -> target.
func (a *api) topology(w http.ResponseWriter, r *http.Request) {
	hours, _ := strconv.Atoi(r.URL.Query().Get("hours"))
	if hours <= 0 || hours > 24*7 {
		hours = 24
	}
	since := time.Now().Add(-time.Duration(hours) * time.Hour).Unix()
	rows, err := a.store.connectionGraph(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	nodes, links, totals := buildTopology(rows)
	if nodes == nil {
		nodes = []topoNode{}
	}
	if links == nil {
		links = []topoLink{}
	}
	if totals == nil {
		totals = map[string]int64{}
	}
	writeJSON(w, map[string]any{
		"nodes":        nodes,
		"links":        links,
		"totals":       totals,
		"window_hours": hours,
		"updated_at":   time.Now().Unix(),
	})
}

// buildTopology turns grouped connection rows into topology nodes and links.
// Users and targets beyond the top N are merged into an "其他" node so the
// flows stay balanced and the graph stays readable.
func buildTopology(rows []connGraphRow) ([]topoNode, []topoLink, map[string]int64) {
	userTotals := map[string]int64{}
	targetTotals := map[string]int64{}
	userProto := map[[2]string]int64{}
	protoTotal := map[string]int64{}
	statusTotal := map[string]int64{}
	outTarget := map[[2]string]int64{}
	var total int64

	for _, r := range rows {
		user := r.Username
		if user == "" {
			user = "未知用户"
		}
		status := r.Status
		if status == "" {
			status = "unknown"
		}
		target := normalizeTarget(r.Target)
		userTotals[user] += r.Count
		targetTotals[target] += r.Count
		userProto[[2]string{user, r.Protocol}] += r.Count
		protoTotal[r.Protocol] += r.Count
		statusTotal[status] += r.Count
		outTarget[[2]string{status, target}] += r.Count
		total += r.Count
	}
	if total == 0 {
		return nil, nil, nil
	}

	keepUsers := topKeys(userTotals, topoTopN)
	keepTargets := topKeys(targetTotals, topoTopN)
	userKey := func(name string) string {
		if keepUsers[name] {
			return "user:" + name
		}
		return "user:__other__"
	}
	targetKey := func(name string) string {
		if keepTargets[name] {
			return "target:" + name
		}
		return "target:__other__"
	}

	userCount := map[string]int64{}
	userLabel := map[string]string{}
	for name, c := range userTotals {
		id := userKey(name)
		userCount[id] += c
		if _, ok := userLabel[id]; !ok {
			if id == "user:__other__" {
				userLabel[id] = "其他"
			} else {
				userLabel[id] = name
			}
		}
	}
	targetCount := map[string]int64{}
	targetLabel := map[string]string{}
	for name, c := range targetTotals {
		id := targetKey(name)
		targetCount[id] += c
		if _, ok := targetLabel[id]; !ok {
			if id == "target:__other__" {
				targetLabel[id] = "其他"
			} else {
				targetLabel[id] = name
			}
		}
	}

	nodes := make([]topoNode, 0, len(userCount)+len(protoTotal)+1+len(statusTotal)+len(targetCount))
	for id, c := range userCount {
		nodes = append(nodes, topoNode{ID: id, Label: userLabel[id], Kind: "user", Count: c})
	}
	for p, c := range protoTotal {
		nodes = append(nodes, topoNode{ID: "proto:" + p, Label: protoLabel(p), Kind: "protocol", Count: c})
	}
	nodes = append(nodes, topoNode{ID: "srv", Label: "服务器", Kind: "server", Count: total})
	for s, c := range statusTotal {
		nodes = append(nodes, topoNode{ID: "out:" + s, Label: statusLabel(s), Kind: s, Count: c})
	}
	for id, c := range targetCount {
		nodes = append(nodes, topoNode{ID: id, Label: targetLabel[id], Kind: "target", Count: c})
	}

	linkCount := map[[3]string]int64{}
	for pair, c := range userProto {
		linkCount[[3]string{userKey(pair[0]), "proto:" + pair[1], ""}] += c
	}
	for p, c := range protoTotal {
		linkCount[[3]string{"proto:" + p, "srv", ""}] += c
	}
	for s, c := range statusTotal {
		linkCount[[3]string{"srv", "out:" + s, s}] += c
	}
	for pair, c := range outTarget {
		linkCount[[3]string{"out:" + pair[0], targetKey(pair[1]), pair[0]}] += c
	}
	links := make([]topoLink, 0, len(linkCount))
	for k, c := range linkCount {
		links = append(links, topoLink{Source: k[0], Target: k[1], Status: k[2], Count: c})
	}

	sort.Slice(nodes, func(i, j int) bool {
		li, lj := topoLayer(nodes[i].Kind), topoLayer(nodes[j].Kind)
		if li != lj {
			return li < lj
		}
		if nodes[i].Count != nodes[j].Count {
			return nodes[i].Count > nodes[j].Count
		}
		return nodes[i].ID < nodes[j].ID
	})
	sort.Slice(links, func(i, j int) bool {
		if links[i].Source != links[j].Source {
			return links[i].Source < links[j].Source
		}
		if links[i].Target != links[j].Target {
			return links[i].Target < links[j].Target
		}
		return links[i].Status < links[j].Status
	})
	return nodes, links, statusTotal
}

// topoLayer maps a node kind to its column: user=0, protocol=1, server=2,
// outbound statuses=3, target=4.
func topoLayer(kind string) int {
	switch kind {
	case "user":
		return 0
	case "protocol":
		return 1
	case "server":
		return 2
	case "target":
		return 4
	default:
		return 3
	}
}

func topKeys(m map[string]int64, n int) map[string]bool {
	type kv struct {
		k string
		v int64
	}
	arr := make([]kv, 0, len(m))
	for k, v := range m {
		arr = append(arr, kv{k, v})
	}
	sort.Slice(arr, func(i, j int) bool {
		if arr[i].v != arr[j].v {
			return arr[i].v > arr[j].v
		}
		return arr[i].k < arr[j].k
	})
	keep := make(map[string]bool, n)
	for i := 0; i < len(arr) && i < n; i++ {
		keep[arr[i].k] = true
	}
	return keep
}

func normalizeTarget(t string) string {
	if t == "" {
		return "未知目标"
	}
	host := t
	if h, _, err := net.SplitHostPort(t); err == nil {
		host = h
	}
	host = strings.Trim(strings.TrimSpace(host), "[]")
	if host == "" {
		return "未知目标"
	}
	return strings.ToLower(host)
}

func protoLabel(p string) string {
	switch p {
	case "vmess":
		return "VMess"
	case "anytls":
		return "AnyTLS"
	case "":
		return "未知协议"
	default:
		return p
	}
}

func statusLabel(s string) string {
	switch s {
	case "direct":
		return "直连"
	case "warp":
		return "WARP"
	case "blocked":
		return "封禁"
	default:
		return "未知"
	}
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
