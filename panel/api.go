package main

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"
)

type api struct {
	store     *store
	cfg       *Config
	onlineWin int64
}

type userInfo struct {
	Protocol string `json:"protocol"`
	Username string `json:"username"`
	Uplink   int64  `json:"uplink"`
	Downlink int64  `json:"downlink"`
	Total    int64  `json:"total"`
	LastSeen int64  `json:"last_seen"`
	Online   bool   `json:"online"`
}

func (a *api) overview(w http.ResponseWriter, r *http.Request) {
	totals, err := a.store.totals()
	if err != nil {
		writeErr(w, err)
		return
	}
	now := time.Now().Unix()
	users := make([]userInfo, 0, len(totals))
	var totalUp, totalDown int64
	for _, t := range totals {
		users = append(users, userInfo{
			Protocol: t.Protocol,
			Username: t.Username,
			Uplink:   t.Uplink,
			Downlink: t.Downlink,
			Total:    t.Uplink + t.Downlink,
			LastSeen: t.LastSeen,
			Online:   t.LastSeen > 0 && now-t.LastSeen <= a.onlineWin,
		})
		totalUp += t.Uplink
		totalDown += t.Downlink
	}
	writeJSON(w, map[string]any{
		"users":      users,
		"total_up":   totalUp,
		"total_down": totalDown,
		"updated_at": now,
	})
}

type hourlyPoint struct {
	Hour     int64 `json:"hour"`
	Uplink   int64 `json:"uplink"`
	Downlink int64 `json:"downlink"`
}

func (a *api) traffic(w http.ResponseWriter, r *http.Request) {
	hours, _ := strconv.Atoi(r.URL.Query().Get("hours"))
	if hours <= 0 || hours > 24*7 {
		hours = 24
	}
	since := time.Now().Add(-time.Duration(hours) * time.Hour)
	totals, err := a.store.totals()
	if err != nil {
		writeErr(w, err)
		return
	}
	series := map[string][]hourlyPoint{}
	for _, t := range totals {
		rows, err := a.store.hourly(t.Protocol, t.Username, since)
		if err != nil {
			continue
		}
		pts := make([]hourlyPoint, 0, len(rows))
		for _, r := range rows {
			pts = append(pts, hourlyPoint{Hour: r.Hour, Uplink: r.Uplink, Downlink: r.Downlink})
		}
		series[t.Protocol+":"+t.Username] = pts
	}
	writeJSON(w, map[string]any{"series": series})
}

type connInfo struct {
	TS       int64  `json:"ts"`
	Protocol string `json:"protocol"`
	Username string `json:"username"`
	Source   string `json:"source"`
	Target   string `json:"target"`
}

func (a *api) connections(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 200
	}
	if limit > 1000 {
		limit = 1000
	}
	rows, err := a.store.connections(limit)
	if err != nil {
		writeErr(w, err)
		return
	}
	out := make([]connInfo, 0, len(rows))
	for _, r := range rows {
		out = append(out, connInfo{TS: r.TS, Protocol: r.Protocol, Username: r.Username, Source: r.Source, Target: r.Target})
	}
	writeJSON(w, map[string]any{"connections": out})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, err error) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusInternalServerError)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}
