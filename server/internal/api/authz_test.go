package api

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

const (
	tokAdmin    = "1111111111111111111111111111111111111111111111111111111111111111"
	tokOperator = "2222222222222222222222222222222222222222222222222222222222222222"
	tokViewer   = "3333333333333333333333333333333333333333333333333333333333333333"
)

func TestIdentifySharedTokenMode(t *testing.T) {
	s := newTestServer(t)
	s.token = testToken // no roster loaded → shared-token compatibility mode

	if id, ok := s.identify(testToken); !ok || id.Role != RoleAdmin || id.Name != "shared" {
		t.Fatalf("shared token should resolve to admin/shared, got %+v ok=%v", id, ok)
	}
	if _, ok := s.identify("nope"); ok {
		t.Fatal("wrong token must not resolve")
	}
	if _, ok := s.identify(""); ok {
		t.Fatal("empty token must not resolve")
	}
}

func TestIdentifyRosterMode(t *testing.T) {
	s := newTestServer(t)
	s.token = testToken // shared token still exists but MUST be ignored once a roster is present
	s.users = []User{
		{Name: "al", token: tokAdmin, Role: RoleAdmin},
		{Name: "op", token: tokOperator, Role: RoleOperator},
		{Name: "vi", token: tokViewer, Role: RoleViewer},
	}

	cases := []struct {
		tok  string
		name string
		role Role
	}{
		{tokAdmin, "al", RoleAdmin},
		{tokOperator, "op", RoleOperator},
		{tokViewer, "vi", RoleViewer},
	}
	for _, c := range cases {
		id, ok := s.identify(c.tok)
		if !ok || id.Name != c.name || id.Role != c.role {
			t.Fatalf("token %s: got %+v ok=%v, want %s/%s", c.tok, id, ok, c.name, c.role)
		}
	}
	// The shared token must NOT grant access when a roster is configured.
	if _, ok := s.identify(testToken); ok {
		t.Fatal("shared token must be rejected in roster mode")
	}
	if _, ok := s.identify("deadbeef"); ok {
		t.Fatal("unknown token must be rejected")
	}
}

func TestLoadUsers(t *testing.T) {
	dir := t.TempDir()
	body := `{"users":[
	  {"name":"al","token":"` + tokAdmin + `","role":"admin"},
	  {"name":"op","token":"` + tokOperator + `","role":"operator"},
	  {"name":"nokey","token":"","role":"admin"},
	  {"name":"","token":"` + tokViewer + `","role":"viewer"},
	  {"name":"short","token":"abc","role":"admin"}
	]}`
	if err := os.WriteFile(filepath.Join(dir, usersFileName), []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	users := loadUsers(dir)
	if len(users) != 2 {
		t.Fatalf("expected 2 valid users (malformed entries skipped), got %d", len(users))
	}
	if users[0].Role != RoleAdmin || users[1].Role != RoleOperator {
		t.Fatalf("roles parsed wrong: %+v", users)
	}
	// Absent file → nil (single-shared-token mode).
	if loadUsers(t.TempDir()) != nil {
		t.Fatal("absent roster file must return nil")
	}
}

func TestRequireRole(t *testing.T) {
	s := newTestServer(t)
	next := func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }

	call := func(min Role, caller Role, haveIdentity bool) int {
		h := s.requireRole(min, next)
		req := httptest.NewRequest("GET", "/install/cmake", nil)
		if haveIdentity {
			req = req.WithContext(context.WithValue(req.Context(), identityKey, identity{Name: "x", Role: caller}))
		}
		rec := httptest.NewRecorder()
		h(rec, req)
		return rec.Code
	}

	if code := call(RoleOperator, RoleViewer, true); code != http.StatusForbidden {
		t.Fatalf("viewer must be forbidden from operator route, got %d", code)
	}
	if code := call(RoleOperator, RoleOperator, true); code != http.StatusOK {
		t.Fatalf("operator must reach operator route, got %d", code)
	}
	if code := call(RoleOperator, RoleAdmin, true); code != http.StatusOK {
		t.Fatalf("admin must reach operator route, got %d", code)
	}
	if code := call(RoleAdmin, RoleOperator, true); code != http.StatusForbidden {
		t.Fatalf("operator must be forbidden from admin route, got %d", code)
	}
	if code := call(RoleViewer, RoleViewer, false); code != http.StatusForbidden {
		t.Fatalf("missing identity must be forbidden, got %d", code)
	}
}

func TestRoleParsingAndOrder(t *testing.T) {
	if !(RoleViewer < RoleOperator && RoleOperator < RoleAdmin) {
		t.Fatal("roles must be ordered viewer < operator < admin")
	}
	if parseRole("ADMIN") != RoleAdmin || parseRole("Operator") != RoleOperator ||
		parseRole("viewer") != RoleViewer || parseRole("garbage") != RoleViewer {
		t.Fatal("parseRole mismatch")
	}
	if RoleAdmin.String() != "admin" || RoleOperator.String() != "operator" || RoleViewer.String() != "viewer" {
		t.Fatal("Role.String mismatch")
	}
}
