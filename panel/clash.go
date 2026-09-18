package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
)

// clashPoller periodically reads sing-box's Clash API /connections endpoint and
// accumulates per-destination traffic. This is the only source that exposes
// per-target bytes (sing-box stats only aggregate per user/inbound/
// outbound). Only active connections are visible, so very short connections
// between polls are not counted; long-lived transfers dominate the totals.
type clashPoller struct {
	store     *store
	addr      string
	client    *http.Client
	mu        sync.Mutex
	last      map[string]clashConnBytes
	buf       map[targetKey]trafficDelta
	lastDebug time.Time
	firstPoll bool
}

type clashConnBytes struct {
	up, down int64
}

type targetKey struct {
	username string
	protocol string
	host     string
	status   string
}

type trafficDelta struct {
	up, down int64
}

type clashConnection struct {
	ID       string `json:"id"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
	Metadata struct {
		Type          string `json:"type"`
		Host          string `json:"host"`
		DestinationIP string `json:"destinationIP"`
		User          string `json:"user"`
	} `json:"metadata"`
	Chains []string `json:"chains"`
}

type clashSnapshot struct {
	Connections []clashConnection `json:"connections"`
}

func newClashPoller(st *store, addr string) *clashPoller {
	last, err := st.loadClashConns()
	if err != nil {
		log.Printf("clash: load seen connections: %v", err)
	}
	if last == nil {
		last = make(map[string]clashConnBytes)
	}
	return &clashPoller{
		store:     st,
		addr:      addr,
		client:    &http.Client{Timeout: 3 * time.Second},
		last:      last,
		buf:       make(map[targetKey]trafficDelta),
		firstPoll: len(last) == 0,
	}
}

func (p *clashPoller) run(ctx context.Context, interval time.Duration) {
	poll := time.NewTicker(interval)
	flush := time.NewTicker(30 * time.Second)
	defer poll.Stop()
	defer flush.Stop()
	for {
		select {
		case <-ctx.Done():
			p.flush()
			return
		case <-poll.C:
			p.poll(ctx)
		case <-flush.C:
			p.flush()
		}
	}
}

func (p *clashPoller) poll(ctx context.Context) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://"+p.addr+"/connections", nil)
	if err != nil {
		return
	}
	resp, err := p.client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return
	}
	var snap clashSnapshot
	if err := json.NewDecoder(resp.Body).Decode(&snap); err != nil {
		return
	}

	// Diagnostic: dump a few raw connections once a minute so the topology's
	// target layer can be debugged (check `journalctl -u panel | grep clash:`).
	if time.Since(p.lastDebug) >= time.Minute {
		p.lastDebug = time.Now()
		log.Printf("clash: %d connections (active + recently closed)", len(snap.Connections))
		for i, c := range snap.Connections {
			if i >= 8 {
				break
			}
			log.Printf("clash: type=%q user=%q host=%q dst=%q chains=%v up=%d down=%d",
				c.Metadata.Type, c.Metadata.User, c.Metadata.Host, c.Metadata.DestinationIP,
				c.Chains, c.Upload, c.Download)
		}
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	baseline := p.firstPoll
	p.firstPoll = false
	seen := make(map[string]bool, len(snap.Connections))
	for _, c := range snap.Connections {
		seen[c.ID] = true
		du, dd := c.Upload, c.Download
		if last, ok := p.last[c.ID]; ok {
			du = c.Upload - last.up
			dd = c.Download - last.down
		}
		if du < 0 {
			du = c.Upload
		}
		if dd < 0 {
			dd = c.Download
		}
		p.last[c.ID] = clashConnBytes{up: c.Upload, down: c.Download}
		if baseline {
			// First run: record what already exists (including sing-box's
			// buffered closed connections) without attributing it to "now".
			continue
		}
		if du == 0 && dd == 0 {
			continue
		}
		host := c.Metadata.Host
		if host == "" {
			host = c.Metadata.DestinationIP
		}
		host = strings.TrimSpace(host)
		if host == "" {
			continue
		}
		key := targetKey{
			username: clashUser(c.Metadata.User),
			protocol: clashProtocol(c.Metadata.Type),
			host:     strings.ToLower(host),
			status:   clashStatus(c.Chains),
		}
		d := p.buf[key]
		d.up += du
		d.down += dd
		p.buf[key] = d
	}
	for id := range p.last {
		if !seen[id] {
			delete(p.last, id)
		}
	}
}

func (p *clashPoller) flush() {
	p.mu.Lock()
	buf := p.buf
	p.buf = make(map[targetKey]trafficDelta)
	seen := make(map[string]clashConnBytes, len(p.last))
	for id, b := range p.last {
		seen[id] = b
	}
	p.mu.Unlock()
	// Persist the last-seen byte counts so a restart resumes deltas instead of
	// re-counting connections (active or closed) it already accounted for.
	if err := p.store.saveClashConns(seen); err != nil {
		log.Printf("clash: save seen connections: %v", err)
	}
	if len(buf) == 0 {
		return
	}
	hour := time.Now().Truncate(time.Hour).Unix()
	for k, d := range buf {
		if err := p.store.addUserTargetTraffic(k.username, k.protocol, k.host, k.status, hour, d.up, d.down); err != nil {
			log.Printf("clash flush: %v", err)
		}
	}
}

// clashUser strips the installer's protocol namespace ("v:"/"a:") from the
// sing-box user name exposed by the patched Clash API, so it matches the
// per-user stats and the users files.
func clashUser(user string) string {
	if strings.HasPrefix(user, "v:") || strings.HasPrefix(user, "a:") {
		return user[2:]
	}
	return user
}

func clashProtocol(inbound string) string {
	switch {
	case strings.HasPrefix(inbound, "vmess"):
		return "vmess"
	case strings.HasPrefix(inbound, "anytls"):
		return "anytls"
	default:
		return "unknown"
	}
}

func clashStatus(chains []string) string {
	for _, c := range chains {
		switch c {
		case "block", "blocked":
			return "blocked"
		case "warp":
			return "warp"
		}
	}
	return "direct"
}
