package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"os"
	"path/filepath"
	"testing"
	"time"
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
	if cfgs[0].Transport != "websocket" || cfgs[0].TLS != "是" || cfgs[0].AEAD != "是" {
		t.Errorf("vmess transport/tls/aead = %q/%q/%q", cfgs[0].Transport, cfgs[0].TLS, cfgs[0].AEAD)
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
	if c.SkipCertCheck != "否" {
		t.Errorf("skip_cert_check = %q, want 否 (no cert configured)", c.SkipCertCheck)
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

func newKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func selfSignedPEM(t *testing.T) []byte {
	t.Helper()
	key := newKey(t)
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "example.com"},
		Issuer:       pkix.Name{CommonName: "example.com"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		IsCA:         true,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
}

func caSignedPEM(t *testing.T) []byte {
	t.Helper()
	caKey := newKey(t)
	caTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "Test CA"},
		Issuer:       pkix.Name{CommonName: "Test CA"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		IsCA:         true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTmpl, caTmpl, &caKey.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	ca, err := x509.ParseCertificate(caDER)
	if err != nil {
		t.Fatal(err)
	}
	leafKey := newKey(t)
	leafTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(2),
		Subject:      pkix.Name{CommonName: "example.com"},
		Issuer:       ca.Subject,
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTmpl, ca, &leafKey.PublicKey, caKey)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leafDER})
}

func TestAnyTLSSkipCertCheck(t *testing.T) {
	dir := t.TempDir()

	self := writeFile(t, dir, "self.crt", string(selfSignedPEM(t)))
	selfConf := writeFile(t, dir, "self-conf.json", `{"inbounds":[{"tls":{"certificate_path":"`+self+`"}}]}`)
	if got := anytlsSkipCertCheck(selfConf); got != "是" {
		t.Errorf("self-signed cert: skip_cert_check = %q, want 是", got)
	}

	ca := writeFile(t, dir, "ca.crt", string(caSignedPEM(t)))
	caConf := writeFile(t, dir, "ca-conf.json", `{"inbounds":[{"tls":{"certificate_path":"`+ca+`"}}]}`)
	if got := anytlsSkipCertCheck(caConf); got != "否" {
		t.Errorf("CA-signed cert: skip_cert_check = %q, want 否", got)
	}

	missingConf := writeFile(t, dir, "missing-conf.json", `{"inbounds":[{"tls":{"certificate_path":"/nonexistent.crt"}}]}`)
	if got := anytlsSkipCertCheck(missingConf); got != "否" {
		t.Errorf("missing cert: skip_cert_check = %q, want 否", got)
	}
}
