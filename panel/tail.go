package main

import (
	"bufio"
	"io"
	"log"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
)

// v2ray access log line:
//
//	2006/01/02 15:04:05 1.2.3.4:12345 accepted tcp:example.com:443 [detour] email: user1
//
// detour is the outbound tag: direct / warp / blocked.
var v2rayRe = regexp.MustCompile(`^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\s+(\S+)\s+(accepted|rejected)\s+(\S+)(?:\s+\[([^\]]+)\])?`)
var v2rayEmailRe = regexp.MustCompile(`email:\s*(\S+)`)

// sing-box info log line for an AnyTLS inbound connection:
//
//	+0800 2026-08-27 12:00:00 INFO [id 12s] inbound/anytls[anytls-in]: [user1] inbound connection from 1.2.3.4:12345 to example.com:443
//
// Older/官方 sing-box 只记录 "inbound connection to {dest}"（无来源），此时 source 为空。
// The log connection id (the numeric part of "[id 12s]") is shared between the
// inbound and outbound lines, so it is used to correlate them.
var sbIDRe = regexp.MustCompile(`\[(\d+)\s+\S+\]`)
var sbInboundRe = regexp.MustCompile(`(?:\[([^\]]+)\]\s+)?inbound connection (?:from (\S+) )?to (\S+)`)
var sbOutboundRe = regexp.MustCompile(`outbound/\S+\[([^\]]+)\]:\s+(outbound|blocked) connection to\s+\S+`)

func parseV2rayLine(line string) (protocol, username, source, target, status string, ts int64, ok bool) {
	m := v2rayRe.FindStringSubmatch(line)
	if m == nil {
		return "", "", "", "", "", 0, false
	}
	ts = parseV2rayTime(m[1])
	source = m[2]
	acc := m[3]
	targetRaw := m[4]
	if acc != "accepted" || targetRaw == "" {
		return "", "", "", "", "", ts, false
	}
	target = stripNetPrefix(targetRaw)
	if target == "" {
		return "", "", "", "", "", ts, false
	}
	if em := v2rayEmailRe.FindStringSubmatch(line); em != nil {
		username = em[1]
	}
	return "vmess", username, source, target, m[5], ts, true
}

// parseV2rayTime parses the v2ray access log timestamp "2006/01/02 15:04:05"
// (server local time) into a Unix timestamp.
func parseV2rayTime(s string) int64 {
	t, err := time.ParseInLocation("2006/01/02 15:04:05", s, time.Local)
	if err != nil {
		return time.Now().Unix()
	}
	return t.Unix()
}

// parseNginxWsLine parses a Nginx WebSocket access log line:
//
//	1.2.3.4 2026-08-27T12:00:00+08:00 /e01ec5ea/ 101
func parseNginxWsLine(line string) (ip string, ts int64, ok bool) {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return "", 0, false
	}
	ip = fields[0]
	t, err := time.Parse(time.RFC3339, fields[1])
	if err != nil {
		return "", 0, false
	}
	return ip, t.Unix(), true
}

// parseSingboxInbound parses the AnyTLS inbound connection line, returning the
// log connection id, username, source and target.
func parseSingboxInbound(line string) (id, username, source, target string, ok bool) {
	idm := sbIDRe.FindStringSubmatch(line)
	if idm == nil {
		return "", "", "", "", false
	}
	m := sbInboundRe.FindStringSubmatch(line)
	if m == nil {
		return "", "", "", "", false
	}
	username = m[1]
	source = stripScheme(m[2])
	target = stripScheme(m[3])
	if target == "" {
		return "", "", "", "", false
	}
	return idm[1], username, source, target, true
}

// parseSingboxOutbound parses the AnyTLS outbound connection line, returning
// the log connection id and a normalized status (direct / warp / blocked).
func parseSingboxOutbound(line string) (id, status string, ok bool) {
	idm := sbIDRe.FindStringSubmatch(line)
	if idm == nil {
		return "", "", false
	}
	m := sbOutboundRe.FindStringSubmatch(line)
	if m == nil {
		return "", "", false
	}
	tag := m[1]
	kind := m[2]
	if kind == "blocked" || tag == "block" {
		status = "blocked"
	} else {
		status = tag
	}
	return idm[1], status, true
}

