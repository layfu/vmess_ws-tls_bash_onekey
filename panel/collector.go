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

// statUserName returns the sing-box stats counter user name for a protocol. The
// installer namespaces user names with "v:"/"a:" so the per-user counters are
// independent per protocol; otherwise a same-named user across protocols shares
// one counter and the per-protocol split is lost.
func statUserName(protocol, user string) string {
	switch protocol {
	case "vmess":
		return "v:" + user
	case "anytls":
		return "a:" + user
	default:
		return user
	}
}

func newCollector(st *store, cfg *Config, onlineWindow int) (*collector, error) {
	c := &collector{
		store:    st,
		counters: make(map[string]int64),
		online:   onlineWindow,
	}

	if cfg.VMess.Enabled && cfg.VMess.APIAddr != "" {
		src, err := newStatsSource(cfg.VMess.APIAddr)
		if err != nil {
			log.Printf("vmess stats api %s: %v", cfg.VMess.APIAddr, err)
		} else {
			c.sources = append(c.sources, &protoSource{protocol: "vmess", source: src, usersFile: cfg.VMess.UsersFile})
		}
	}
	// sing-box 同时承载 VMess 与 AnyTLS，只要配置了统计地址就采集（用户文件为空则跳过）。
	if cfg.SingBox.APIAddr != "" {
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
			statUser := statUserName(ps.protocol, user)
			up := counters["user>>>"+statUser+">>>traffic>>>uplink"]
			down := counters["user>>>"+statUser+">>>traffic>>>downlink"]
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
			c.collectUserOutbound(counters, ps.protocol, user, statUser, now)
		}
	}
}

// outboundTags are the sing-box outbound tags tracked via the v2ray_api stats.
var outboundTags = []string{"direct", "block", "warp"}

// collectUserOutbound records the exact per-(user, protocol, outbound) byte
// deltas from the custom user_outbound>>> counter. On binaries without the
// patch the counter is absent, so every delta is zero and nothing is stored.
func (c *collector) collectUserOutbound(counters map[string]int64, protocol, user, statUser string, now time.Time) {
	hour := now.Truncate(time.Hour).Unix()
	for _, tag := range outboundTags {
		prefix := "user_outbound>>>" + statUser + ">>>" + tag + ">>>traffic>>>"
		up := counters[prefix+"uplink"]
		down := counters[prefix+"downlink"]
		c.mu.Lock()
		lastUp := c.counters["user_outbound|"+protocol+"|"+user+"|"+tag+"|up"]
		lastDown := c.counters["user_outbound|"+protocol+"|"+user+"|"+tag+"|down"]
		dUp := up - lastUp
		dDown := down - lastDown
		if dUp < 0 {
			dUp = up
		}
		if dDown < 0 {
			dDown = down
		}
		c.counters["user_outbound|"+protocol+"|"+user+"|"+tag+"|up"] = up
		c.counters["user_outbound|"+protocol+"|"+user+"|"+tag+"|down"] = down
		c.mu.Unlock()
		if dUp == 0 && dDown == 0 {
			continue
		}
		status := tag
		if tag == "block" {
			status = "blocked"
		}
		if err := c.store.addUserOutboundTraffic(user, protocol, status, hour, dUp, dDown); err != nil {
			log.Printf("store addUserOutboundTraffic: %v", err)
		}
	}
}

// readUsers returns the usernames from a users file. The file format is
// "name <secret>" per line (same for VMess UUID and sing-box password).
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
