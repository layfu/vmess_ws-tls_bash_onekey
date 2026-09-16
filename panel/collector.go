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
	protocol     string
	source       *statsSource
	usersFile    string
	users        []string
	readOutbound bool
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

	if cfg.V2Ray.Enabled && cfg.V2Ray.APIAddr != "" {
		src, err := newStatsSource(cfg.V2Ray.APIAddr)
		if err != nil {
			log.Printf("v2ray stats api %s: %v", cfg.V2Ray.APIAddr, err)
		} else {
			c.sources = append(c.sources, &protoSource{protocol: "vmess", source: src, usersFile: cfg.V2Ray.UsersFile})
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

	// outbound 统计是全局的（不区分协议/用户），两个 stats 源指向同一个 API，
	// 只让其中一个源读取，避免重复计数。
	if len(c.sources) > 0 {
		c.sources[0].readOutbound = true
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
		if len(ps.users) == 0 && !ps.readOutbound {
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
		}
		if ps.readOutbound {
			c.collectOutbound(counters, now)
			c.collectInbound(counters, now)
		}
	}
}

// outboundTags are the sing-box outbound tags tracked via the v2ray_api stats.
var outboundTags = []string{"direct", "block", "warp"}

// collectOutbound records per-outbound byte deltas (accurate, same source as
// the per-user stats) so the topology's outbound layer matches the totals.
func (c *collector) collectOutbound(counters map[string]int64, now time.Time) {
	hour := now.Truncate(time.Hour).Unix()
	for _, tag := range outboundTags {
		up := counters["outbound>>>"+tag+">>>traffic>>>uplink"]
		down := counters["outbound>>>"+tag+">>>traffic>>>downlink"]
		c.mu.Lock()
		lastUp := c.counters["outbound|"+tag+"|up"]
		lastDown := c.counters["outbound|"+tag+"|down"]
		dUp := up - lastUp
		dDown := down - lastDown
		if dUp < 0 {
			dUp = up
		}
		if dDown < 0 {
			dDown = down
		}
		c.counters["outbound|"+tag+"|up"] = up
		c.counters["outbound|"+tag+"|down"] = down
		c.mu.Unlock()
		if dUp != 0 || dDown != 0 {
			if err := c.store.addOutboundTraffic(tag, hour, dUp, dDown); err != nil {
				log.Printf("store addOutboundTraffic: %v", err)
			}
		}
		_ = c.store.saveCounter("outbound", tag, "up", up)
		_ = c.store.saveCounter("outbound", tag, "down", down)
	}
}

// inboundTagProtocol maps the sing-box inbound tags to protocols, so the
// topology's protocol layer is measured accurately per protocol (the per-user
// stats are shared by name across protocols and can't be split).
var inboundTagProtocol = []struct{ tag, protocol string }{
	{"vmess-in", "vmess"},
	{"anytls-in", "anytls"},
}

// collectInbound records per-protocol byte deltas from the inbound stats.
func (c *collector) collectInbound(counters map[string]int64, now time.Time) {
	hour := now.Truncate(time.Hour).Unix()
	for _, it := range inboundTagProtocol {
		up := counters["inbound>>>"+it.tag+">>>traffic>>>uplink"]
		down := counters["inbound>>>"+it.tag+">>>traffic>>>downlink"]
		c.mu.Lock()
		lastUp := c.counters["inbound|"+it.protocol+"|up"]
		lastDown := c.counters["inbound|"+it.protocol+"|down"]
		dUp := up - lastUp
		dDown := down - lastDown
		if dUp < 0 {
			dUp = up
		}
		if dDown < 0 {
			dDown = down
		}
		c.counters["inbound|"+it.protocol+"|up"] = up
		c.counters["inbound|"+it.protocol+"|down"] = down
		c.mu.Unlock()
		if dUp != 0 || dDown != 0 {
			if err := c.store.addInboundTraffic(it.protocol, hour, dUp, dDown); err != nil {
				log.Printf("store addInboundTraffic: %v", err)
			}
		}
		_ = c.store.saveCounter("inbound", it.protocol, "up", up)
		_ = c.store.saveCounter("inbound", it.protocol, "down", down)
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
