package main

import (
	"context"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// serverLocation is the coarse position of the panel server, used as the hub
// node that client routes converge on.
type serverLocation struct {
	Lat  float64 `json:"lat"`
	Lng  float64 `json:"lng"`
	Name string  `json:"name"`
}

// serverLocator resolves the server's own location. An explicit config value
// wins; otherwise it detects the public egress IP once and geolocates it. The
// cached value is refreshed periodically so a failed startup detection can
// recover without restarting the panel.
type serverLocator struct {
	cfg *Config
	geo *geoLookup
	mu  sync.Mutex
	loc *serverLocation
}

func newServerLocator(cfg *Config, geo *geoLookup) *serverLocator {
	s := &serverLocator{cfg: cfg, geo: geo}
	if cfg.ServerLat != 0 || cfg.ServerLng != 0 {
		s.loc = s.resolve()
	}
	return s
}

func (s *serverLocator) run(ctx context.Context) {
	s.refresh()
	t := time.NewTicker(30 * time.Minute)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.refresh()
		}
	}
}

func (s *serverLocator) get() *serverLocation {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.loc
}

func (s *serverLocator) refresh() {
	loc := s.resolve()
	s.mu.Lock()
	s.loc = loc
	s.mu.Unlock()
}

func (s *serverLocator) resolve() *serverLocation {
	if s.cfg.ServerLat != 0 || s.cfg.ServerLng != 0 {
		name := s.cfg.ServerName
		if name == "" {
			name = "服务器"
		}
		return &serverLocation{Lat: s.cfg.ServerLat, Lng: s.cfg.ServerLng, Name: name}
	}
	if s.geo == nil {
		return nil
	}
	ip := detectPublicIP()
	if ip == "" {
		return nil
	}
	region, lat, lng, ok := s.geo.lookupPoint(ip)
	if !ok {
		return nil
	}
	if region == "" {
		region = "服务器"
	}
	return &serverLocation{Lat: lat, Lng: lng, Name: region}
}

// publicIPServices are tried in order; the first valid IP wins.
var publicIPServices = []string{
	"https://api.ipify.org",
	"https://ifconfig.me/ip",
	"https://ipinfo.io/ip",
}

// detectPublicIP returns the host's public egress IP, or "" if it cannot be
// determined. Best-effort: any failure simply disables the server node.
func detectPublicIP() string {
	client := &http.Client{Timeout: 3 * time.Second}
	for _, url := range publicIPServices {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			cancel()
			continue
		}
		resp, err := client.Do(req)
		if err != nil {
			cancel()
			continue
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 64))
		resp.Body.Close()
		cancel()
		if err != nil || resp.StatusCode != http.StatusOK {
			continue
		}
		ip := strings.TrimSpace(string(body))
		if net.ParseIP(ip) != nil {
			return ip
		}
	}
	log.Printf("server location: public IP detection failed")
	return ""
}
