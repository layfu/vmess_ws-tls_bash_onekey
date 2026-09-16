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
	Value int64  `json:"value"`
	Unit  string `json:"unit"`
}

type topoLink struct {
	Source string `json:"source"`
	Target string `json:"target"`
	Status string `json:"status"`
	Value  int64  `json:"value"`
	Unit   string `json:"unit"`
}

// topoCell is one exact (user, protocol, outbound, target) -> value datum. The
// frontend recomputes every node/link value as a marginal of these cells under
// the current hover filter, so hovering any node shows that slice's traffic.
type topoCell struct {
	User     string `json:"u"`
	Protocol string `json:"p"`
	Outbound string `json:"o"`
	Target   string `json:"t"`
	Value    int64  `json:"v"`
	Unit     string `json:"unit"`
}

const topoTopN = 10

// topology returns the layered routing graph (user -> protocol -> server ->
// outbound -> target) as full marginals plus the exact per-(user, protocol,
// outbound, target) cells, which the frontend filters on hover. Values come from
// the connection records, reconciled to the custom user_outbound>>> counter.
func (a *api) topology(w http.ResponseWriter, r *http.Request) {
	hours, _ := strconv.Atoi(r.URL.Query().Get("hours"))
	if hours <= 0 || hours > 24*7 {
		hours = 24
	}
	since := time.Now().Add(-time.Duration(hours) * time.Hour).Unix()
	userTargetRows, err := a.store.userTargetTraffic(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	userOutboundRows, err := a.store.userOutboundTraffic(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	connRows, err := a.store.connectionGraph(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	nodes, links, totals, cells := buildTopology(userTargetRows, userOutboundRows, connRows)
	if nodes == nil {
		nodes = []topoNode{}
	}
	if links == nil {
		links = []topoLink{}
	}
	if totals == nil {
		totals = map[string]int64{}
	}
	if cells == nil {
		cells = []topoCell{}
	}
	writeJSON(w, map[string]any{
		"nodes":        nodes,
		"links":        links,
		"totals":       totals,
		"cells":        cells,
		"window_hours": hours,
		"updated_at":   time.Now().Unix(),
	})
}

// buildTopology turns the exact per-connection records into a layered routing
// graph: user -> protocol -> server -> outbound -> target. Every value is a
// marginal of the 4-D table ct[user][protocol][outbound][target] (bytes), built
// from the connection records and reconciled to the exact user_outbound>>>
// counter for each (user, protocol, outbound) slice. Blocked is a separate
// dimension measured in attempts (count). Users/targets beyond the top N are
// merged into an "其他" node. The raw cells are returned so the frontend can
// recompute the same marginals under any hover filter.
func buildTopology(userTargetRows []userTargetTrafficRow, userOutboundRows []userOutboundRow, connRows []connGraphRow) ([]topoNode, []topoLink, map[string]int64, []topoCell) {
	type cellKey struct {
		user, proto, status, host string
	}

	// Raw byte cells from the connection records (blocked excluded).
	raw := map[cellKey]int64{}
	for _, r := range userTargetRows {
		if r.Username == "" || r.Host == "" {
			continue
		}
		status := r.Status
		if status == "" {
			status = "unknown"
		}
		if status == "blocked" {
			continue
		}
		b := r.Uplink + r.Downlink
		if b == 0 {
			continue
		}
		raw[cellKey{r.Username, r.Protocol, status, r.Host}] += b
	}
	sliceRaw := map[[3]string]int64{}
	for k, v := range raw {
		sliceRaw[[3]string{k.user, k.proto, k.status}] += v
	}

	// Exact per-(user, protocol, outbound) totals from the custom counter.
	sliceExact := map[[3]string]int64{}
	for _, r := range userOutboundRows {
		if r.Username == "" {
			continue
		}
		status := r.Tag
		if status == "block" {
			status = "blocked"
		}
		if status == "blocked" {
			continue
		}
		sliceExact[[3]string{r.Username, r.Protocol, status}] += r.Uplink + r.Downlink
	}

	// Reconcile each slice to its exact total. Slices with exact bytes but no
	// records are attributed to an unknown target so the outbound still shows.
	cells4 := map[cellKey]int64{}
	for k, v := range raw {
		sk := [3]string{k.user, k.proto, k.status}
		total := sliceExact[sk]
		if total <= 0 {
			total = sliceRaw[sk]
		}
		if total <= 0 {
			continue
		}
		if scaled := v * total / sliceRaw[sk]; scaled > 0 {
			cells4[k] = scaled
		}
	}
	for sk, total := range sliceExact {
		if sliceRaw[sk] > 0 || total <= 0 {
			continue
		}
		cells4[cellKey{sk[0], sk[1], sk[2], ""}] += total
	}

	userBytes := map[string]int64{}
	hostBytes := map[string]int64{}
	for k, v := range cells4 {
		userBytes[k.user] += v
		hostBytes[k.host] += v
	}
	// Rank users by bytes plus blocked attempts so blocked-only users keep a node.
	userRank := map[string]int64{}
	for name, b := range userBytes {
		userRank[name] = b
	}
	for _, r := range connRows {
		if r.Status == "blocked" && r.Username != "" {
			userRank[baseUserName(r.Username)] += r.Count
		}
	}
	keepUsers := topKeys(userRank, topoTopN)
	keepTargets := topKeys(hostBytes, topoTopN)
	userKey := func(name string) string {
		if keepUsers[name] {
			return "user:" + name
		}
		return "user:__other__"
	}
	targetKey := func(name string) string {
		if name == "" {
			return "target:未知目标"
		}
		if keepTargets[name] {
			return "target:" + name
		}
		return "target:__other__"
	}

	// Blocked attempts (count) from the connection log.
	blockedCounts := map[string]int64{}
	var blockedTotal int64
	for _, r := range connRows {
		if r.Status != "blocked" {
			continue
		}
		host := normalizeTarget(r.Target)
		if host == "" {
			continue
		}
		blockedCounts[host] += r.Count
		blockedTotal += r.Count
	}
	keepBlocked := topKeys(blockedCounts, topoTopN)
	blockedKey := func(name string) string {
		if keepBlocked[name] {
			return "btarget:" + name
		}
		return "btarget:__other__"
	}

	// Node marginals.
	userNodeBytes := map[string]int64{}
	userLabel := map[string]string{}
	for name, b := range userBytes {
		id := userKey(name)
		userNodeBytes[id] += b
		if _, ok := userLabel[id]; !ok {
			if id == "user:__other__" {
				userLabel[id] = "其他"
			} else {
				userLabel[id] = name
			}
		}
	}
	protoBytes := map[string]int64{}
	outBytes := map[string]int64{}
	for k, v := range cells4 {
		protoBytes[k.proto] += v
		outBytes[k.status] += v
	}
	targetNodeBytes := map[string]int64{}
	targetLabel := map[string]string{}
	for host, b := range hostBytes {
		id := targetKey(host)
		targetNodeBytes[id] += b
		if _, ok := targetLabel[id]; !ok {
			switch id {
			case "target:__other__":
				targetLabel[id] = "其他"
			case "target:未知目标":
				targetLabel[id] = "未知目标"
			default:
				targetLabel[id] = host
			}
		}
	}
	var serverBytes int64
	for _, b := range userNodeBytes {
		serverBytes += b
	}
	if serverBytes == 0 && blockedTotal == 0 {
		return nil, nil, nil, nil
	}

	nodes := make([]topoNode, 0)
	for id, b := range userNodeBytes {
		nodes = append(nodes, topoNode{ID: id, Label: userLabel[id], Kind: "user", Value: b, Unit: "bytes"})
	}
	for p, b := range protoBytes {
		nodes = append(nodes, topoNode{ID: "proto:" + p, Label: protoLabel(p), Kind: "protocol", Value: b, Unit: "bytes"})
	}
	nodes = append(nodes, topoNode{ID: "srv", Label: "服务器", Kind: "server", Value: serverBytes, Unit: "bytes"})
	for s, b := range outBytes {
		nodes = append(nodes, topoNode{ID: "out:" + s, Label: statusLabel(s), Kind: s, Value: b, Unit: "bytes"})
	}
	if blockedTotal > 0 {
		nodes = append(nodes, topoNode{ID: "out:blocked", Label: statusLabel("blocked"), Kind: "blocked", Value: blockedTotal, Unit: "count"})
	}
	for id, b := range targetNodeBytes {
		nodes = append(nodes, topoNode{ID: id, Label: targetLabel[id], Kind: "target", Value: b, Unit: "bytes"})
	}
	blockedNodeCounts := map[string]int64{}
	blockedLabel := map[string]string{}
	for name, c := range blockedCounts {
		id := blockedKey(name)
		blockedNodeCounts[id] += c
		if _, ok := blockedLabel[id]; !ok {
			if id == "btarget:__other__" {
				blockedLabel[id] = "其他"
			} else {
				blockedLabel[id] = name
			}
		}
	}
	for id, c := range blockedNodeCounts {
		nodes = append(nodes, topoNode{ID: id, Label: blockedLabel[id], Kind: "target", Value: c, Unit: "count"})
	}

	// Link marginals.
	links := make([]topoLink, 0)
	addLink := func(src, dst, status string, v int64, unit string) {
		if v <= 0 {
			return
		}
		links = append(links, topoLink{Source: src, Target: dst, Status: status, Value: v, Unit: unit})
	}
	userProtoBytes := map[[2]string]int64{}
	outTargetBytes := map[[2]string]int64{}
	for k, v := range cells4 {
		userProtoBytes[[2]string{userKey(k.user), "proto:" + k.proto}] += v
		outTargetBytes[[2]string{"out:" + k.status, targetKey(k.host)}] += v
	}
	for pair, b := range userProtoBytes {
		addLink(pair[0], pair[1], "", b, "bytes")
	}
	for p, b := range protoBytes {
		addLink("proto:"+p, "srv", "", b, "bytes")
	}
	for s, b := range outBytes {
		addLink("srv", "out:"+s, s, b, "bytes")
	}
	for pair, b := range outTargetBytes {
		addLink(pair[0], pair[1], strings.TrimPrefix(pair[0], "out:"), b, "bytes")
	}
	if blockedTotal > 0 {
		addLink("srv", "out:blocked", "blocked", blockedTotal, "count")
	}
	for name, c := range blockedCounts {
		addLink("out:blocked", blockedKey(name), "blocked", c, "count")
	}

	sort.Slice(nodes, func(i, j int) bool {
		li, lj := topoLayer(nodes[i].Kind), topoLayer(nodes[j].Kind)
		if li != lj {
			return li < lj
		}
		if nodes[i].Value != nodes[j].Value {
			return nodes[i].Value > nodes[j].Value
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

	// Cells for the frontend hover filter (byte cells + blocked count cells).
	cells := make([]topoCell, 0, len(cells4))
	for k, v := range cells4 {
		if v <= 0 {
			continue
		}
		cells = append(cells, topoCell{
			User:     userKey(k.user),
			Protocol: "proto:" + k.proto,
			Outbound: "out:" + k.status,
			Target:   targetKey(k.host),
			Value:    v,
			Unit:     "bytes",
		})
	}
	for _, r := range connRows {
		if r.Username == "" || r.Status != "blocked" {
			continue
		}
		host := normalizeTarget(r.Target)
		if host == "" {
			continue
		}
		cells = append(cells, topoCell{
			User:     userKey(baseUserName(r.Username)),
			Protocol: "proto:" + r.Protocol,
			Outbound: "out:blocked",
			Target:   blockedKey(host),
			Value:    r.Count,
			Unit:     "count",
		})
	}

	totals := map[string]int64{}
	for s, b := range outBytes {
		totals[s] = b
	}
	if blockedTotal > 0 {
		totals["blocked"] = blockedTotal
	}

	return nodes, links, totals, cells
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
