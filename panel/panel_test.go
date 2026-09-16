package main

import (
	"bytes"
	"fmt"
	"path/filepath"
	"testing"
	"time"
)

func encVarint(buf *bytes.Buffer, v uint64) {
	for v >= 0x80 {
		buf.WriteByte(byte(v) | 0x80)
		v >>= 7
	}
	buf.WriteByte(byte(v))
}

func encTag(buf *bytes.Buffer, field, wire int) {
	encVarint(buf, uint64(field<<3|wire))
}

func encString(buf *bytes.Buffer, field int, s string) {
	encTag(buf, field, wireBytes)
	encVarint(buf, uint64(len(s)))
	buf.WriteString(s)
}

func encInt64(buf *bytes.Buffer, field int, v int64) {
	encTag(buf, field, wireVarint)
	encVarint(buf, uint64(v))
}

func TestParseQueryStatsResponse(t *testing.T) {
	var stat1, stat2, resp bytes.Buffer
	encString(&stat1, 1, "user>>>alice>>>traffic>>>uplink")
	encInt64(&stat1, 2, 12345)
	encString(&stat2, 1, "user>>>alice>>>traffic>>>downlink")
	encInt64(&stat2, 2, 67890)

	encTag(&resp, 1, wireBytes)
	encVarint(&resp, uint64(stat1.Len()))
	resp.Write(stat1.Bytes())
	encTag(&resp, 1, wireBytes)
	encVarint(&resp, uint64(stat2.Len()))
	resp.Write(stat2.Bytes())

	stats := parseQueryStatsResponse(resp.Bytes())
	if len(stats) != 2 {
		t.Fatalf("expected 2 stats, got %d", len(stats))
	}
	if stats[0].Name != "user>>>alice>>>traffic>>>uplink" || stats[0].Value != 12345 {
		t.Errorf("stat0 = %+v", stats[0])
	}
	if stats[1].Name != "user>>>alice>>>traffic>>>downlink" || stats[1].Value != 67890 {
		t.Errorf("stat1 = %+v", stats[1])
	}
}

func TestParseV2rayLine(t *testing.T) {
	line := "2026/08/27 12:00:00 1.2.3.4:54321 accepted tcp:example.com:443 [direct] email: user1"
	p, u, src, dst, status, ts, ok := parseV2rayLine(line)
	if !ok {
		t.Fatalf("expected ok")
	}
	if p != "vmess" || u != "user1" || src != "1.2.3.4:54321" || dst != "example.com:443" || status != "direct" {
		t.Errorf("got %q %q %q %q %q", p, u, src, dst, status)
	}
	if ts <= 0 {
		t.Errorf("expected positive timestamp, got %d", ts)
	}

	blocked := "2026/08/27 12:00:00 1.2.3.4:54321 accepted tcp:example.com:443 [blocked] email: user1"
	_, _, _, _, status, _, ok = parseV2rayLine(blocked)
	if !ok || status != "blocked" {
		t.Errorf("expected blocked status, got %q %v", status, ok)
	}

	rej := "2026/08/27 12:00:00 5.6.7.8:9999 rejected  email: user2"
	if _, _, _, _, _, _, ok := parseV2rayLine(rej); ok {
		t.Errorf("rejected line should not be accepted")
	}

	// 面板自身轮询统计接口产生的内部连接：无 email、tag 为 api、目标是回环。
	api := "2026/09/12 17:18:55 127.0.0.1:36464 accepted tcp:127.0.0.1:0 [api]"
	if _, _, _, _, _, _, ok := parseV2rayLine(api); ok {
		t.Errorf("api inbound line should be skipped")
	}
	loopback := "2026/09/12 17:18:55 127.0.0.1:36464 accepted tcp:127.0.0.1:8080 [direct]"
	if _, _, _, _, _, _, ok := parseV2rayLine(loopback); ok {
		t.Errorf("loopback target should be skipped")
	}
}

func TestParseNginxWsLine(t *testing.T) {
	line := "1.2.3.4 2026-08-27T12:00:00+08:00 /e01ec5ea/ 101"
	ip, ts, ok := parseNginxWsLine(line)
	if !ok || ip != "1.2.3.4" || ts <= 0 {
		t.Errorf("got %q %d %v", ip, ts, ok)
	}
	if _, _, ok := parseNginxWsLine("garbage"); ok {
		t.Errorf("garbage should not parse")
	}
}

