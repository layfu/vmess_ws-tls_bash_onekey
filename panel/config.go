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
	ConfigFile  string `json:"config_file"`
	QrFile      string `json:"qr_file"`
	DomainFile  string `json:"domain_file"`
}

type Config struct {
	Listen            string         `json:"listen"`
	DBPath            string         `json:"db_path"`
	PollIntervalSec   int            `json:"poll_interval_sec"`
	OnlineWindowSec   int            `json:"online_window_sec"`
	RetentionDays     int            `json:"retention_days"`
	GeoDB             string         `json:"geo_db"`
	AuthFile          string         `json:"auth_file"`
	SessionSecretFile string         `json:"session_secret_file"`
	SessionTTLSec     int            `json:"session_ttl_sec"`
	LoginMaxFails     int            `json:"login_max_fails"`
	LoginLockSec      int            `json:"login_lock_sec"`
	V2Ray             ProtocolConfig `json:"v2ray"`
	SingBox           ProtocolConfig `json:"singbox"`
}

func defaultConfig() *Config {
	return &Config{
		Listen:            "127.0.0.1:2052",
		DBPath:            "/var/lib/panel/panel.db",
		PollIntervalSec:   15,
		OnlineWindowSec:   90,
		RetentionDays:     1095,
		AuthFile:          "/etc/panel/panel.htpasswd",
		SessionSecretFile: "/etc/panel/panel.key",
		SessionTTLSec:     604800,
		LoginMaxFails:     5,
		LoginLockSec:      1800,
		V2Ray: ProtocolConfig{
			Enabled:     false,
			APIAddr:     "127.0.0.1:50085",
			AccessLog:   "/var/log/v2ray/access.log",
			WSAccessLog: "/var/log/nginx/ws-access.log",
			UsersFile:   "/etc/v2ray/users",
			ConfigFile:  "/etc/v2ray/config.json",
			QrFile:      "/usr/local/vmess_qr.json",
		},
		SingBox: ProtocolConfig{
			Enabled:    false,
			APIAddr:    "127.0.0.1:50086",
			LogFile:    "/var/log/sing-box/sing-box.log",
			UsersFile:  "/etc/sing-box/users",
			ConfigFile: "/etc/sing-box/config.json",
			DomainFile: "/etc/sing-box/domain",
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
	if cfg.AuthFile == "" {
		cfg.AuthFile = "/etc/panel/panel.htpasswd"
	}
	if cfg.SessionSecretFile == "" {
		cfg.SessionSecretFile = "/etc/panel/panel.key"
	}
	if cfg.SessionTTLSec <= 0 {
		cfg.SessionTTLSec = 604800
	}
	if cfg.LoginMaxFails <= 0 {
		cfg.LoginMaxFails = 5
	}
	if cfg.LoginLockSec <= 0 {
		cfg.LoginLockSec = 1800
	}
	return cfg, nil
}
