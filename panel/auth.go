package main

import (
	"crypto/hmac"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const sessionCookie = "panel_session"

const cryptAlphabet = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

// apr1Crypt computes the Apache $apr1$ MD5-crypt hash for the given password
// and salt. It mirrors the reference implementation used by openssl passwd -apr1
// and htpasswd -m so existing htpasswd files keep working without any change.
func apr1Crypt(password, salt string) string {
	const magic = "$apr1$"
	if len(salt) > 8 {
		salt = salt[:8]
	}

	h := md5.New()
	io.WriteString(h, password)
	io.WriteString(h, magic)
	io.WriteString(h, salt)

	alt := md5.Sum([]byte(password + salt + password))

	plen := len(password)
	for plen > 0 {
		n := plen
		if n > 16 {
			n = 16
		}
		h.Write(alt[:n])
		plen -= n
	}

	for i := len(password); i > 0; i >>= 1 {
		if i&1 != 0 {
			h.Write([]byte{0})
		} else {
			h.Write([]byte{password[0]})
		}
	}

	final := h.Sum(nil)

	for i := 0; i < 1000; i++ {
		c := md5.New()
		if i&1 != 0 {
			c.Write([]byte(password))
		} else {
			c.Write(final)
		}
		if i%3 != 0 {
			c.Write([]byte(salt))
		}
		if i%7 != 0 {
			c.Write([]byte(password))
		}
		if i&1 != 0 {
			c.Write(final)
		} else {
			c.Write([]byte(password))
		}
		final = c.Sum(nil)
	}

	enc := make([]byte, 0, 22)
	enc = append(enc, apr1Base64(final[0], final[6], final[12], 4)...)
	enc = append(enc, apr1Base64(final[1], final[7], final[13], 4)...)
	enc = append(enc, apr1Base64(final[2], final[8], final[14], 4)...)
	enc = append(enc, apr1Base64(final[3], final[9], final[15], 4)...)
	enc = append(enc, apr1Base64(final[4], final[10], final[5], 4)...)
	enc = append(enc, apr1Base64(0, 0, final[11], 2)...)

	return magic + salt + "$" + string(enc)
}

func apr1Base64(b2, b1, b0 byte, n int) []byte {
	w := (uint32(b2) << 16) | (uint32(b1) << 8) | uint32(b0)
	out := make([]byte, n)
	for i := 0; i < n; i++ {
		out[i] = cryptAlphabet[w&0x3f]
		w >>= 6
	}
	return out
}

// apr1Verify checks password against a $apr1$... hash using constant-time
// comparison of the full encoded string.
func apr1Verify(password, hash string) bool {
	const magic = "$apr1$"
	if !strings.HasPrefix(hash, magic) {
		return false
	}
	rest := hash[len(magic):]
	var salt, checksum string
	if i := strings.Index(rest, "$"); i >= 0 {
		salt = rest[:i]
		checksum = rest[i+1:]
	} else {
		salt = rest
	}
	if salt == "" {
		return false
	}
	got := apr1Crypt(password, salt)
	want := magic + salt + "$" + checksum
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

// readAuthUsers parses a htpasswd-style file (user:$apr1$...) and returns a
// name -> hash map. It is read on every login so password changes take effect
// without restarting the panel.
func readAuthUsers(path string) map[string]string {
	users := map[string]string{}
	data, err := os.ReadFile(path)
	if err != nil {
		return users
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		i := strings.Index(line, ":")
		if i <= 0 {
			continue
		}
		users[line[:i]] = line[i+1:]
	}
	return users
}

func loadOrCreateSecret(path string) ([]byte, error) {
	if data, err := os.ReadFile(path); err == nil && len(data) >= 32 {
		return data, nil
	}
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, secret, 0600); err != nil {
		return nil, err
	}
	return secret, nil
}

// authenticator implements password login with stateless HMAC-signed session
// cookies and per-IP brute-force throttling.
type authenticator struct {
	authFile string
	secret   []byte
	ttl      time.Duration
	limiter  *loginLimiter
}

func newAuthenticator(cfg *Config) (*authenticator, error) {
	secret, err := loadOrCreateSecret(cfg.SessionSecretFile)
	if err != nil {
		return nil, err
	}
	return &authenticator{
		authFile: cfg.AuthFile,
		secret:   secret,
		ttl:      time.Duration(cfg.SessionTTLSec) * time.Second,
		limiter:  newLoginLimiter(cfg.LoginMaxFails, cfg.LoginLockSec),
	}, nil
}

func (a *authenticator) issue() string {
	exp := make([]byte, 8)
	binary.BigEndian.PutUint64(exp, uint64(time.Now().Add(a.ttl).Unix()))
	expStr := base64.RawURLEncoding.EncodeToString(exp)
	mac := hmac.New(sha256.New, a.secret)
	mac.Write([]byte(expStr))
	return expStr + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (a *authenticator) verify(token string) bool {
	parts := strings.SplitN(token, ".", 2)
	if len(parts) != 2 {
		return false
	}
	exp, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil || len(exp) != 8 {
		return false
	}
	if time.Now().Unix() > int64(binary.BigEndian.Uint64(exp)) {
		return false
	}
	mac := hmac.New(sha256.New, a.secret)
	mac.Write([]byte(parts[0]))
	want := mac.Sum(nil)
	got, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return false
	}
	return hmac.Equal(want, got)
}

func (a *authenticator) authenticated(r *http.Request) bool {
	c, err := r.Cookie(sessionCookie)
	if err != nil || c == nil {
		return false
	}
	return a.verify(c.Value)
}

func isPublicPath(path string) bool {
	return path == "/login" || path == "/api/login" || path == "/api/logout"
}

func wantsJSON(r *http.Request) bool {
	return strings.Contains(r.Header.Get("Accept"), "application/json")
}

// middleware guards the whole mux: public paths pass through, everything else
// requires a valid session cookie.
func (a *authenticator) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isPublicPath(r.URL.Path) || a.authenticated(r) {
			next.ServeHTTP(w, r)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/api/") || wantsJSON(r) {
			writeJSONStatus(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		http.Redirect(w, r, "/login", http.StatusFound)
	})
}

