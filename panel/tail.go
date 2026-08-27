package main

import (
	"bufio"
	"io"
	"log"
	"os"
	"regexp"
	"strings"
	"time"
)

// v2ray access log line:
//
//	2006/01/02 15:04:05 1.2.3.4:12345 accepted tcp:example.com:443 [detour] email: user1
var v2rayRe = regexp.MustCompile(`^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})\s+(\S+)\s+(accepted|rejected)\s+(\S+)`)
var v2rayEmailRe = regexp.MustCompile(`email:\s*(\S+)`)

// sing-box info log line for an AnyTLS inbound connection:
//
//	+0800 2026-08-27 12:00:00 INFO [id 12s] inbound/anytls[anytls-in]: [user1] inbound connection from 1.2.3.4:12345 to example.com:443
//
// Older/官方 sing-box 只记录 "inbound connection to {dest}"（无来源），此时 source 为空。
var sbInboundRe = regexp.MustCompile(`(?:\[([^\]]+)\]\s+)?inbound connection (?:from (\S+) )?to (\S+)`)

func parseV2rayLine(line string) (protocol, username, source, target string, ok bool) {
	m := v2rayRe.FindStringSubmatch(line)
	if m == nil {
		return "", "", "", "", false
	}
	source = m[2]
	status := m[3]
	targetRaw := m[4]
	if status != "accepted" || targetRaw == "" {
		return "", "", "", "", false
	}
	target = stripNetPrefix(targetRaw)
	if target == "" {
		return "", "", "", "", false
	}
	if em := v2rayEmailRe.FindStringSubmatch(line); em != nil {
		username = em[1]
	}
	return "vmess", username, source, target, true
}

func parseSingboxLine(line string) (protocol, username, source, target string, ok bool) {
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
	return "anytls", username, source, target, true
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
	if cfg.V2Ray.Enabled && cfg.V2Ray.AccessLog != "" {
		go followFile(cfg.V2Ray.AccessLog, func(line string) {
			p, u, src, dst, ok := parseV2rayLine(line)
			if ok {
				_ = st.addConnection(p, u, src, dst, time.Now())
			}
		})
	}
	if cfg.SingBox.Enabled && cfg.SingBox.LogFile != "" {
		go followFile(cfg.SingBox.LogFile, func(line string) {
			p, u, src, dst, ok := parseSingboxLine(line)
			if ok {
				_ = st.addConnection(p, u, src, dst, time.Now())
			}
		})
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