func TestParseSingboxInbound(t *testing.T) {
	withUser := "+0800 2026-08-27 12:00:00 INFO [123 12s] inbound/anytls[anytls-in]: [user1] inbound connection from 1.2.3.4:54321 to example.com:443"
	id, u, src, dst, ok := parseSingboxInbound(withUser)
	if !ok {
		t.Fatalf("expected ok")
	}
	if id != "123" || u != "user1" || src != "1.2.3.4:54321" || dst != "example.com:443" {
		t.Errorf("got %q %q %q %q", id, u, src, dst)
	}

	// 官方 sing-box 不记录来源（只有目标）
	noSource := "INFO [42 3s] inbound/anytls[anytls-in]: [user1] inbound connection to example.com:443"
	_, u, src, dst, ok = parseSingboxInbound(noSource)
	if !ok || u != "user1" || src != "" || dst != "example.com:443" {
		t.Errorf("got %q %q %q %v", u, src, dst, ok)
	}

	noUser := "INFO [43 3s] inbound/anytls[anytls-in]: inbound connection from 5.6.7.8:9999 to 1.2.3.4:443"
	_, u2, src2, dst2, ok := parseSingboxInbound(noUser)
	if !ok || u2 != "" || src2 != "5.6.7.8:9999" || dst2 != "1.2.3.4:443" {
		t.Errorf("got %q %q %q %v", u2, src2, dst2, ok)
	}
}

func TestParseSingboxOutbound(t *testing.T) {
	direct := "+0800 2026-08-27 12:00:00 INFO [123 12s] outbound/direct[direct]: outbound connection to example.com:443"
	id, status, ok := parseSingboxOutbound(direct)
	if !ok || id != "123" || status != "direct" {
		t.Errorf("got %q %q %v", id, status, ok)
	}

	warp := "+0800 2026-08-27 12:00:00 INFO [123 12s] outbound/socks[warp]: outbound connection to video-s.twimg.com:443"
	id, status, ok = parseSingboxOutbound(warp)
	if !ok || id != "123" || status != "warp" {
		t.Errorf("got %q %q %v", id, status, ok)
	}

	blocked := "+0800 2026-08-27 12:00:00 INFO [123 12s] outbound/block[block]: blocked connection to example.com:443"
	id, status, ok = parseSingboxOutbound(blocked)
	if !ok || id != "123" || status != "blocked" {
		t.Errorf("got %q %q %v", id, status, ok)
	}

	if _, _, ok := parseSingboxOutbound("INFO inbound/anytls[anytls-in]: [user1] inbound connection to example.com:443"); ok {
		t.Errorf("inbound line should not parse as outbound")
	}
}