func (a *authenticator) login(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSONStatus(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}
	ip := clientIP(r)
	if a.limiter.locked(ip) {
		writeJSONStatus(w, http.StatusTooManyRequests, map[string]string{"error": "尝试次数过多，请稍后再试"})
		return
	}
	username := r.FormValue("username")
	password := r.FormValue("password")
	users := readAuthUsers(a.authFile)
	hash, ok := users[username]
	if !ok || !apr1Verify(password, hash) {
		a.limiter.fail(ip)
		writeJSONStatus(w, http.StatusUnauthorized, map[string]string{"error": "用户名或密码错误"})
		return
	}
	a.limiter.success(ip)
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    a.issue(),
		Path:     "/",
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int(a.ttl.Seconds()),
	})
	writeJSON(w, map[string]bool{"ok": true})
}

func (a *authenticator) logout(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   -1,
	})
	writeJSON(w, map[string]bool{"ok": true})
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.Index(xff, ","); i > 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	host := r.RemoteAddr
	if i := strings.LastIndex(host, ":"); i > 0 {
		return host[:i]
	}
	return host
}

// loginLimiter is a simple in-memory per-IP failed-login throttle.
type loginLimiter struct {
	mu       sync.Mutex
	maxFails int
	lockSec  int64
	failures map[string]*failState
}

type failState struct {
	count     int
	lockUntil int64
}

func newLoginLimiter(maxFails, lockSec int) *loginLimiter {
	if maxFails <= 0 {
		maxFails = 5
	}
	if lockSec <= 0 {
		lockSec = 1800
	}
	return &loginLimiter{
		maxFails: maxFails,
		lockSec:  int64(lockSec),
		failures: map[string]*failState{},
	}
}

func (l *loginLimiter) locked(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	st := l.failures[ip]
	if st == nil || st.lockUntil == 0 {
		return false
	}
	if time.Now().Unix() >= st.lockUntil {
		st.count = 0
		st.lockUntil = 0
		return false
	}
	return true
}

func (l *loginLimiter) fail(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	st := l.failures[ip]
	if st == nil {
		st = &failState{}
		l.failures[ip] = st
	}
	if st.lockUntil > 0 {
		return
	}
	st.count++
	if st.count >= l.maxFails {
		st.lockUntil = time.Now().Unix() + l.lockSec
		st.count = 0
	}
}

func (l *loginLimiter) success(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.failures, ip)
}

// writeJSONStatus writes v as JSON with the given HTTP status code.
func writeJSONStatus(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
