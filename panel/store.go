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
  target TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_connections_ts ON connections(ts);
CREATE INDEX IF NOT EXISTS idx_hourly_hour ON hourly(hour);
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
	if err := migrate(db); err != nil {
		db.Close()
		return nil, err
	}
	return &store{db: db}, nil
}

// migrate adds columns introduced after the initial release without disturbing
// existing rows. SQLite lacks "ADD COLUMN IF NOT EXISTS", so we inspect the
// table columns first.
func migrate(db *sql.DB) error {
	migrations := []struct {
		table string
		add   []struct{ name, ddl string }
	}{
		{
			table: "connections",
			add: []struct{ name, ddl string }{
				{"status", `ALTER TABLE connections ADD COLUMN status TEXT NOT NULL DEFAULT ''`},
			},
		},
	}
	for _, m := range migrations {
		have, err := tableColumns(db, m.table)
		if err != nil {
			return err
		}
		for _, c := range m.add {
			if !have[c.name] {
				if _, err := db.Exec(c.ddl); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

func tableColumns(db *sql.DB, table string) (map[string]bool, error) {
	rows, err := db.Query(`PRAGMA table_info(` + table + `)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	have := map[string]bool{}
	for rows.Next() {
		var cid int
		var name, ctype string
		var notnull, pk int
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notnull, &dflt, &pk); err != nil {
			return nil, err
		}
		have[name] = true
	}
	return have, rows.Err()
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

func (s *store) addConnection(protocol, username, source, target, status string, ts time.Time) error {
	_, err := s.db.Exec(
		`INSERT INTO connections (ts, protocol, username, source, target, status) VALUES (?, ?, ?, ?, ?, ?)`,
		ts.Unix(), protocol, username, source, target, status,
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

type monthlyRow struct {
	Protocol string
	Username string
	Uplink   int64
	Downlink int64
}

// monthlyTotals returns per-user traffic summed over the hourly buckets since
// the given timestamp (used for the current-month view).
func (s *store) monthlyTotals(since int64) (map[string]monthlyRow, error) {
	rows, err := s.db.Query(
		`SELECT protocol, username, SUM(uplink), SUM(downlink) FROM hourly WHERE hour >= ? GROUP BY protocol, username`,
		since,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	m := make(map[string]monthlyRow)
	for rows.Next() {
		var r monthlyRow
		if err := rows.Scan(&r.Protocol, &r.Username, &r.Uplink, &r.Downlink); err != nil {
			return nil, err
		}
		m[r.Protocol+"|"+r.Username] = r
	}
	return m, rows.Err()
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

type hourlyRangeRow struct {
	Hour     int64
	Protocol string
	Username string
	Uplink   int64
	Downlink int64
}

func (s *store) hourlyRange(start, end int64, protocols, usernames []string) ([]hourlyRangeRow, error) {
	q := `SELECT hour, protocol, username, uplink, downlink FROM hourly WHERE hour >= ? AND hour < ?`
	args := []any{start, end}
	if len(protocols) > 0 {
		q += ` AND ` + inClause(`protocol`, len(protocols))
		for _, p := range protocols {
			args = append(args, p)
		}
	}
	if len(usernames) > 0 {
		q += ` AND ` + inClause(`username`, len(usernames))
		for _, u := range usernames {
			args = append(args, u)
		}
	}
	q += ` ORDER BY hour`
	rows, err := s.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []hourlyRangeRow
	for rows.Next() {
		var r hourlyRangeRow
		if err := rows.Scan(&r.Hour, &r.Protocol, &r.Username, &r.Uplink, &r.Downlink); err != nil {
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
	Status   string
}

func (s *store) connections(limit int, protocols, usernames, statuses []string) ([]connectionRow, error) {
	q := `SELECT ts, protocol, username, source, target, status FROM connections`
	var args []any
	var conds []string
	if len(protocols) > 0 {
		conds = append(conds, inClause(`protocol`, len(protocols)))
		for _, p := range protocols {
			args = append(args, p)
		}
	}
	if len(usernames) > 0 {
		conds = append(conds, inClause(`username`, len(usernames)))
		for _, u := range usernames {
			args = append(args, u)
		}
	}
	if len(statuses) > 0 {
		var ors []string
		for _, st := range statuses {
			if st == "empty" {
				ors = append(ors, `status = ''`)
			} else {
				ors = append(ors, `status = ?`)
				args = append(args, st)
			}
		}
		conds = append(conds, `(`+strings.Join(ors, ` OR `)+`)`)
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
		if err := rows.Scan(&r.TS, &r.Protocol, &r.Username, &r.Source, &r.Target, &r.Status); err != nil {
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
	}
	if maxRows > 0 {
		_, _ = s.db.Exec(`DELETE FROM connections WHERE id NOT IN (SELECT id FROM connections ORDER BY id DESC LIMIT ?)`, maxRows)
	}
}

func (s *store) pruneHourly(maxAge time.Duration) {
	if maxAge > 0 {
		cutoff := time.Now().Add(-maxAge).Unix()
		_, _ = s.db.Exec(`DELETE FROM hourly WHERE hour < ?`, cutoff)
	}
}

// inClause builds "col IN (?,?,...)" with the given number of placeholders.
func inClause(col string, n int) string {
	return col + ` IN (` + strings.TrimSuffix(strings.Repeat(`?,`, n), `,`) + `)`
}
