package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestApr1Crypt(t *testing.T) {
	cases := []struct {
		password string
		salt     string
		want     string
	}{
		{"password", "hfT7jp2q", "$apr1$hfT7jp2q$two3QJlp/Qr/L8kifGFHF1"},
		{"hunter2", "salt1234", "$apr1$salt1234$3bsgUooExbmQbfo/Dn12v/"},
		{"test", "a1", "$apr1$a1$uUIRSbJ8pgNNsyQTYTf6P1"},
	}
	for _, c := range cases {
		got := apr1Crypt(c.password, c.salt)
		if got != c.want {
			t.Errorf("apr1Crypt(%q, %q) = %q, want %q", c.password, c.salt, got, c.want)
		}
	}
}

func TestApr1Verify(t *testing.T) {
	hash := apr1Crypt("secret-pass", "abc12345")
	if !apr1Verify("secret-pass", hash) {
		t.Errorf("apr1Verify should accept correct password for %q", hash)
	}
	if apr1Verify("wrong-pass", hash) {
		t.Errorf("apr1Verify should reject wrong password for %q", hash)
	}
	if apr1Verify("x", "not-a-hash") {
		t.Errorf("apr1Verify should reject malformed hash")
	}
	if apr1Verify("x", "") {
		t.Errorf("apr1Verify should reject empty hash")
	}
}

func TestSessionIssueVerify(t *testing.T) {
	a := &authenticator{secret: make([]byte, 32), ttl: time.Hour}
	copy(a.secret, []byte("0123456789abcdef0123456789abcdef"))

	tok := a.issue()
	if !a.verify(tok) {
		t.Errorf("verify should accept freshly issued token")
	}
	if a.verify("garbage") {
		t.Errorf("verify should reject garbage")
	}

	aExpired := &authenticator{secret: a.secret, ttl: -time.Hour}
	tokExp := aExpired.issue()
	if a.verify(tokExp) {
		t.Errorf("verify should reject expired token")
	}
}

func TestLoginFlow(t *testing.T) {
	dir := t.TempDir()
	authFile := filepath.Join(dir, "panel.htpasswd")
	secretFile := filepath.Join(dir, "panel.key")

	if err := writeTestFile(authFile, "admin:"+apr1Crypt("pw123", "testsalt")+"\n"); err != nil {
		t.Fatal(err)
	}

	cfg := &Config{
		AuthFile:          authFile,
		SessionSecretFile: secretFile,
		SessionTTLSec:     3600,
		LoginMaxFails:     5,
		LoginLockSec:      1800,
	}
	a, err := newAuthenticator(cfg)
	if err != nil {
		t.Fatal(err)
	}

	// wrong password -> 401
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/login", strings.NewReader("username=admin&password=bad"))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	a.login(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Errorf("wrong password should be 401, got %d", rr.Code)
	}

	// correct password -> 200 + cookie
	rr = httptest.NewRecorder()
	req = httptest.NewRequest(http.MethodPost, "/api/login", strings.NewReader("username=admin&password=pw123"))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	a.login(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("correct password should be 200, got %d", rr.Code)
	}
	cookies := rr.Result().Cookies()
	var sess *http.Cookie
	for _, c := range cookies {
		if c.Name == sessionCookie {
			sess = c
		}
	}
	if sess == nil {
		t.Fatalf("expected session cookie to be set")
	}

	// authenticated request passes middleware
	req2 := httptest.NewRequest(http.MethodGet, "/api/overview", nil)
	req2.AddCookie(&http.Cookie{Name: sessionCookie, Value: sess.Value})
	if !a.authenticated(req2) {
		t.Errorf("authenticated() should be true with valid session cookie")
	}
}

func TestLoginThrottle(t *testing.T) {
	dir := t.TempDir()
	authFile := filepath.Join(dir, "panel.htpasswd")
	secretFile := filepath.Join(dir, "panel.key")
	if err := writeTestFile(authFile, "admin:"+apr1Crypt("pw", "s")+"\n"); err != nil {
		t.Fatal(err)
	}
	cfg := &Config{
		AuthFile:          authFile,
		SessionSecretFile: secretFile,
		SessionTTLSec:     3600,
		LoginMaxFails:     3,
		LoginLockSec:      1800,
	}
	a, err := newAuthenticator(cfg)
	if err != nil {
		t.Fatal(err)
	}

	doLogin := func(ip string) int {
		rr := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/api/login", strings.NewReader("username=admin&password=bad"))
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		req.RemoteAddr = ip + ":1234"
		a.login(rr, req)
		return rr.Code
	}

	if code := doLogin("9.9.9.9"); code != http.StatusUnauthorized {
		t.Fatalf("first fail should be 401, got %d", code)
	}
	if code := doLogin("9.9.9.9"); code != http.StatusUnauthorized {
		t.Fatalf("second fail should be 401, got %d", code)
	}
	if code := doLogin("9.9.9.9"); code != http.StatusUnauthorized {
		t.Fatalf("third fail should be 401, got %d", code)
	}
	if code := doLogin("9.9.9.9"); code != http.StatusTooManyRequests {
		t.Fatalf("fourth attempt should be locked 429, got %d", code)
	}
}

func TestMiddlewareGuards(t *testing.T) {
	dir := t.TempDir()
	authFile := filepath.Join(dir, "panel.htpasswd")
	secretFile := filepath.Join(dir, "panel.key")
	if err := writeTestFile(authFile, "admin:"+apr1Crypt("pw", "s")+"\n"); err != nil {
		t.Fatal(err)
	}
	cfg := &Config{
		AuthFile:          authFile,
		SessionSecretFile: secretFile,
		SessionTTLSec:     3600,
		LoginMaxFails:     5,
		LoginLockSec:      1800,
	}
	a, err := newAuthenticator(cfg)
	if err != nil {
		t.Fatal(err)
	}
	inner := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	h := a.middleware(inner)

	// public paths pass through
	for _, p := range []string{"/login", "/api/login", "/api/logout"} {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, p, nil))
		if rr.Code != http.StatusNoContent {
			t.Errorf("%s should be public, got %d", p, rr.Code)
		}
	}

	// api without auth -> 401 JSON
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, httptest.NewRequest(http.MethodGet, "/api/overview", nil))
	if rr.Code != http.StatusUnauthorized {
		t.Errorf("api without auth should be 401, got %d", rr.Code)
	}

	// html without auth -> redirect to /login
	rr = httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Accept", "text/html")
	h.ServeHTTP(rr, req)
	if rr.Code != http.StatusFound {
		t.Errorf("html without auth should redirect 302, got %d", rr.Code)
	}
	if loc := rr.Header().Get("Location"); loc != "/login" {
		t.Errorf("redirect location = %q, want /login", loc)
	}
}

func writeTestFile(path, content string) error {
	return os.WriteFile(path, []byte(content), 0644)
}