func TestCorrelator(t *testing.T) {
	st, err := openStore(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	c := newCorrelator(st)
	now := time.Now().Unix()

	_ = st.addConnection("vmess", "user1", "127.0.0.1:54321", "example.com:443", "direct", time.Unix(now, 0))
	c.addVmess(now, "user1", "example.com:443", "127.0.0.1:54321")
	c.addWs(now+1, "9.9.9.9")

	rows, err := st.connections(10, nil, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Source != "9.9.9.9" {
		t.Errorf("expected source 9.9.9.9, got %+v", rows)
	}
}

func TestSingboxMatcher(t *testing.T) {
	st, err := openStore(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	m := newSingboxMatcher(st, nil)

	// inbound + outbound (warp)
	m.handle("+0800 2026-08-27 12:00:00 INFO [1 5ms] inbound/anytls[anytls-in]: [alice] inbound connection from 1.2.3.4:1000 to video-s.twimg.com:443")
	m.handle("+0800 2026-08-27 12:00:00 INFO [1 12ms] outbound/socks[warp]: outbound connection to video-s.twimg.com:443")

	// inbound + outbound (blocked)
	m.handle("+0800 2026-08-27 12:00:00 INFO [2 5ms] inbound/anytls[anytls-in]: [bob] inbound connection from 5.6.7.8:2000 to ad.example.com:443")
	m.handle("+0800 2026-08-27 12:00:00 INFO [2 12ms] outbound/block[block]: blocked connection to ad.example.com:443")

	rows, err := st.connections(10, nil, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 {
		t.Fatalf("expected 2 connections, got %d", len(rows))
	}
	byUser := map[string]connectionRow{}
	for _, r := range rows {
		byUser[r.Username] = r
	}
	if r := byUser["alice"]; r.Status != "warp" || r.Source != "1.2.3.4:1000" {
		t.Errorf("alice = %+v", r)
	}
	if r := byUser["bob"]; r.Status != "blocked" || r.Source != "5.6.7.8:2000" {
		t.Errorf("bob = %+v", r)
	}
}

func TestMonthlyTotals(t *testing.T) {
	st, err := openStore(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	now := time.Now()
	thisMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location()).Unix()
	lastMonth := time.Date(now.Year(), now.Month()-1, 1, 0, 0, 0, 0, now.Location())

	if err := st.addTraffic("vmess", "alice", 100, 200, now); err != nil {
		t.Fatal(err)
	}
	if err := st.addTraffic("vmess", "bob", 300, 400, lastMonth); err != nil {
		t.Fatal(err)
	}

	m, err := st.monthlyTotals(thisMonth)
	if err != nil {
		t.Fatal(err)
	}
	if len(m) != 1 {
		t.Fatalf("expected 1 monthly row, got %d: %+v", len(m), m)
	}
	r, ok := m["vmess|alice"]
	if !ok || r.Uplink != 100 || r.Downlink != 200 {
		t.Errorf("monthly alice = %+v", r)
	}
	if _, ok := m["vmess|bob"]; ok {
		t.Errorf("last month traffic should not appear in monthly totals")
	}
}

func TestConnectionGraph(t *testing.T) {
	st, err := openStore(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	now := time.Now()
	_ = st.addConnection("vmess", "a", "1.1.1.1:1", "example.com:443", "direct", now)
	_ = st.addConnection("vmess", "a", "1.1.1.1:2", "example.com:443", "direct", now)
	_ = st.addConnection("anytls", "b", "2.2.2.2:1", "video.com:443", "warp", now)
	_ = st.addConnection("vmess", "c", "3.3.3.3:1", "old.com:443", "direct", now.Add(-48*time.Hour))

	rows, err := st.connectionGraph(now.Add(-time.Hour).Unix())
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int64{}
	for _, r := range rows {
		counts[r.Username+"|"+r.Protocol+"|"+r.Status+"|"+r.Target] = r.Count
	}
	if len(rows) != 2 {
		t.Fatalf("expected 2 grouped rows, got %d: %+v", len(rows), rows)
	}
	if counts["a|vmess|direct|example.com:443"] != 2 || counts["b|anytls|warp|video.com:443"] != 1 {
		t.Errorf("counts = %+v", counts)
	}
}

func TestStatUserName(t *testing.T) {
	if got := statUserName("vmess", "admin"); got != "v:admin" {
		t.Errorf("vmess stat name = %q, want v:admin", got)
	}
	if got := statUserName("anytls", "admin"); got != "a:admin" {
		t.Errorf("anytls stat name = %q, want a:admin", got)
	}
}

func TestBuildTopology(t *testing.T) {
	userRows := []userTrafficRow{
		{Protocol: "vmess", Username: "alice", Uplink: 100, Downlink: 200},
		{Protocol: "anytls", Username: "bob", Uplink: 50, Downlink: 50},
	}
	targetRows := []targetTrafficRow{
		{Protocol: "vmess", Host: "example.com", Status: "direct", Uplink: 100, Downlink: 200},
		{Protocol: "anytls", Host: "ads.com", Status: "blocked", Uplink: 50, Downlink: 50},
	}
	outboundBytes := map[string]int64{"direct": 300, "block": 100, "warp": 0}
	connRows := []connGraphRow{
		{Username: "alice", Protocol: "vmess", Status: "direct", Target: "example.com:443", Count: 5},
		{Username: "bob", Protocol: "anytls", Status: "blocked", Target: "ads.com:443", Count: 3},
	}
	inboundBytes := map[string]int64{"vmess": 300, "anytls": 100}
	nodes, links, totals, userPaths := buildTopology(userRows, targetRows, outboundBytes, inboundBytes, connRows)

	// direct is bytes (outbound stats), blocked is attempts (count).
	if totals["direct"] != 300 || totals["blocked"] != 3 {
		t.Errorf("totals = %+v", totals)
	}
	byID := map[string]topoNode{}
	for _, n := range nodes {
		byID[n.ID] = n
	}
	if n := byID["srv"]; n.Kind != "server" || n.Value != 400 || n.Unit != "bytes" {
		t.Errorf("server node = %+v", n)
	}
	if n := byID["user:alice"]; n.Value != 300 {
		t.Errorf("alice node = %+v", n)
	}
	if n := byID["out:direct"]; n.Label != "直连" || n.Value != 300 || n.Unit != "bytes" {
		t.Errorf("direct node = %+v", n)
	}
	if n := byID["out:blocked"]; n.Value != 3 || n.Unit != "count" {
		t.Errorf("blocked node = %+v", n)
	}
	if n := byID["target:example.com"]; n.Value != 300 || n.Unit != "bytes" {
		t.Errorf("example.com node = %+v", n)
	}
	if n := byID["btarget:ads.com"]; n.Value != 3 || n.Unit != "count" {
		t.Errorf("ads.com blocked node = %+v", n)
	}
	if _, ok := byID["user:未知用户"]; ok {
		t.Errorf("unknown user should not appear: %+v", nodes)
	}

	linkByKey := map[string]int64{}
	for _, l := range links {
		linkByKey[l.Source+"->"+l.Target] = l.Value
	}
	if linkByKey["srv->out:direct"] != 300 || linkByKey["out:blocked->btarget:ads.com"] != 3 {
		t.Errorf("links = %+v", links)
	}

	alice := map[string]bool{}
	for _, i := range userPaths["user:alice"] {
		if i < 0 || i >= len(links) {
			t.Fatalf("alice path index out of range: %d", i)
		}
		alice[links[i].Source+"->"+links[i].Target] = true
	}
	for _, want := range []string{
		"user:alice->proto:vmess",
		"proto:vmess->srv",
		"srv->out:direct",
		"out:direct->target:example.com",
	} {
		if !alice[want] {
			t.Errorf("alice path missing %q; got %+v", want, alice)
		}
	}
	// bob never used direct/example.com, so those must not be in his path.
	bob := map[string]bool{}
	for _, i := range userPaths["user:bob"] {
		bob[links[i].Source+"->"+links[i].Target] = true
	}
	if bob["srv->out:direct"] || bob["out:direct->target:example.com"] {
		t.Errorf("bob path unexpectedly includes direct route: %+v", bob)
	}
	if !bob["srv->out:blocked"] || !bob["out:blocked->btarget:ads.com"] {
		t.Errorf("bob blocked path missing: %+v", bob)
	}
}

func TestBuildTopologyScalesTargetsToOutbound(t *testing.T) {
	// Clash sample only saw 100 of the real 400 bytes on the warp outbound;
	// the target distribution must be scaled up to 400.
	userRows := []userTrafficRow{
		{Protocol: "vmess", Username: "alice", Uplink: 400, Downlink: 0},
	}
	targetRows := []targetTrafficRow{
		{Protocol: "vmess", Host: "a.com", Status: "warp", Uplink: 60, Downlink: 0},
		{Protocol: "vmess", Host: "b.com", Status: "warp", Uplink: 40, Downlink: 0},
	}
	outboundBytes := map[string]int64{"warp": 400}
	nodes, _, _, _ := buildTopology(userRows, targetRows, outboundBytes, nil, nil)
	byID := map[string]topoNode{}
	for _, n := range nodes {
		byID[n.ID] = n
	}
	if n := byID["out:warp"]; n.Value != 400 {
		t.Errorf("warp node = %+v", n)
	}
	if n := byID["target:a.com"]; n.Value != 240 {
		t.Errorf("a.com = %+v (want 240)", n)
	}
	if n := byID["target:b.com"]; n.Value != 160 {
		t.Errorf("b.com = %+v (want 160)", n)
	}
}

func TestBuildTopologyProtocolUsesInbound(t *testing.T) {
	// Same username on both protocols: the user node is the combined per-user
	// total, while each protocol node comes from the accurate inbound stats.
	userRows := []userTrafficRow{
		{Protocol: "vmess", Username: "admin", Uplink: 100, Downlink: 0},
	}
	targetRows := []targetTrafficRow{
		{Protocol: "vmess", Host: "a.com", Status: "warp", Uplink: 100, Downlink: 0},
	}
	outboundBytes := map[string]int64{"warp": 100}
	inboundBytes := map[string]int64{"vmess": 70, "anytls": 30}
	nodes, _, _, _ := buildTopology(userRows, targetRows, outboundBytes, inboundBytes, nil)
	byID := map[string]topoNode{}
	for _, n := range nodes {
		byID[n.ID] = n
	}
	if n := byID["user:admin"]; n.Value != 100 {
		t.Errorf("user node = %+v (want 100, combined)", n)
	}
	if n := byID["proto:vmess"]; n.Value != 70 {
		t.Errorf("vmess proto = %+v (want 70, inbound)", n)
	}
	if n := byID["proto:anytls"]; n.Value != 30 {
		t.Errorf("anytls proto = %+v (want 30, inbound)", n)
	}
}

func TestBuildTopologySkipsUnknownUser(t *testing.T) {
	userRows := []userTrafficRow{
		{Protocol: "vmess", Username: "alice", Uplink: 5, Downlink: 5},
		{Protocol: "vmess", Username: "", Uplink: 3, Downlink: 0},
	}
	targetRows := []targetTrafficRow{
		{Protocol: "vmess", Host: "example.com", Status: "direct", Uplink: 5, Downlink: 5},
	}
	outboundBytes := map[string]int64{"direct": 10}
	nodes, _, totals, userPaths := buildTopology(userRows, targetRows, outboundBytes, nil, nil)
	if totals["direct"] != 10 {
		t.Errorf("totals = %+v", totals)
	}
	for _, n := range nodes {
		if n.ID == "user:未知用户" {
			t.Errorf("unknown user leaked into topology: %+v", n)
		}
	}
	if _, ok := userPaths["user:未知用户"]; ok {
		t.Errorf("unknown user path should be absent")
	}
}

func TestBuildTopologyOtherBuckets(t *testing.T) {
	var userRows []userTrafficRow
	var targetRows []targetTrafficRow
	var connRows []connGraphRow
	for i := 0; i < 12; i++ {
		userRows = append(userRows, userTrafficRow{
			Protocol: "vmess",
			Username: fmt.Sprintf("u%02d", i),
			Uplink:   int64(100 - i),
		})
		targetRows = append(targetRows, targetTrafficRow{
			Protocol: "vmess",
			Host:     fmt.Sprintf("t%02d.com", i),
			Status:   "direct",
			Uplink:   int64(100 - i),
		})
		connRows = append(connRows, connGraphRow{
			Username: fmt.Sprintf("u%02d", i),
			Protocol: "vmess",
			Status:   "direct",
			Target:   fmt.Sprintf("t%02d.com:443", i),
			Count:    1,
		})
	}
	outboundBytes := map[string]int64{"direct": 1200}
	nodes, links, _, userPaths := buildTopology(userRows, targetRows, outboundBytes, nil, connRows)
	byID := map[string]topoNode{}
	for _, n := range nodes {
		byID[n.ID] = n
	}
	if _, ok := byID["user:u00"]; !ok {
		t.Errorf("top user missing")
	}
	if _, ok := byID["user:u11"]; ok {
		t.Errorf("11th user should be merged into other")
	}
	if n, ok := byID["user:__other__"]; !ok || n.Label != "其他" {
		t.Errorf("other user node = %+v ok=%v", n, ok)
	}
	if _, ok := byID["target:t11.com"]; ok {
		t.Errorf("11th target should be merged into other")
	}
	if _, ok := byID["target:__other__"]; !ok {
		t.Errorf("other target node missing")
	}
	// other buckets must still receive links
	var hasOtherUserLink, hasOtherTargetLink bool
	for _, l := range links {
		if l.Source == "user:__other__" {
			hasOtherUserLink = true
		}
		if l.Target == "target:__other__" {
			hasOtherTargetLink = true
		}
	}
	if !hasOtherUserLink || !hasOtherTargetLink {
		t.Errorf("other buckets missing links: %+v", links)
	}
	// the merged user must still have a full path
	if len(userPaths["user:__other__"]) == 0 {
		t.Errorf("other user has no path")
	}
}

func TestHourlyRange(t *testing.T) {
	st, err := openStore(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	base := time.Unix(1700000000, 0).Truncate(time.Hour)
	if err := st.addTraffic("vmess", "alice", 100, 200, base); err != nil {
		t.Fatal(err)
	}
	if err := st.addTraffic("anytls", "bob", 300, 400, base.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}

	rows, err := st.hourlyRange(base.Unix()-3600, base.Unix()+7200, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 {
		t.Fatalf("expected 2 rows, got %d", len(rows))
	}

	rows, err = st.hourlyRange(base.Unix()-3600, base.Unix()+7200, []string{"vmess"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Protocol != "vmess" || rows[0].Username != "alice" {
		t.Errorf("protocol filter failed: %+v", rows)
	}

	rows, err = st.hourlyRange(base.Unix()-3600, base.Unix()+7200, nil, []string{"bob"})
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Protocol != "anytls" || rows[0].Username != "bob" {
		t.Errorf("username filter failed: %+v", rows)
	}
}
