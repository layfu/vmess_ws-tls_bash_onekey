package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const schema = `
CREATE TABLE IF NOT EXISTS counters (
  protocol TEXT NOT NULL,
  username TEXT NOT NULL,
  direction TEXT NOT NULL,
  value INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (protocol, username, direction)
);
CREATE TABLE IF NOT EXISTS totals (
  protocol TEXT NOT NULL,
  username TEXT NOT NULL,
  uplink INTEGER NOT NULL DEFAULT 0,
  downlink INTEGER NOT NULL DEFAULT 0,
  last_seen INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (protocol, username)
);
CREATE TABLE IF NOT EXISTS hourly (
  protocol TEXT NOT NULL,
  username TEXT NOT NULL,
  hour INTEGER NOT NULL,
  uplink INTEGER NOT NULL DEFAULT 0,
  downlink INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (protocol, username, hour)
);
CREATE TABLE IF NOT EXISTS connections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  protocol TEXT NOT NULL,
  username TEXT NOT NULL,
  source TEXT NOT NULL,
  target TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_connections_ts ON connections(ts);
`

type store struct {
	db *sql.DB
}

func openStore(path string) (*store, error) {
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		_ = os.MkdirAll(dir, 0o755)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	return &store{db: db}, nil
}

func (s *store) Close() error { return s.db.Close() }

func (s *store) loadCounters() (map[string]int64, error) {
	rows, err := s.db.Query(`SELECT protocol, username, direction, value FROM counters`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	m := make(map[string]int64)
	for rows.Next() {
		var p, u, d string
		var v int64
		if err := rows.Scan(&p, &u, &d, &v); err != nil {
			return nil, err
		}
		m[p+"|"+u+"|"+d] = v
	}
	return m, rows.Err()
}

func (s *store) saveCounter(protocol, username, direction string, value int64) error {
	_, err := s.db.Exec(
		`INSERT INTO counters (protocol, username, direction, value) VALUES (?, ?, ?, ?)
		 ON CONFLICT(protocol, username, direction) DO UPDATE SET value = excluded.value`,
		protocol, username, direction, value,
	)
	return err
}

func (s *store) addTraffic(protocol, username string, uplink, downlink int64, now time.Time) error {
	hour := now.Truncate(time.Hour).Unix()
	_, err := s.db.Exec(
		`INSERT INTO totals (protocol, username, uplink, downlink, last_seen) VALUES (?, ?, ?, ?, ?)
		 ON CONFLICT(protocol, username) DO UPDATE SET
		   uplink = uplink + excluded.uplink,
		   downlink = downlink + excluded.downlink,
		   last_seen = excluded.last_seen`,
		protocol, username, uplink, downlink, now.Unix(),
	)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(
		`INSERT INTO hourly (protocol, username, hour, uplink, downlink) VALUES (?, ?, ?, ?, ?)
		 ON CONFLICT(protocol, username, hour) DO UPDATE SET
		   uplink = uplink + excluded.uplink,
		   downlink = downlink + excluded.downlink`,
		protocol, username, hour, uplink, downlink,
	)
	return err
}

func (s *store) addConnection(protocol, username, source, target string, ts time.Time) error {
	_, err := s.db.Exec(
		`INSERT INTO connections (ts, protocol, username, source, target) VALUES (?, ?, ?, ?, ?)`,
		ts.Unix(), protocol, username, source, target,
	)
	return err
}

func (s *store) updateConnectionSource(oldSource, newSource string) error {
	_, err := s.db.Exec(`UPDATE connections SET source = ? WHERE source = ?`, newSource, oldSource)
	return err
}

type totalRow struct {
	Protocol string
	Username string
	Uplink   int64
	Downlink int64
	LastSeen int64
}

func (s *store) totals() ([]totalRow, error) {
	rows, err := s.db.Query(`SELECT protocol, username, uplink, downlink, last_seen FROM totals ORDER BY protocol, username`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []totalRow
	for rows.Next() {
		var r totalRow
		if err := rows.Scan(&r.Protocol, &r.Username, &r.Uplink, &r.Downlink, &r.LastSeen); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

type hourlyRow struct {
	Hour     int64
	Uplink   int64
	Downlink int64
}

func (s *store) hourly(protocol, username string, since time.Time) ([]hourlyRow, error) {
	rows, err := s.db.Query(
		`SELECT hour, uplink, downlink FROM hourly WHERE protocol = ? AND username = ? AND hour >= ? ORDER BY hour`,
		protocol, username, since.Truncate(time.Hour).Unix(),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []hourlyRow
	for rows.Next() {
		var r hourlyRow
		if err := rows.Scan(&r.Hour, &r.Uplink, &r.Downlink); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

type connectionRow struct {
	TS       int64
	Protocol string
	Username string
	Source   string
	Target   string
}

func (s *store) connections(limit int, protocol, username string) ([]connectionRow, error) {
	q := `SELECT ts, protocol, username, source, target FROM connections`
	var args []any
	var conds []string
	if protocol != "" {
		conds = append(conds, `protocol = ?`)
		args = append(args, protocol)
	}
	if username != "" {
		conds = append(conds, `username = ?`)
		args = append(args, username)
	}
	if len(conds) > 0 {
		q += ` WHERE ` + strings.Join(conds, ` AND `)
	}
	q += ` ORDER BY id DESC LIMIT ?`
	args = append(args, limit)

	rows, err := s.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []connectionRow
	for rows.Next() {
		var r connectionRow
		if err := rows.Scan(&r.TS, &r.Protocol, &r.Username, &r.Source, &r.Target); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *store) prune(maxAge time.Duration, maxRows int) {
	if maxAge > 0 {
		cutoff := time.Now().Add(-maxAge).Unix()
		_, _ = s.db.Exec(`DELETE FROM connections WHERE ts < ?`, cutoff)
		_, _ = s.db.Exec(`DELETE FROM hourly WHERE hour < ?`, cutoff)
	}
	if maxRows > 0 {
		_, _ = s.db.Exec(`DELETE FROM connections WHERE id NOT IN (SELECT id FROM connections ORDER BY id DESC LIMIT ?)`, maxRows)
	}
}
