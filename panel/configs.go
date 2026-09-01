package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

// userConfig is a single user's client connection configuration, derived from
// the live on-disk server config files at request time so the panel always
// reflects the real state.
type userConfig struct {
	Protocol    string `json:"protocol"`
	Username    string `json:"username"`
	Address     string `json:"address"`
	Port        string `json:"port"`
	Secret      string `json:"secret"`
	SecretLabel string `json:"secret_label"`
	Path        string `json:"path,omitempty"`
	SNI         string `json:"sni,omitempty"`
	Link        string `json:"link"`
	Surge       string `json:"surge,omitempty"`
}

type userSecret struct {
	name   string
	secret string
}

// loadAllConfigs reads the actual config files on disk and returns one config
// per user across all installed protocols, sorted by protocol then username.
func loadAllConfigs(cfg *Config) []userConfig {
	anytlsDomain := readDomain(cfg.SingBox.DomainFile)
	var out []userConfig
	out = append(out, loadVmessConfigs(cfg.V2Ray, anytlsDomain)...)
	out = append(out, loadAnyTLSConfigs(cfg.SingBox, anytlsDomain)...)
	sort.Slice(out, func(i, j int) bool {
		if out[i].Protocol != out[j].Protocol {
			return out[i].Protocol < out[j].Protocol
		}
		return out[i].Username < out[j].Username
	})
	return out
}

func readUserSecrets(path string) []userSecret {
	if path == "" {
		return nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var users []userSecret
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
		secret := ""
		if len(fields) >= 2 {
			secret = fields[1]
		}
		users = append(users, userSecret{name: fields[0], secret: secret})
	}
	return users
}

func readDomain(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

type qrConf struct {
	Add  string `json:"add"`
	Port string `json:"port"`
	Path string `json:"path"`
}

func loadQr(path string) qrConf {
	var q qrConf
	if path == "" {
		return q
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return q
	}
	_ = json.Unmarshal(data, &q)
	return q
}

func v2rayWSPath(path string) string {
	if path == "" {
		return ""
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var c struct {
		Inbounds []struct {
			StreamSettings struct {
				WSSettings struct {
					Path string `json:"path"`
				} `json:"wsSettings"`
			} `json:"streamSettings"`
		} `json:"inbounds"`
	}
	if err := json.Unmarshal(data, &c); err != nil {
		return ""
	}
	for _, in := range c.Inbounds {
		if p := in.StreamSettings.WSSettings.Path; p != "" {
			return p
		}
	}
	return ""
}

func singboxPort(path string) string {
	if path == "" {
		return ""
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var c struct {
		Inbounds []struct {
			ListenPort int `json:"listen_port"`
		} `json:"inbounds"`
	}
	if err := json.Unmarshal(data, &c); err != nil {
		return ""
	}
	for _, in := range c.Inbounds {
		if in.ListenPort > 0 {
			return strconv.Itoa(in.ListenPort)
		}
	}
	return ""
}

func vmessLink(ps, id, add, port, path string) string {
	if add == "" || id == "" {
		return ""
	}
	j := fmt.Sprintf(`{"v":"2","ps":%q,"add":%q,"port":%q,"id":%q,"aid":"0","net":"ws","type":"none","host":%q,"path":%q,"tls":"tls"}`,
		ps, add, port, id, add, path)
	return "vmess://" + base64.StdEncoding.EncodeToString([]byte(j))
}

func loadVmessConfigs(p ProtocolConfig, fallbackDomain string) []userConfig {
	users := readUserSecrets(p.UsersFile)
	if len(users) == 0 {
		return nil
	}
	qr := loadQr(p.QrFile)
	domain := qr.Add
	if domain == "" {
		domain = fallbackDomain
	}
	path := qr.Path
	if path == "" {
		path = v2rayWSPath(p.ConfigFile)
	}
	out := make([]userConfig, 0, len(users))
	for _, u := range users {
		out = append(out, userConfig{
			Protocol:    "vmess",
			Username:    u.name,
			Address:     domain,
			Port:        qr.Port,
			Secret:      u.secret,
			SecretLabel: "UUID",
			Path:        path,
			Link:        vmessLink(u.name, u.secret, domain, qr.Port, path),
		})
	}
	return out
}

func anytlsLink(name, password, domain, port string) string {
	if password == "" || domain == "" {
		return ""
	}
	return fmt.Sprintf("anytls://%s@%s:%s?sni=%s#AnyTLS-%s", password, domain, port, domain, name)
}

func anytlsSurge(name, password, domain, port string) string {
	if password == "" || domain == "" {
		return ""
	}
	return fmt.Sprintf("AnyTLS-%s = anytls, %s, %s, password=%s, sni=%s, reuse=true", name, domain, port, password, domain)
}

func loadAnyTLSConfigs(p ProtocolConfig, fallbackDomain string) []userConfig {
	users := readUserSecrets(p.UsersFile)
	if len(users) == 0 {
		return nil
	}
	port := singboxPort(p.ConfigFile)
	if port == "" {
		port = "8443"
	}
	domain := readDomain(p.DomainFile)
	if domain == "" {
		domain = fallbackDomain
	}
	out := make([]userConfig, 0, len(users))
	for _, u := range users {
		out = append(out, userConfig{
			Protocol:    "anytls",
			Username:    u.name,
			Address:     domain,
			Port:        port,
			Secret:      u.secret,
			SecretLabel: "密码",
			SNI:         domain,
			Link:        anytlsLink(u.name, u.secret, domain, port),
			Surge:       anytlsSurge(u.name, u.secret, domain, port),
		})
	}
	return out
}
