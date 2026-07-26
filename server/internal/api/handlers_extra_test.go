package api

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

// jsonStr JSON-encodes s so it can be embedded safely in a request body
// (escapes backslashes in Windows paths, quotes, etc.).
func jsonStr(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func durSeconds(n int) time.Duration {
	return time.Duration(n) * time.Second
}

const (
	testToken    = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	hdrToken     = "X-DevKit-Token"
	toolCMakeID  = "cmake"
	pathTools    = "/api/tools"
	pathLayout   = "/api/layout"
	pathToolPre  = "/api/tool/"
	pathSetupAPI = "/api/setup"
)

// apiTestServer returns a Server wired for JSON-handler and router tests: maps
// initialised, a known token, setup marked complete, and one sample tool.
func apiTestServer(t *testing.T) *Server {
	s := newTestServer(t)
	s.OS = "linux"
	s.token = testToken
	s.prefix = t.TempDir()
	s.profiles = map[string]Profile{}
	s.metaOverrides = map[string]ToolMetaOverride{}
	s.allTools = []tools.Tool{{
		ID: toolCMakeID, Name: "CMake", Version: "3.29.0",
		Category: "Build Tools", ReceiptName: toolCMakeID,
	}}
	s.Config.SetupComplete = true
	// Serve the real templates from the repo's web/ dir (relative to this package).
	s.webFS = os.DirFS(filepath.Join("..", "..", "web"))
	return s
}

// authReq issues a request through h with the test auth token applied.
func authReq(t *testing.T, h http.Handler, method, path string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	var r *http.Request
	if body != nil {
		r = httptest.NewRequest(method, path, bytes.NewReader(body))
	} else {
		r = httptest.NewRequest(method, path, nil)
	}
	r.Header.Set(hdrToken, testToken)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return rec
}

func decodeObj(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &m); err != nil {
		t.Fatalf("decode JSON (%s): %v", rec.Body.String(), err)
	}
	return m
}

// ── Router + JSON handlers ───────────────────────────────────────────────────

func TestRouterHealthAndTools(t *testing.T) {
	h := apiTestServer(t).Routes()

	rec := authReq(t, h, http.MethodGet, "/health", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("health: want 200, got %d", rec.Code)
	}
	if got := decodeObj(t, rec)["status"]; got != "ok" {
		t.Fatalf("health status = %v", got)
	}

	rec = authReq(t, h, http.MethodGet, pathTools, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("tools: want 200, got %d", rec.Code)
	}
	var arr []map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &arr); err != nil {
		t.Fatalf("tools decode: %v", err)
	}
	if len(arr) != 1 {
		t.Fatalf("want 1 tool, got %d", len(arr))
	}
}

func TestRouterAPITool(t *testing.T) {
	h := apiTestServer(t).Routes()

	if rec := authReq(t, h, http.MethodGet, pathToolPre+toolCMakeID, nil); rec.Code != http.StatusOK {
		t.Fatalf("known tool: want 200, got %d", rec.Code)
	}
	if rec := authReq(t, h, http.MethodGet, pathToolPre+"does-not-exist", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("unknown tool: want 404, got %d", rec.Code)
	}
}

