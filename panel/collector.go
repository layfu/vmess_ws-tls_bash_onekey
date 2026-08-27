package main

import (
	"bufio"
	"context"
	"log"
	"os"
	"strings"
	"sync"
	"time"
)

type protoSource struct {
	protocol  string
	source    *statsSource
	usersFile string
	users     []string
}

type collector struct {
	store    *store
	sources  []*protoSource
	counters map[string]int64
	mu       sync.Mutex
	online   int // seconds window for "online"
}

func newCollector(st *store, cfg *Config, onlineWindow int) (*collector, error) {
	c := &collector{
		store:    st,
		counters: make(map[string]int64),
		online:   onlineWindow,
	}

	if cfg.V2Ray.Enabled && cfg.V2Ray.APIAddr != "" {
		src, err := newStatsSource(cfg.V2Ray.APIAddr)
		if err != nil {
			log.Printf("v2ray stats api %s: %v", cfg.V2Ray.APIAddr, err)
		} else {
			c.sources = append(c.sources, &protoSource{protocol: "vmess", source: src, usersFile: cfg.V2Ray.UsersFile})
		}
	}
	if cfg.SingBox.Enabled && cfg.SingBox.APIAddr != "" {
		src, err := newStatsSource(cfg.SingBox.APIAddr)
		if err != nil {
			log.Printf("sing-box stats api %s: %v", cfg.SingBox.APIAddr, err)
		} else {
			c.sources = append(c.sources, &protoSource{protocol: "anytls", source: src, usersFile: cfg.SingBox.UsersFile})
		}
	}

	m, err := st.loadCounters()
	if err != nil {
		return nil, err
	}
	c.counters = m
	return c, nil
}

func (c *collector) Close() {
	for _, s := range c.sources {
		s.source.Close()
	}
}

func (c *collector) run(ctx context.Context, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	c.poll(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			c.poll(ctx)
		}
	}
}

func (c *collector) poll(ctx context.Context) {
	for _, ps := range c.sources {
		ps.users = readUsers(ps.usersFile, ps.users)
		if len(ps.users) == 0 {
			continue
		}
		pctx, cancel := context.WithTimeout(ctx, 8*time.Second)
		counters, err := ps.source.query(pctx)
		cancel()
		if err != nil {
			log.Printf("stats query %s: %v", ps.protocol, err)
			continue
		}
		now := time.Now()
		for _, user := range ps.users {
			up := counters["user>>>"+user+">>>traffic>>>uplink"]
			down := counters["user>>>"+user+">>>traffic>>>downlink"]
			c.mu.Lock()
			lastUp := c.counters[ps.protocol+"|"+user+"|up"]
			lastDown := c.counters[ps.protocol+"|"+user+"|down"]
			dUp := up - lastUp
			dDown := down - lastDown
			if dUp < 0 {
				dUp = up
			}
			if dDown < 0 {
				dDown = down
			}
			c.counters[ps.protocol+"|"+user+"|up"] = up
			c.counters[ps.protocol+"|"+user+"|down"] = down
			c.mu.Unlock()

			if dUp != 0 || dDown != 0 {
				if err := c.store.addTraffic(ps.protocol, user, dUp, dDown, now); err != nil {
					log.Printf("store addTraffic: %v", err)
				}
			}
			_ = c.store.saveCounter(ps.protocol, user, "up", up)
			_ = c.store.saveCounter(ps.protocol, user, "down", down)
		}
	}
}

// readUsers returns the usernames from a users file. The file format is
// "name <secret>" per line (same for v2ray uuid and sing-box password).
func readUsers(path string, cached []string) []string {
	if path == "" {
		return cached
	}
	f, err := os.Open(path)
	if err != nil {
		return cached
	}
	defer f.Close()
	var users []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		users = append(users, fields[0])
	}
	if len(users) == 0 {
		return cached
	}
	return users
}
