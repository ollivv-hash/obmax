package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

// ------------------------------------------------------------------ helpers

type testEnv struct {
	t        *testing.T
	srv      *Server
	public   *httptest.Server
	admin    *httptest.Server
	jellyfin *httptest.Server
	now      time.Time
	root     *x509.Certificate
}

func writePEM(t *testing.T, path, typ string, der []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: typ, Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
}

// makeCA builds a root and an intermediate shaped like the ones the
// ceremony script produces, and writes the intermediate where the service
// looks for it.
func makeCA(t *testing.T, dataDir string) *x509.Certificate {
	t.Helper()
	rootKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	rootTmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "Jellyfin Client CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(10 * 365 * 24 * time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
	}
	rootDER, _ := x509.CreateCertificate(rand.Reader, rootTmpl, rootTmpl, &rootKey.PublicKey, rootKey)
	root, _ := x509.ParseCertificate(rootDER)

	intKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	intTmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(2),
		Subject:               pkix.Name{CommonName: "OB Max Enrollment CA"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(3 * 365 * 24 * time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		MaxPathLen:            0,
		MaxPathLenZero:        true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	}
	intDER, _ := x509.CreateCertificate(rand.Reader, intTmpl, root, &intKey.PublicKey, rootKey)
	keyDER, _ := x509.MarshalECPrivateKey(intKey)
	cfg := Config{DataDir: dataDir}
	writePEM(t, cfg.caCertPath(), "CERTIFICATE", intDER)
	writePEM(t, cfg.caKeyPath(), "EC PRIVATE KEY", keyDER)
	return root
}

func newEnv(t *testing.T) *testEnv {
	t.Helper()
	dir := t.TempDir()
	root := makeCA(t, dir)
	env := &testEnv{t: t, now: time.Now().UTC().Truncate(time.Second), root: root}

	env.jellyfin = httptest.NewServer(http.HandlerFunc(fakeJellyfin))
	t.Cleanup(env.jellyfin.Close)

	cfg := Config{
		DataDir:         dir,
		AdminBasePath:   "/obmax-admin",
		JellyfinURL:     env.jellyfin.URL,
		PublicServerURL: "https://jellyfin.example.com",
		CertValidity:    180 * 24 * time.Hour,
		InviteValidity:  48 * time.Hour,
	}
	ca, err := LoadCA(cfg.caCertPath(), cfg.caKeyPath())
	if err != nil {
		t.Fatal(err)
	}
	store, err := OpenStore(cfg.statePath())
	if err != nil {
		t.Fatal(err)
	}
	env.srv = NewServer(cfg, ca, store)
	env.srv.now = func() time.Time { return env.now }
	env.public = httptest.NewServer(env.srv.PublicHandler())
	env.admin = httptest.NewServer(env.srv.AdminHandler())
	t.Cleanup(env.public.Close)
	t.Cleanup(env.admin.Close)
	return env
}

// invite stores an invitation the way the admin page does and returns its
// code.
func (e *testEnv) invite(user string) string {
	e.t.Helper()
	code, err := NewCode()
	if err != nil {
		e.t.Fatal(err)
	}
	err = e.srv.store.Update(func(st *state) error {
		st.Invitations = append(st.Invitations, &Invitation{
			ID: randomID(), CodeHash: HashCode(NormalizeCode(code)),
			JellyfinUserID: "id-" + user, JellyfinUserName: user,
			CreatedAt: e.now, ExpiresAt: e.now.Add(48 * time.Hour),
		})
		return nil
	})
	if err != nil {
		e.t.Fatal(err)
	}
	return code
}

func newKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func csrPEM(t *testing.T, key *ecdsa.PrivateKey) string {
	t.Helper()
	der, err := x509.CreateCertificateRequest(rand.Reader, &x509.CertificateRequest{
		Subject: pkix.Name{CommonName: "ignored by the service"},
	}, key)
	if err != nil {
		t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE REQUEST", Bytes: der}))
}

func (e *testEnv) post(path string, body any) (int, map[string]any) {
	e.t.Helper()
	data, _ := json.Marshal(body)
	resp, err := http.Post(e.public.URL+path, "application/json", bytes.NewReader(data))
	if err != nil {
		e.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func (e *testEnv) enroll(code string, key *ecdsa.PrivateKey) (int, map[string]any) {
	return e.post("/v1/enroll", map[string]any{
		"code":   code,
		"csr":    csrPEM(e.t, key),
		"device": map[string]string{"name": "SHIELD Android TV", "platform": "androidTv", "appVersion": "2.0.0"},
	})
}

func leafOf(t *testing.T, chain string) *x509.Certificate {
	t.Helper()
	block, _ := pem.Decode([]byte(chain))
	c, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

// ------------------------------------------------------------------ codes

func TestCodes(t *testing.T) {
	code, err := NewCode()
	if err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`).MatchString(code) {
		t.Fatalf("bad code format %q", code)
	}
	if NormalizeCode(strings.ToLower(strings.ReplaceAll(code, "-", " "))) != strings.ReplaceAll(code, "-", "") {
		t.Fatal("lower case and spaces should normalize")
	}
	if NormalizeCode("0000-1111-2222") != NormalizeCode("oooo-iiii-2222") {
		t.Fatal("O and I should read as 0 and 1")
	}
	for _, bad := range []string{"", "ABCD", "ABCD-EFGH-JKMNP", "ABCD-EFGH-JKU1", "ABCD-EFGH-JK*1"} {
		if NormalizeCode(bad) != "" {
			t.Fatalf("%q should not normalize", bad)
		}
	}
}

// ------------------------------------------------------------------ enroll

func TestEnrollIssuesADeviceCertificate(t *testing.T) {
	e := newEnv(t)
	code := e.invite("paul")
	key := newKey(t)

	status, body := e.enroll(code, key)
	if status != http.StatusOK {
		t.Fatalf("enroll: %d %v", status, body)
	}
	if body["jellyfinUsername"] != "paul" || body["serverUrl"] != "https://jellyfin.example.com" || body["subject"] != "paul/SHIELD Android TV" {
		t.Fatalf("unexpected body %v", body)
	}
	chain := body["certificateChain"].(string)
	if strings.Count(chain, "BEGIN CERTIFICATE") != 2 {
		t.Fatal("chain should hold the device certificate and the intermediate")
	}
	leaf := leafOf(t, chain)
	if leaf.Subject.CommonName != "paul/SHIELD Android TV" || leaf.Subject.Organization[0] != "OB Max" {
		t.Fatalf("subject %v", leaf.Subject)
	}
	if len(leaf.ExtKeyUsage) != 1 || leaf.ExtKeyUsage[0] != x509.ExtKeyUsageClientAuth || leaf.IsCA {
		t.Fatal("device certificate must be a clientAuth leaf")
	}
	if got := leaf.NotAfter.Sub(e.now); got != 180*24*time.Hour {
		t.Fatalf("validity %v", got)
	}
	if leaf.NotBefore.After(e.now.Add(-4 * time.Minute)) {
		t.Fatal("notBefore should be backdated for clock drift")
	}
	if !leaf.PublicKey.(*ecdsa.PublicKey).Equal(&key.PublicKey) {
		t.Fatal("certificate must carry the device's own key")
	}

	// What Caddy does with the trust pool holding only the intermediate (the
	// target), and with the root during the transition.
	inter := e.srv.ca.Cert
	for name, anchor := range map[string]*x509.Certificate{"intermediate": inter, "root": e.root} {
		roots := x509.NewCertPool()
		roots.AddCert(anchor)
		inters := x509.NewCertPool()
		inters.AddCert(inter)
		if _, err := leaf.Verify(x509.VerifyOptions{Roots: roots, Intermediates: inters, CurrentTime: e.now, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}}); err != nil {
			t.Fatalf("verify with %s as anchor: %v", name, err)
		}
	}

	// A code works once.
	if status, _ := e.enroll(code, newKey(t)); status != http.StatusForbidden {
		t.Fatalf("second use: %d", status)
	}
}

func TestEnrollRefusesBadCodesAlike(t *testing.T) {
	e := newEnv(t)
	expired := e.invite("paul")
	e.now = e.now.Add(49 * time.Hour)
	for _, code := range []string{expired, "ZZZZ-ZZZZ-ZZZZ", "pas un code"} {
		status, body := e.enroll(code, newKey(t))
		if status != http.StatusForbidden || body["error"] != "invalid_code" || body["message"] != msgInvalidCode {
			t.Fatalf("%q: %d %v", code, status, body)
		}
	}
}

func TestEnrollAcceptsHowPeopleTypeCodes(t *testing.T) {
	e := newEnv(t)
	code := e.invite("paul")
	typed := strings.ToLower(strings.ReplaceAll(code, "-", ""))
	if status, body := e.enroll(typed, newKey(t)); status != http.StatusOK {
		t.Fatalf("%d %v", status, body)
	}
}

func TestEnrollRateLimit(t *testing.T) {
	e := newEnv(t)
	for i := 0; i < 5; i++ {
		if status, _ := e.enroll("ZZZZ-ZZZZ-ZZZZ", newKey(t)); status != http.StatusForbidden {
			t.Fatalf("attempt %d: %d", i+1, status)
		}
	}
	good := e.invite("paul")
	if status, body := e.enroll(good, newKey(t)); status != http.StatusTooManyRequests || body["message"] != msgRateLimited {
		t.Fatalf("6th attempt: %d %v", status, body)
	}
	e.now = e.now.Add(61 * time.Minute)
	if status, _ := e.enroll(good, newKey(t)); status != http.StatusOK {
		t.Fatalf("after an hour: %d", status)
	}
}

func TestEnrollRejectsWeakCSR(t *testing.T) {
	e := newEnv(t)
	code := e.invite("paul")
	k384, _ := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	if status, _ := e.enroll(code, k384); status != http.StatusBadRequest {
		t.Fatalf("P-384: %d", status)
	}
	status, _ := e.post("/v1/enroll", map[string]any{"code": code, "csr": "-----BEGIN CERTIFICATE REQUEST-----\nAAAA\n-----END CERTIFICATE REQUEST-----"})
	if status != http.StatusBadRequest {
		t.Fatalf("garbage CSR: %d", status)
	}
	// The code survives a malformed request.
	if status, _ := e.enroll(code, newKey(t)); status != http.StatusOK {
		t.Fatalf("code after bad CSR: %d", status)
	}
}

// ------------------------------------------------------------------ renew

func TestRenew(t *testing.T) {
	e := newEnv(t)
	key := newKey(t)
	_, body := e.enroll(e.invite("paul"), key)
	deviceID := body["deviceId"].(string)
	chain1 := body["certificateChain"].(string)

	renew := func(chain string, k *ecdsa.PrivateKey) (int, map[string]any) {
		return e.post("/v1/renew", map[string]any{
			"deviceId": deviceID, "certificateChain": chain, "csr": csrPEM(t, k), "appVersion": "2.0.1",
		})
	}

	e.now = e.now.Add(125 * 24 * time.Hour)
	status, body := renew(chain1, key)
	if status != http.StatusOK {
		t.Fatalf("renew: %d %v", status, body)
	}
	chain2 := body["certificateChain"].(string)
	leaf2 := leafOf(t, chain2)
	if got := leaf2.NotAfter.Sub(e.now); got != 180*24*time.Hour {
		t.Fatalf("renewed validity %v", got)
	}
	if leafOf(t, chain1).SerialNumber.Cmp(leaf2.SerialNumber) == 0 {
		t.Fatal("renewal must issue a new serial")
	}

	// The response may never have reached the device: the previous
	// certificate still renews, and what it gets becomes current.
	status, body = renew(chain1, key)
	if status != http.StatusOK {
		t.Fatalf("renew with previous certificate: %d", status)
	}
	chain3 := body["certificateChain"].(string)

	// Another key cannot renew this device.
	if status, body := renew(chain3, newKey(t)); status != http.StatusForbidden || body["error"] != "invalid_certificate" {
		t.Fatalf("foreign key: %d %v", status, body)
	}

	// Revoked: refused, then the certificate runs out.
	_ = e.srv.store.Update(func(st *state) error {
		now := e.now
		st.deviceByID(deviceID).RevokedAt = &now
		return nil
	})
	status, body = renew(chain3, key)
	if status != http.StatusForbidden || body["error"] != "revoked" {
		t.Fatalf("revoked: %d %v", status, body)
	}
}

func TestRenewRefusesExpiredAndUnknownCertificates(t *testing.T) {
	e := newEnv(t)
	key := newKey(t)
	_, body := e.enroll(e.invite("paul"), key)
	deviceID := body["deviceId"].(string)
	chain := body["certificateChain"].(string)

	status, out := e.post("/v1/renew", map[string]any{"deviceId": "nope", "certificateChain": chain, "csr": csrPEM(t, key)})
	if status != http.StatusForbidden || out["error"] != "invalid_certificate" {
		t.Fatalf("unknown device: %d %v", status, out)
	}

	e.now = e.now.Add(181 * 24 * time.Hour)
	status, out = e.post("/v1/renew", map[string]any{"deviceId": deviceID, "certificateChain": chain, "csr": csrPEM(t, key)})
	if status != http.StatusForbidden || out["error"] != "invalid_certificate" {
		t.Fatalf("expired: %d %v", status, out)
	}
}

func TestStatePersists(t *testing.T) {
	e := newEnv(t)
	_, body := e.enroll(e.invite("paul"), newKey(t))
	store, err := OpenStore(e.srv.cfg.statePath())
	if err != nil {
		t.Fatal(err)
	}
	var found bool
	store.View(func(st *state) { found = st.deviceByID(body["deviceId"].(string)) != nil })
	if !found {
		t.Fatal("device not saved")
	}
	info, _ := os.Stat(e.srv.cfg.statePath())
	if info.Mode().Perm()&0o077 != 0 && os.PathSeparator == '/' {
		t.Fatalf("state file mode %v", info.Mode())
	}
}

func TestForwardedIPOnlyFromTrustedProxy(t *testing.T) {
	cfg, err := LoadConfig()
	if err != nil {
		t.Fatal(err)
	}
	s := &Server{cfg: cfg}
	r := httptest.NewRequest("POST", "/v1/enroll", nil)
	r.Header.Set("X-Forwarded-For", "203.0.113.9")
	r.RemoteAddr = "192.168.0.101:51000"
	if got := s.clientIP(r); got != "203.0.113.9" {
		t.Fatalf("from Caddy: %s", got)
	}
	r.RemoteAddr = "198.51.100.7:51000"
	if got := s.clientIP(r); got != "198.51.100.7" {
		t.Fatalf("from elsewhere: %s", got)
	}
}

// ------------------------------------------------------------------ admin

// fakeJellyfin knows "admin" (admin, password "secret") and "paul".
func fakeJellyfin(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.Method == "POST" && r.URL.Path == "/Users/AuthenticateByName":
		var in map[string]string
		_ = json.NewDecoder(r.Body).Decode(&in)
		admin := in["Username"] == "admin" && in["Pw"] == "secret"
		user := in["Username"] == "paul" && in["Pw"] == "pw"
		if !admin && !user {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"AccessToken": "tok-" + in["Username"],
			"User": map[string]any{"Id": "id-" + in["Username"], "Name": in["Username"],
				"Policy": map[string]any{"IsAdministrator": admin}},
		})
	case r.Method == "GET" && r.URL.Path == "/Users":
		if !strings.Contains(r.Header.Get("Authorization"), `Token="tok-admin"`) {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_ = json.NewEncoder(w).Encode([]map[string]any{
			{"Id": "id-paul", "Name": "paul", "Policy": map[string]any{}},
			{"Id": "id-admin", "Name": "admin", "Policy": map[string]any{"IsAdministrator": true}},
		})
	case r.URL.Path == "/Sessions/Logout":
		w.WriteHeader(http.StatusNoContent)
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func (e *testEnv) adminClient() *http.Client {
	return &http.Client{
		Jar: newJar(),
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
}

func get(t *testing.T, c *http.Client, u string) (int, string) {
	t.Helper()
	resp, err := c.Get(u)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

func postForm(t *testing.T, c *http.Client, u string, v url.Values) (int, string, string) {
	t.Helper()
	resp, err := c.PostForm(u, v)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, resp.Header.Get("Location"), string(b)
}

var csrfField = regexp.MustCompile(`name="csrf" value="([^"]+)"`)
var codeShown = regexp.MustCompile(`<p class="code">([0-9A-Z-]{14})</p>`)

func TestAdminFlow(t *testing.T) {
	e := newEnv(t)
	c := e.adminClient()
	base := e.admin.URL + "/obmax-admin"

	if status, page := get(t, c, base+"/"); status != 200 || !strings.Contains(page, "Connexion") {
		t.Fatalf("login page: %d", status)
	}

	// A non-administrator is turned away.
	_, loc, _ := postForm(t, c, base+"/login", url.Values{"username": {"paul"}, "password": {"pw"}})
	if !strings.Contains(loc, "e=login") {
		t.Fatalf("non-admin login redirect %q", loc)
	}

	_, loc, _ = postForm(t, c, base+"/login", url.Values{"username": {"admin"}, "password": {"secret"}})
	if loc != "/obmax-admin/" {
		t.Fatalf("admin login redirect %q", loc)
	}
	status, page := get(t, c, base+"/")
	if status != 200 || !strings.Contains(page, "Inviter un appareil") || !strings.Contains(page, ">paul<") {
		t.Fatalf("dashboard: %d", status)
	}
	csrf := csrfField.FindStringSubmatch(page)[1]

	// Without the CSRF token nothing happens.
	if status, _, _ := postForm(t, c, base+"/invitations", url.Values{"user": {"id-paul"}}); status != http.StatusForbidden {
		t.Fatalf("missing csrf: %d", status)
	}

	status, _, page = postForm(t, c, base+"/invitations", url.Values{"csrf": {csrf}, "user": {"id-paul"}, "label": {"Shield du salon"}})
	m := codeShown.FindStringSubmatch(page)
	if status != 200 || m == nil {
		t.Fatalf("invite page: %d", status)
	}
	if !strings.Contains(page, "Saisis ce code : "+m[1]) {
		t.Fatal("ready-to-send message missing")
	}

	// The code shown enrolls a device for paul.
	status, body := e.enroll(m[1], newKey(t))
	if status != 200 || body["jellyfinUsername"] != "paul" {
		t.Fatalf("enroll with admin code: %d %v", status, body)
	}

	// The device is listed, and revocation goes through.
	_, page = get(t, c, base+"/")
	if !strings.Contains(page, "SHIELD Android TV") || !strings.Contains(page, "Shield du salon") {
		t.Fatal("device not listed")
	}
	_, loc, _ = postForm(t, c, base+"/devices/"+body["deviceId"].(string)+"/revoke", url.Values{"csrf": {csrf}})
	if !strings.Contains(loc, "n=revoked") {
		t.Fatalf("revoke redirect %q", loc)
	}
	var revoked bool
	e.srv.store.View(func(st *state) { revoked = st.deviceByID(body["deviceId"].(string)).RevokedAt != nil })
	if !revoked {
		t.Fatal("device not revoked")
	}

	// Signing out ends the session.
	postForm(t, c, base+"/logout", url.Values{"csrf": {csrf}})
	if _, page := get(t, c, base+"/"); !strings.Contains(page, "Connexion") {
		t.Fatal("still signed in after logout")
	}
}

func TestAdminLoginRateLimit(t *testing.T) {
	e := newEnv(t)
	c := e.adminClient()
	base := e.admin.URL + "/obmax-admin"
	for i := 0; i < 5; i++ {
		postForm(t, c, base+"/login", url.Values{"username": {"admin"}, "password": {"wrong"}})
	}
	_, loc, _ := postForm(t, c, base+"/login", url.Values{"username": {"admin"}, "password": {"secret"}})
	if !strings.Contains(loc, "e=rate") {
		t.Fatalf("6th login: %q", loc)
	}
}

func TestOnlyTheProxyGetsThrough(t *testing.T) {
	_, n, _ := net.ParseCIDR("192.168.0.101/32")
	s := &Server{cfg: Config{RequireProxy: true, TrustedProxies: []*net.IPNet{n}}}
	h := s.proxyOnly(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	cases := []struct {
		remote, path string
		want         int
	}{
		{"192.168.0.101:5000", "/v1/enroll", 200},
		{"192.168.0.50:5000", "/v1/enroll", 403},    // another LAN device
		{"192.168.0.50:5000", "/obmax-admin/", 403}, // bypassing the mTLS
		{"127.0.0.1:5000", "/v1/health", 200},       // container healthcheck
		{"127.0.0.1:5000", "/v1/enroll", 403},
	}
	for _, c := range cases {
		r := httptest.NewRequest("GET", c.path, nil)
		r.RemoteAddr = c.remote
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != c.want {
			t.Errorf("%s %s: %d, want %d", c.remote, c.path, w.Code, c.want)
		}
	}
}