func TestPrefixLifecycle(t *testing.T) {
	s := apiTestServer(t)
	h := s.Routes()
	const prefixPath = "/api/prefix"

	if rec := authReq(t, h, http.MethodGet, prefixPath, nil); rec.Code != http.StatusOK {
		t.Fatalf("get prefix: want 200, got %d", rec.Code)
	}

	// Rejected: empty and non-absolute values.
	for _, bad := range []string{`{"prefix":""}`, `{"prefix":"relative/dir"}`} {
		rec := authReq(t, h, http.MethodPost, prefixPath, []byte(bad))
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("set prefix %q: want 400, got %d", bad, rec.Code)
		}
	}

	// Accepted: an absolute, clean path.
	abs := t.TempDir()
	rec := authReq(t, h, http.MethodPost, prefixPath, []byte(`{"prefix":`+jsonStr(abs)+`}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("set prefix: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}
	if s.currentPrefix() != abs {
		t.Fatalf("prefix not applied: %q", s.currentPrefix())
	}

	if rec := authReq(t, h, http.MethodDelete, prefixPath, nil); rec.Code != http.StatusOK {
		t.Fatalf("reset prefix: want 200, got %d", rec.Code)
	}
}

func TestProfilesCRUD(t *testing.T) {
	h := apiTestServer(t).Routes()
	const profilesPath = "/api/profiles"

	if rec := authReq(t, h, http.MethodGet, profilesPath, nil); rec.Code != http.StatusOK {
		t.Fatalf("get profiles: want 200, got %d", rec.Code)
	}

	// Valid create.
	rec := authReq(t, h, http.MethodPost, profilesPath, []byte(`{"id":"p1","name":"P1","tool_ids":["cmake"]}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("save profile: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}
	// Invalid: missing id.
	if rec := authReq(t, h, http.MethodPost, profilesPath, []byte(`{"name":"x"}`)); rec.Code != http.StatusBadRequest {
		t.Fatalf("save invalid profile: want 400, got %d", rec.Code)
	}
	// Delete existing, then a missing one.
	if rec := authReq(t, h, http.MethodDelete, profilesPath+"/p1", nil); rec.Code != http.StatusOK {
		t.Fatalf("delete profile: want 200, got %d", rec.Code)
	}
	if rec := authReq(t, h, http.MethodDelete, profilesPath+"/missing", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("delete missing profile: want 404, got %d", rec.Code)
	}
}

func TestToolMetaOverride(t *testing.T) {
	s := apiTestServer(t)
	h := s.Routes()
	metaPath := pathToolPre + toolCMakeID + "/meta"

	// Save for a known tool, then confirm the override is applied on read.
	rec := authReq(t, h, http.MethodPost, metaPath, []byte(`{"name":"CMake Custom","version":"4.0.0"}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("save meta: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}
	rec = authReq(t, h, http.MethodGet, pathToolPre+toolCMakeID, nil)
	if got := decodeObj(t, rec)["name"]; got != "CMake Custom" {
		t.Fatalf("override not applied, name = %v", got)
	}

	// Unknown tool → 404; malformed body → 400.
	if rec := authReq(t, h, http.MethodPost, pathToolPre+"nope/meta", []byte(`{}`)); rec.Code != http.StatusNotFound {
		t.Fatalf("meta unknown tool: want 404, got %d", rec.Code)
	}
	if rec := authReq(t, h, http.MethodPost, metaPath, []byte(`not json`)); rec.Code != http.StatusBadRequest {
		t.Fatalf("meta bad body: want 400, got %d", rec.Code)
	}

	// Reset removes it.
	if rec := authReq(t, h, http.MethodDelete, metaPath, nil); rec.Code != http.StatusOK {
		t.Fatalf("reset meta: want 200, got %d", rec.Code)
	}
}

func TestConfigSave(t *testing.T) {
	s := apiTestServer(t)
	h := s.Routes()

	rec := authReq(t, h, http.MethodPost, "/api/config",
		[]byte(`{"team_name":"Team","org_name":"Org","devkit_name":"Kit","team_config_repo":""}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("save config: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}
	if s.Config.DevkitName != "Kit" {
		t.Fatalf("config not persisted: %q", s.Config.DevkitName)
	}

	// A non-encrypted transport is rejected.
	if rec := authReq(t, h, http.MethodPost, "/api/config",
		[]byte(`{"team_config_repo":"http://insecure/repo.git"}`)); rec.Code != http.StatusBadRequest {
		t.Fatalf("insecure repo url: want 400, got %d", rec.Code)
	}
}

func TestLayoutLifecycle(t *testing.T) {
	h := apiTestServer(t).Routes()

	rec := authReq(t, h, http.MethodGet, pathLayout, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("get layout: want 200, got %d", rec.Code)
	}
	rec = authReq(t, h, http.MethodPost, pathLayout, []byte(`{"category_order":["Build Tools"]}`))
	if rec.Code != http.StatusOK {
		t.Fatalf("save layout: want 200, got %d (%s)", rec.Code, rec.Body.String())
	}
	if rec := authReq(t, h, http.MethodDelete, pathLayout, nil); rec.Code != http.StatusOK {
		t.Fatalf("reset layout: want 200, got %d", rec.Code)
	}
}

func TestTeamStatusAndLayoutData(t *testing.T) {
	h := apiTestServer(t).Routes()

	if rec := authReq(t, h, http.MethodGet, "/api/team/status", nil); rec.Code != http.StatusOK {
		t.Fatalf("team status: want 200, got %d", rec.Code)
	}

	if rec := authReq(t, h, http.MethodPost, pathLayout,
		[]byte(`{"category_order":["Build Tools","Languages"]}`)); rec.Code != http.StatusOK {
		t.Fatalf("save layout: want 200, got %d", rec.Code)
	}
	rec := authReq(t, h, http.MethodGet, pathLayout, nil)
	var l Layout
	if err := json.Unmarshal(rec.Body.Bytes(), &l); err != nil {
		t.Fatalf("layout decode: %v", err)
	}
	if len(l.CategoryOrder) != 2 {
		t.Fatalf("category order not persisted: %+v", l.CategoryOrder)
	}
}

func TestValidateRepoURL(t *testing.T) {
	for _, u := range []string{"", "https://example.com/r.git", "ssh://git@host/r.git"} {
		if err := validateRepoURL(u); err != nil {
			t.Errorf("validateRepoURL(%q) unexpected error: %v", u, err)
		}
	}
	for _, u := range []string{"http://example.com/r.git", "ftp://x/y"} {
		if err := validateRepoURL(u); err == nil {
			t.Errorf("validateRepoURL(%q) = nil, want error", u)
		}
	}
}

func TestPrefixAndLayoutHelpers(t *testing.T) {
	if detectPrefix("linux") == "" || detectPrefix("windows") == "" {
		t.Error("detectPrefix returned empty")
	}
	if nonceFromCtx(context.Background()) != "" {
		t.Error("nonceFromCtx of empty context should be empty")
	}
	l := emptyLayout()
	if l.CategoryOrder == nil || l.CategoryNames == nil || l.ToolOrder == nil {
		t.Error("emptyLayout must have non-nil fields")
	}
}

func TestUploadConfigEndpoint(t *testing.T) {
	h := apiTestServer(t).Routes()
	rec := authReq(t, h, http.MethodGet, "/packages/upload-config", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("upload-config: want 200, got %d", rec.Code)
	}
	if _, ok := decodeObj(t, rec)["max_bytes"]; !ok {
		t.Fatalf("upload-config missing max_bytes: %s", rec.Body.String())
	}
}

// ── Middleware & auth ────────────────────────────────────────────────────────

func TestTokenAuth(t *testing.T) {
	s := apiTestServer(t)
	ok := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	h := s.tokenAuth(ok)

	// Missing / wrong token on a protected path → 401.
	for _, tok := range []string{"", "wrong"} {
		r := httptest.NewRequest(http.MethodGet, pathTools, nil)
		if tok != "" {
			r.Header.Set(hdrToken, tok)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, r)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("token %q: want 401, got %d", tok, rec.Code)
		}
	}

	// Correct header and correct cookie both pass.
	if rec := authReq(t, h, http.MethodGet, pathTools, nil); rec.Code != http.StatusOK {
		t.Fatalf("header auth: want 200, got %d", rec.Code)
	}
	r := httptest.NewRequest(http.MethodGet, pathTools, nil)
	r.AddCookie(&http.Cookie{Name: "devkit_token", Value: testToken})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != http.StatusOK {
		t.Fatalf("cookie auth: want 200, got %d", rec.Code)
	}

	// Exempt path needs no token.
	r = httptest.NewRequest(http.MethodGet, "/health", nil)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != http.StatusOK {
		t.Fatalf("exempt /health: want 200, got %d", rec.Code)
	}
}

func TestTokenMatches(t *testing.T) {
	s := apiTestServer(t)
	if !s.tokenMatches(testToken) {
		t.Fatal("correct token rejected")
	}
	if s.tokenMatches("nope") {
		t.Fatal("wrong token accepted")
	}
}

func TestSetupCheckRedirect(t *testing.T) {
	s := apiTestServer(t)
	s.Config.SetupComplete = false
	ok := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	h := s.setupCheck(ok)

	r := httptest.NewRequest(http.MethodGet, pathTools, nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != http.StatusFound {
		t.Fatalf("incomplete setup: want 302, got %d", rec.Code)
	}
	if loc := rec.Header().Get("Location"); loc != pathSetup {
		t.Fatalf("redirect target = %q", loc)
	}

	// Exempt path is allowed through even when setup is incomplete.
	r = httptest.NewRequest(http.MethodGet, pathSetup, nil)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	if rec.Code != http.StatusOK {
		t.Fatalf("setup path: want 200, got %d", rec.Code)
	}
}

func TestResponseHeaders(t *testing.T) {
	ok := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	h := responseHeaders(ok)
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)

	if rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Error("missing nosniff")
	}
	if rec.Header().Get("X-Frame-Options") != "DENY" {
		t.Error("missing frame-options DENY")
	}
	csp := rec.Header().Get("Content-Security-Policy")
	if !strings.Contains(csp, "default-src 'self'") || !strings.Contains(csp, "nonce-") {
		t.Errorf("CSP missing expected directives: %q", csp)
	}
}

func TestHandleAuthBootstrap(t *testing.T) {
	s := apiTestServer(t)

	// Valid token sets the session cookie and redirects to a safe next.
	r := httptest.NewRequest(http.MethodGet, "/auth/bootstrap?devkit_token="+testToken+"&next=/status", nil)
	rec := httptest.NewRecorder()
	s.handleAuthBootstrap(rec, r)
	if rec.Code != http.StatusFound {
		t.Fatalf("bootstrap: want 302, got %d", rec.Code)
	}
	if loc := rec.Header().Get("Location"); loc != "/status" {
		t.Fatalf("bootstrap redirect = %q", loc)
	}
	if !strings.Contains(rec.Header().Get("Set-Cookie"), "devkit_token="+testToken) {
		t.Fatalf("bootstrap did not set session cookie: %q", rec.Header().Get("Set-Cookie"))
	}

	// Wrong token is rejected.
	r = httptest.NewRequest(http.MethodGet, "/auth/bootstrap?devkit_token=bad", nil)
	rec = httptest.NewRecorder()
	s.handleAuthBootstrap(rec, r)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("bootstrap bad token: want 401, got %d", rec.Code)
	}
}

// ── Pure helpers ─────────────────────────────────────────────────────────────

func TestSafeNext(t *testing.T) {
	cases := map[string]string{
		"":                 "/",
		"/dashboard":       "/dashboard",
		"//evil.example":   "/",
		"https://evil.com": "/",
		"relative":         "/",
	}
	for in, want := range cases {
		if got := safeNext(in); got != want {
			t.Errorf("safeNext(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSlugify(t *testing.T) {
	cases := map[string]string{
		"My Tool":     "my-tool",
		"  Hello  ":   "hello",
		"C++ Builder": "c-builder",
		"---":         "",
	}
	for in, want := range cases {
		if got := slugify(in); got != want {
			t.Errorf("slugify(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSanitizeDisplayName(t *testing.T) {
	if got := sanitizeDisplayName(`a"b'<c>\d`); got != "abcd" {
		t.Errorf("sanitizeDisplayName stripped wrong: %q", got)
	}
	if got := sanitizeDisplayName("  keep me  "); got != "keep me" {
		t.Errorf("sanitizeDisplayName trim = %q", got)
	}
}

func TestFormatUptime(t *testing.T) {
	cases := []struct {
		secs int
		want string
	}{
		{30, "30s"},
		{90, "1m"},
		{3660, "1h 1m"},
		{90061, "1d 1h 1m"},
	}
	for _, c := range cases {
		if got := formatUptime(durSeconds(c.secs)); got != c.want {
			t.Errorf("formatUptime(%ds) = %q, want %q", c.secs, got, c.want)
		}
	}
}

func TestTimeFormatID(t *testing.T) {
	if timeFormatID("") == "" {
		t.Error("empty stored format should resolve to a default id")
	}
	if got := timeFormatID("iso"); got != "iso" {
		t.Errorf("timeFormatID(iso) = %q", got)
	}
}

func TestValidPkgSpec(t *testing.T) {
	valid := [][2]string{{"boost", "1.83.0"}, {"zlib", ""}, {"pkg_name", "various"}}
	for _, v := range valid {
		if !validPkgSpec(v[0], v[1]) {
			t.Errorf("validPkgSpec(%q,%q) = false, want true", v[0], v[1])
		}
	}
	invalid := [][2]string{{"-bad", "1.0"}, {"has space", "1.0"}, {"ok", "bad version"}}
	for _, v := range invalid {
		if validPkgSpec(v[0], v[1]) {
			t.Errorf("validPkgSpec(%q,%q) = true, want false", v[0], v[1])
		}
	}
}

func TestOSLabelUnknown(t *testing.T) {
	if got := osLabel("plan9"); got != "plan9" {
		t.Errorf("osLabel(plan9) = %q, want passthrough", got)
	}
}

func TestGenerateNonce(t *testing.T) {
	a, err := generateNonce()
	if err != nil {
		t.Fatalf("generateNonce: %v", err)
	}
	b, err := generateNonce()
	if err != nil {
		t.Fatalf("generateNonce: %v", err)
	}
	if a == "" || a == b {
		t.Errorf("nonce not unique/non-empty: %q %q", a, b)
	}
}

func TestAPIReferenceGroups(t *testing.T) {
	groups := apiReference()
	if len(groups) == 0 {
		t.Fatal("apiReference returned no groups")
	}
	for _, g := range groups {
		if g.Name == "" || len(g.Endpoints) == 0 {
			t.Fatalf("group %q has no endpoints", g.Name)
		}
		for _, e := range g.Endpoints {
			if e.Method == "" || e.Path == "" {
				t.Fatalf("endpoint in %q missing method/path: %+v", g.Name, e)
			}
		}
	}
}

func TestLogDirForID(t *testing.T) {
	s := apiTestServer(t)
	dir, ok := s.logDirForID("toolchains/clang")
	if !ok || !strings.Contains(dir, "toolchains_clang") {
		t.Fatalf("logDirForID sanitised path unexpected: %q ok=%v", dir, ok)
	}
	// A traversal attempt must still resolve inside devkit-logs.
	if d, ok := s.logDirForID("../../etc"); ok && strings.Contains(d, ".."+string(os.PathSeparator)) {
		t.Fatalf("logDirForID allowed traversal: %q", d)
	}
}
