package main

import (
	"bytes"
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

	m := newSingboxMatcher(st)

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
