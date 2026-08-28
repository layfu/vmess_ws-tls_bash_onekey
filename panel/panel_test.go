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
	line := "2026/08/27 12:00:00 1.2.3.4:54321 accepted tcp:example.com:443 email: user1"
	p, u, src, dst, ts, ok := parseV2rayLine(line)
	if !ok {
		t.Fatalf("expected ok")
	}
	if p != "vmess" || u != "user1" || src != "1.2.3.4:54321" || dst != "example.com:443" {
		t.Errorf("got %q %q %q %q", p, u, src, dst)
	}
	if ts <= 0 {
		t.Errorf("expected positive timestamp, got %d", ts)
	}

	rej := "2026/08/27 12:00:00 5.6.7.8:9999 rejected  email: user2"
	if _, _, _, _, _, ok := parseV2rayLine(rej); ok {
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

func TestParseSingboxLine(t *testing.T) {
	withUser := "+0800 2026-08-27 12:00:00 INFO [123 12s] inbound/anytls[anytls-in]: [user1] inbound connection from 1.2.3.4:54321 to example.com:443"
	p, u, src, dst, ok := parseSingboxLine(withUser)
	if !ok {
		t.Fatalf("expected ok")
	}
	if p != "anytls" || u != "user1" || src != "1.2.3.4:54321" || dst != "example.com:443" {
		t.Errorf("got %q %q %q %q", p, u, src, dst)
	}

	// 官方 sing-box 不记录来源（只有目标）
	noSource := "INFO inbound/anytls[anytls-in]: [user1] inbound connection to example.com:443"
	p, u, src, dst, ok = parseSingboxLine(noSource)
	if !ok || p != "anytls" || u != "user1" || src != "" || dst != "example.com:443" {
		t.Errorf("got %q %q %q %q %v", p, u, src, dst, ok)
	}

	noUser := "INFO inbound/anytls[anytls-in]: inbound connection from 5.6.7.8:9999 to 1.2.3.4:443"
	_, u2, src2, dst2, ok := parseSingboxLine(noUser)
	if !ok || u2 != "" || src2 != "5.6.7.8:9999" || dst2 != "1.2.3.4:443" {
		t.Errorf("got %q %q %q %v", u2, src2, dst2, ok)
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

	_ = st.addConnection("vmess", "user1", "127.0.0.1:54321", "example.com:443", time.Unix(now, 0))
	c.addVmess(now, "user1", "example.com:443", "127.0.0.1:54321")
	c.addWs(now+1, "9.9.9.9")

	rows, err := st.connections(10, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Source != "9.9.9.9" {
		t.Errorf("expected source 9.9.9.9, got %+v", rows)
	}
}
