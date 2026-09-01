package main

import (
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestVMessLink(t *testing.T) {
	link := vmessLink("alice", "uuid-1", "example.com", "443", "/abc/")
	if link == "" {
		t.Fatal("expected non-empty link")
	}
	const prefix = "vmess://"
	if len(link) < len(prefix) || link[:len(prefix)] != prefix {
		t.Fatalf("expected vmess:// prefix, got %q", link)
	}
	raw, err := base64.StdEncoding.DecodeString(link[len(prefix):])
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("unmarshal vmess json: %v", err)
	}
	if m["add"] != "example.com" || m["port"] != "443" || m["id"] != "uuid-1" ||
		m["path"] != "/abc/" || m["tls"] != "tls" || m["net"] != "ws" {
		t.Errorf("vmess fields = %+v", m)
	}
	if link == "" {
		t.Error("empty link")
	}
	if l := vmessLink("x", "", "example.com", "443", "/a/"); l != "" {
		t.Errorf("missing id should yield empty link, got %q", l)
	}
}

func TestAnyTLSLinkAndSurge(t *testing.T) {
	link := anytlsLink("bob", "secret", "example.com", "8443")
	want := "anytls://secret@example.com:8443?sni=example.com#AnyTLS-bob"
	if link != want {
		t.Errorf("link = %q, want %q", link, want)
	}
	surge := anytlsSurge("bob", "secret", "example.com", "8443")
	wantSurge := "AnyTLS-bob = anytls, example.com, 8443, password=secret, sni=example.com, reuse=true"
	if surge != wantSurge {
		t.Errorf("surge = %q, want %q", surge, wantSurge)
	}
}

func writeFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadVmessConfigs(t *testing.T) {
	dir := t.TempDir()
	usersFile := writeFile(t, dir, "users", "alice uuid-alice\nbob uuid-bob\n")
	qrFile := writeFile(t, dir, "qr.json", `{"add":"example.com","port":"443","path":"/abc/"}`)
	confFile := writeFile(t, dir, "config.json", `{"inbounds":[{"streamSettings":{"wsSettings":{"path":"/abc/"}}}]}`)

	p := ProtocolConfig{UsersFile: usersFile, QrFile: qrFile, ConfigFile: confFile}
	cfgs := loadVmessConfigs(p, "")
	if len(cfgs) != 2 {
		t.Fatalf("expected 2 configs, got %d", len(cfgs))
	}
	if cfgs[0].Username != "alice" || cfgs[0].Address != "example.com" ||
		cfgs[0].Port != "443" || cfgs[0].Path != "/abc/" || cfgs[0].Secret != "uuid-alice" {
		t.Errorf("cfgs[0] = %+v", cfgs[0])
	}
	if cfgs[0].SecretLabel != "UUID" {
		t.Errorf("secret label = %q", cfgs[0].SecretLabel)
	}
}

func TestLoadVmessConfigsPathFallback(t *testing.T) {
	dir := t.TempDir()
	usersFile := writeFile(t, dir, "users", "alice uuid-alice\n")
	confFile := writeFile(t, dir, "config.json", `{"inbounds":[{"streamSettings":{"wsSettings":{"path":"/fallback/"}}}]}`)

	p := ProtocolConfig{UsersFile: usersFile, QrFile: filepath.Join(dir, "missing.json"), ConfigFile: confFile}
	cfgs := loadVmessConfigs(p, "fb.example.com")
	if len(cfgs) != 1 {
		t.Fatalf("expected 1 config, got %d", len(cfgs))
	}
	if cfgs[0].Path != "/fallback/" {
		t.Errorf("path = %q, want /fallback/", cfgs[0].Path)
	}
	if cfgs[0].Address != "fb.example.com" {
		t.Errorf("address = %q, want fb.example.com", cfgs[0].Address)
	}
}

func TestLoadAnyTLSConfigs(t *testing.T) {
	dir := t.TempDir()
	usersFile := writeFile(t, dir, "users", "bob secret-bob\n")
	confFile := writeFile(t, dir, "config.json", `{"inbounds":[{"type":"anytls","listen_port":8443}]}`)
	domainFile := writeFile(t, dir, "domain", "example.com\n")

	p := ProtocolConfig{UsersFile: usersFile, ConfigFile: confFile, DomainFile: domainFile}
	cfgs := loadAnyTLSConfigs(p, "")
	if len(cfgs) != 1 {
		t.Fatalf("expected 1 config, got %d", len(cfgs))
	}
	c := cfgs[0]
	if c.Username != "bob" || c.Address != "example.com" || c.Port != "8443" ||
		c.Secret != "secret-bob" || c.SecretLabel != "密码" || c.SNI != "example.com" {
		t.Errorf("config = %+v", c)
	}
	if c.Link == "" || c.Surge == "" {
		t.Errorf("expected link and surge, got %+v", c)
	}
}

func TestLoadAllConfigsSorted(t *testing.T) {
	dir := t.TempDir()
	vUsers := writeFile(t, dir, "vusers", "b uuid-b\n")
	vQr := writeFile(t, dir, "vqr.json", `{"add":"example.com","port":"443","path":"/a/"}`)
	vConf := writeFile(t, dir, "vconf.json", `{"inbounds":[{"streamSettings":{"wsSettings":{"path":"/a/"}}}]}`)
	aUsers := writeFile(t, dir, "ausers", "a pass-a\n")
	aConf := writeFile(t, dir, "aconf.json", `{"inbounds":[{"listen_port":8443}]}`)
	aDomain := writeFile(t, dir, "adomain", "example.com\n")

	cfg := &Config{
		V2Ray:   ProtocolConfig{UsersFile: vUsers, QrFile: vQr, ConfigFile: vConf},
		SingBox: ProtocolConfig{UsersFile: aUsers, ConfigFile: aConf, DomainFile: aDomain},
	}
	all := loadAllConfigs(cfg)
	if len(all) != 2 {
		t.Fatalf("expected 2 configs, got %d", len(all))
	}
	if all[0].Protocol != "anytls" || all[1].Protocol != "vmess" {
		t.Errorf("expected anytls then vmess, got %q, %q", all[0].Protocol, all[1].Protocol)
	}
}
