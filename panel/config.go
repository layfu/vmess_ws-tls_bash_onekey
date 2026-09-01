package main

import (
	"encoding/json"
	"os"
)

type ProtocolConfig struct {
	Enabled     bool   `json:"enabled"`
	APIAddr     string `json:"api_addr"`
	AccessLog   string `json:"access_log"`
	WSAccessLog string `json:"ws_access_log"`
	LogFile     string `json:"log_file"`
	UsersFile   string `json:"users_file"`
}

type Config struct {
	Listen          string         `json:"listen"`
	DBPath          string         `json:"db_path"`
	PollIntervalSec int            `json:"poll_interval_sec"`
	OnlineWindowSec int            `json:"online_window_sec"`
	RetentionDays   int            `json:"retention_days"`
	GeoDB           string         `json:"geo_db"`
	V2Ray           ProtocolConfig `json:"v2ray"`
	SingBox         ProtocolConfig `json:"singbox"`
}

func defaultConfig() *Config {
	return &Config{
		Listen:          "127.0.0.1:2052",
		DBPath:          "/var/lib/panel/panel.db",
		PollIntervalSec: 15,
		OnlineWindowSec: 90,
		RetentionDays:   1095,
		V2Ray: ProtocolConfig{
			Enabled:     false,
			APIAddr:     "127.0.0.1:50085",
			AccessLog:   "/var/log/v2ray/access.log",
			WSAccessLog: "/var/log/nginx/ws-access.log",
			UsersFile:   "/etc/v2ray/users",
		},
		SingBox: ProtocolConfig{
			Enabled:   false,
			APIAddr:   "127.0.0.1:50086",
			LogFile:   "/var/log/sing-box/sing-box.log",
			UsersFile: "/etc/sing-box/users",
		},
	}
}

func loadConfig(path string) (*Config, error) {
	cfg := defaultConfig()
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return nil, err
	}
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	if cfg.PollIntervalSec <= 0 {
		cfg.PollIntervalSec = 15
	}
	if cfg.OnlineWindowSec <= 0 {
		cfg.OnlineWindowSec = 90
	}
	if cfg.RetentionDays <= 0 {
		cfg.RetentionDays = 1095
	}
	if cfg.Listen == "" {
		cfg.Listen = "127.0.0.1:2052"
	}
	if cfg.DBPath == "" {
		cfg.DBPath = "/var/lib/panel/panel.db"
	}
	return cfg, nil
}
