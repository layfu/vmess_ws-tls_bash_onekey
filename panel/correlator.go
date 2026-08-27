package main

import (
	"log"
	"sync"
	"time"
)

// correlator matches VMess connections (from v2ray access log, which only
// sees the Nginx loopback source 127.0.0.1:port) with the real client IP
// (from the Nginx WebSocket access log) by timestamp.
type vmessEntry struct {
	ts     int64
	user   string
	target string
	src    string // v2ray-observed source, e.g. "127.0.0.1:54321"
}

type wsEntry struct {
	ts int64
	ip string
}

const (
	matchWindowSec = 3
	pruneAfterSec  = 600
)

type correlator struct {
	mu    sync.Mutex
	store *store
	vmess []vmessEntry
	ws    []wsEntry
}

func newCorrelator(st *store) *correlator {
	return &correlator{store: st}
}

func (c *correlator) addVmess(ts int64, user, target, src string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.vmess = append(c.vmess, vmessEntry{ts: ts, user: user, target: target, src: src})
	c.matchLocked()
	c.pruneLocked()
}

func (c *correlator) addWs(ts int64, ip string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.ws = append(c.ws, wsEntry{ts: ts, ip: ip})
	c.matchLocked()
	c.pruneLocked()
}

func (c *correlator) matchLocked() {
	for wi := 0; wi < len(c.ws); wi++ {
		w := c.ws[wi]
		best := -1
		bestDiff := int64(matchWindowSec) + 1
		for vi := 0; vi < len(c.vmess); vi++ {
			d := w.ts - c.vmess[vi].ts
			if d < 0 {
				d = -d
			}
			if d < bestDiff {
				bestDiff = d
				best = vi
			}
		}
		if best >= 0 && bestDiff <= matchWindowSec {
			v := c.vmess[best]
			if err := c.store.updateConnectionSource(v.src, w.ip); err != nil {
				log.Printf("update source: %v", err)
			}
			c.vmess = append(c.vmess[:best], c.vmess[best+1:]...)
			c.ws = append(c.ws[:wi], c.ws[wi+1:]...)
			wi--
		}
	}
}

func (c *correlator) pruneLocked() {
	cutoff := time.Now().Unix() - pruneAfterSec
	if len(c.vmess) > 0 {
		kept := c.vmess[:0]
		for _, e := range c.vmess {
			if e.ts >= cutoff {
				kept = append(kept, e)
			}
		}
		c.vmess = kept
	}
	if len(c.ws) > 0 {
		kept := c.ws[:0]
		for _, e := range c.ws {
			if e.ts >= cutoff {
				kept = append(kept, e)
			}
		}
		c.ws = kept
	}
}