// singboxMatcher correlates the AnyTLS inbound connection line with its
// outbound line by the shared log connection id, so the panel can record the
// routing result (direct / warp / blocked) for each connection.
type singboxMatcher struct {
	store   *store
	mu      sync.Mutex
	pending map[string]sbPending
}

type sbPending struct {
	user   string
	source string
	target string
	ts     int64
}

func newSingboxMatcher(st *store) *singboxMatcher {
	return &singboxMatcher{store: st, pending: make(map[string]sbPending)}
}

func (m *singboxMatcher) handle(line string) {
	if id, status, ok := parseSingboxOutbound(line); ok {
		m.mu.Lock()
		p, found := m.pending[id]
		if found {
			delete(m.pending, id)
		}
		m.mu.Unlock()
		if found {
			_ = m.store.addConnection("anytls", p.user, p.source, p.target, status, time.Unix(p.ts, 0))
		}
		return
	}
	if id, user, source, target, ok := parseSingboxInbound(line); ok {
		m.mu.Lock()
		m.pending[id] = sbPending{user: user, source: source, target: target, ts: time.Now().Unix()}
		m.pruneLocked()
		m.mu.Unlock()
	}
}

func (m *singboxMatcher) pruneLocked() {
	cutoff := time.Now().Unix() - 30
	for id, p := range m.pending {
		if p.ts < cutoff {
			delete(m.pending, id)
		}
	}
}

func stripScheme(s string) string {
	if i := strings.Index(s, "://"); i >= 0 {
		return s[i+3:]
	}
	return s
}

func stripNetPrefix(s string) string {
	if i := strings.IndexByte(s, ':'); i >= 0 {
		return s[i+1:]
	}
	return s
}

func startLogTailers(st *store, cfg *Config) {
	corr := newCorrelator(st)
	if cfg.V2Ray.Enabled && cfg.V2Ray.AccessLog != "" {
		go followFile(cfg.V2Ray.AccessLog, func(line string) {
			p, u, src, dst, status, ts, ok := parseV2rayLine(line)
			if ok {
				_ = st.addConnection(p, u, src, dst, status, time.Unix(ts, 0))
				corr.addVmess(ts, u, dst, src)
			}
		})
	}
	if cfg.V2Ray.Enabled && cfg.V2Ray.WSAccessLog != "" {
		go followFile(cfg.V2Ray.WSAccessLog, func(line string) {
			ip, ts, ok := parseNginxWsLine(line)
			if ok {
				corr.addWs(ts, ip)
			}
		})
	}
	if cfg.SingBox.Enabled && cfg.SingBox.LogFile != "" {
		sb := newSingboxMatcher(st)
		go followFile(cfg.SingBox.LogFile, sb.handle)
	}
}

// followFile tails a file from its current end, calling onLine for each new
// line. It survives copytruncate-style rotation (reopens on truncation).
func followFile(path string, onLine func(string)) {
	if path == "" {
		return
	}
	f, err := os.Open(path)
	if err != nil {
		log.Printf("tail %s: %v", path, err)
		return
	}
	defer f.Close()
	if _, err := f.Seek(0, io.SeekEnd); err != nil {
		return
	}
	reader := bufio.NewReaderSize(f, 1<<20)
	offset := int64(0)
	if st, err := f.Stat(); err == nil {
		offset = st.Size()
	}
	for {
		line, err := reader.ReadString('\n')
		if line != "" {
			offset += int64(len(line))
			onLine(strings.TrimRight(line, "\r\n"))
			continue
		}
		time.Sleep(500 * time.Millisecond)
		st, statErr := os.Stat(path)
		if statErr == nil && st.Size() < offset {
			// file truncated by rotation; reopen from the beginning
			f.Close()
			nf, openErr := os.Open(path)
			if openErr != nil {
				return
			}
			f = nf
			reader = bufio.NewReaderSize(f, 1<<20)
			offset = 0
		} else if err != nil && err != io.EOF {
			// real error; try to reopen
			f.Close()
			nf, openErr := os.Open(path)
			if openErr != nil {
				return
			}
			f = nf
			reader = bufio.NewReaderSize(f, 1<<20)
			offset = 0
		}
	}
}
