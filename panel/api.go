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

const topoTopN = 10

// topology aggregates recent traffic into a layered routing graph:
// user -> protocol -> server -> outbound status -> target. User/protocol bytes
// come from the per-user stats; outbound/target bytes come from the Clash API
// per-connection stats. User full paths (for hover) come from the connection log.
func (a *api) topology(w http.ResponseWriter, r *http.Request) {
	hours, _ := strconv.Atoi(r.URL.Query().Get("hours"))
	if hours <= 0 || hours > 24*7 {
		hours = 24
	}
	since := time.Now().Add(-time.Duration(hours) * time.Hour).Unix()
	userRows, err := a.store.userProtocolTraffic(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	targetRows, err := a.store.targetTraffic(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	outboundBytes, err := a.store.outboundTraffic(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	inboundBytes, err := a.store.inboundTraffic(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	connRows, err := a.store.connectionGraph(since)
	if err != nil {
		writeErr(w, err)
		return
	}
	nodes, links, totals, userPaths := buildTopology(userRows, targetRows, outboundBytes, inboundBytes, connRows)
	if nodes == nil {
		nodes = []topoNode{}
	}
	if links == nil {
		links = []topoLink{}
	}
	if totals == nil {
		totals = map[string]int64{}
	}
	if userPaths == nil {
		userPaths = map[string][]int{}
	}
	writeJSON(w, map[string]any{
		"nodes":        nodes,
		"links":        links,
		"totals":       totals,
		"user_paths":   userPaths,
		"window_hours": hours,
		"updated_at":   time.Now().Unix(),
	})
}

// buildTopology turns per-user, per-outbound and per-target traffic into a
// layered routing graph: user -> protocol -> server -> outbound -> target.
// Direct/WARP are measured in bytes: the accurate outbound total comes from the
// v2ray_api outbound stats, and the Clash per-target sample is scaled to match.
// Blocked is measured in attempts (count). Users/targets beyond the top N are
// merged into an "其他" node. userPaths maps a user node to its route links.
func buildTopology(userRows []userTrafficRow, targetRows []targetTrafficRow, outboundBytes map[string]int64, inboundBytes map[string]int64, connRows []connGraphRow) ([]topoNode, []topoLink, map[string]int64, map[string][]int) {
	userBytes := map[string]int64{}
	protoBytes := map[string]int64{}
	userProto := map[[2]string]int64{}
	var total int64
	for _, r := range userRows {
		if r.Username == "" {
			continue
		}
		b := r.Uplink + r.Downlink
		if b == 0 {
			continue
		}
		userBytes[r.Username] += b
		userProto[[2]string{r.Username, r.Protocol}] += b
		total += b
	}
	// 协议层用 inbound 统计（按协议准确，同名用户跨协议也不会错）；
	// 没有 inbound 数据的协议回退到用户统计汇总。
	for p, b := range inboundBytes {
		protoBytes[p] = b
	}
	for pair, b := range userProto {
		if _, ok := protoBytes[pair[1]]; !ok {
			protoBytes[pair[1]] += b
		}
	}

	// Clash per-status and per (status,host) sample bytes.
	clashStatus := map[string]int64{}
	clashOutTarget := map[[2]string]int64{}
	for _, r := range targetRows {
		b := r.Uplink + r.Downlink
		if b == 0 || r.Host == "" {
			continue
		}
		status := r.Status
		if status == "" {
			status = "unknown"
		}
		clashStatus[status] += b
		clashOutTarget[[2]string{status, r.Host}] += b
	}

	// Accurate outbound bytes (v2ray_api outbound stats); "block" -> "blocked".
	outBytes := map[string]int64{}
	for tag, b := range outboundBytes {
		status := tag
		if tag == "block" {
			status = "blocked"
		}
		outBytes[status] += b
	}
	if len(outBytes) == 0 { // fall back to the Clash sample
		for s, b := range clashStatus {
			outBytes[s] = b
		}
	}

	// Direct/WARP: scale the Clash target distribution to the accurate outbound total.
	targetBytes := map[string]int64{}
	outTarget := map[[2]string]int64{}
	for pair, b := range clashOutTarget {
		status, host := pair[0], pair[1]
		if status == "blocked" {
			continue
		}
		denom := clashStatus[status]
		if denom <= 0 || outBytes[status] <= 0 {
			continue
		}
		scaled := b * outBytes[status] / denom
		if scaled <= 0 {
			continue
		}
		targetBytes[host] += scaled
		outTarget[pair] += scaled
	}

	// Blocked: attempts per target from the connection log.
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

	var statusTotal int64
	for s, b := range outBytes {
		if s == "blocked" {
			continue
		}
		statusTotal += b
	}
	if total == 0 && statusTotal == 0 && blockedTotal == 0 {
		return nil, nil, nil, nil
	}
	serverBytes := total
	if serverBytes == 0 {
		serverBytes = statusTotal
	}

	keepUsers := topKeys(userBytes, topoTopN)
	keepTargets := topKeys(targetBytes, topoTopN)
	keepBlocked := topKeys(blockedCounts, topoTopN)
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
	blockedKey := func(name string) string {
		if keepBlocked[name] {
			return "btarget:" + name
		}
		return "btarget:__other__"
	}

	nodes := make([]topoNode, 0)

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
	for id, b := range userNodeBytes {
		nodes = append(nodes, topoNode{ID: id, Label: userLabel[id], Kind: "user", Value: b, Unit: "bytes"})
	}
	for p, b := range protoBytes {
		nodes = append(nodes, topoNode{ID: "proto:" + p, Label: protoLabel(p), Kind: "protocol", Value: b, Unit: "bytes"})
	}
	nodes = append(nodes, topoNode{ID: "srv", Label: "服务器", Kind: "server", Value: serverBytes, Unit: "bytes"})
	for s, b := range outBytes {
		if s == "blocked" {
			continue
		}
		nodes = append(nodes, topoNode{ID: "out:" + s, Label: statusLabel(s), Kind: s, Value: b, Unit: "bytes"})
	}
	if blockedTotal > 0 {
		nodes = append(nodes, topoNode{ID: "out:blocked", Label: statusLabel("blocked"), Kind: "blocked", Value: blockedTotal, Unit: "count"})
	}

	targetNodeBytes := map[string]int64{}
	targetLabel := map[string]string{}
	for name, b := range targetBytes {
		id := targetKey(name)
		targetNodeBytes[id] += b
		if _, ok := targetLabel[id]; !ok {
			if id == "target:__other__" {
				targetLabel[id] = "其他"
			} else {
				targetLabel[id] = name
			}
		}
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

	links := make([]topoLink, 0)
	addLink := func(src, dst, status string, v int64, unit string) {
		if v <= 0 {
			return
		}
		links = append(links, topoLink{Source: src, Target: dst, Status: status, Value: v, Unit: unit})
	}
	for pair, b := range userProto {
		addLink(userKey(pair[0]), "proto:"+pair[1], "", b, "bytes")
	}
	for p, b := range protoBytes {
		addLink("proto:"+p, "srv", "", b, "bytes")
	}
	for s, b := range outBytes {
		if s == "blocked" {
			continue
		}
		addLink("srv", "out:"+s, s, b, "bytes")
	}
	if blockedTotal > 0 {
		addLink("srv", "out:blocked", "blocked", blockedTotal, "count")
	}
	for pair, b := range outTarget {
		addLink("out:"+pair[0], targetKey(pair[1]), pair[0], b, "bytes")
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

	// Map (source,target) to link index for the per-user hover paths.
	linkIndex := make(map[[2]string]int, len(links))
	for i, l := range links {
		linkIndex[[2]string{l.Source, l.Target}] = i
	}
	pathSets := map[string]map[int]bool{}
	for _, r := range connRows {
		if r.Username == "" {
			continue
		}
		status := r.Status
		if status == "" {
			status = "unknown"
		}
		uk := userKey(r.Username)
		pk := "proto:" + r.Protocol
		outk := "out:" + status
		var tk string
		if status == "blocked" {
			tk = blockedKey(normalizeTarget(r.Target))
		} else {
			tk = targetKey(normalizeTarget(r.Target))
		}
		set := pathSets[uk]
		if set == nil {
			set = map[int]bool{}
			pathSets[uk] = set
		}
		for _, key := range [][2]string{{uk, pk}, {pk, "srv"}, {"srv", outk}, {outk, tk}} {
			if i, ok := linkIndex[key]; ok {
				set[i] = true
			}
		}
	}
	userPaths := make(map[string][]int, len(pathSets))
	for uk, set := range pathSets {
		idxs := make([]int, 0, len(set))
		for i := range set {
			idxs = append(idxs, i)
		}
		sort.Ints(idxs)
		userPaths[uk] = idxs
	}

	totals := map[string]int64{}
	for s, b := range outBytes {
		if s == "blocked" {
			continue
		}
		totals[s] = b
	}
	if blockedTotal > 0 {
		totals["blocked"] = blockedTotal
	}

	return nodes, links, totals, userPaths
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
