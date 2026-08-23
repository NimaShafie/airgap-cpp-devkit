package api

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// Role is an ordered privilege level. A higher value grants everything a lower
// value does, so authorization is a single `>=` comparison.
type Role int

const (
	RoleViewer   Role = iota // read-only: dashboard, status, listings, logs
	RoleOperator             // install / uninstall / version + package operations
	RoleAdmin                // uploads, config, import, shutdown
)

func (r Role) String() string {
	switch r {
	case RoleAdmin:
		return "admin"
	case RoleOperator:
		return "operator"
	default:
		return "viewer"
	}
}

func parseRole(s string) Role {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "admin":
		return RoleAdmin
	case "operator":
		return RoleOperator
	default:
		return RoleViewer
	}
}

// User is one entry in the optional .devkit-users.json roster. token stays
// unexported so it is never serialised back out or logged.
type User struct {
	Name  string
	token string
	Role  Role
}

// identity is the resolved caller carried in the request context.
type identity struct {
	Name string
	Role Role
}

const usersFileName = ".devkit-users.json"

// loadUsers reads the per-user token roster if present. A missing, empty, or
// unparseable file returns nil, which selects single-shared-token mode so
// existing deployments keep working unchanged.
func loadUsers(repoRoot string) []User {
	data, err := os.ReadFile(filepath.Join(repoRoot, usersFileName))
	if err != nil {
		return nil
	}
	var doc struct {
		Users []struct {
			Name  string `json:"name"`
			Token string `json:"token"`
			Role  string `json:"role"`
		} `json:"users"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		log.Printf("auth: ignoring malformed %s: %v", usersFileName, err)
		return nil
	}
	var out []User
	for _, u := range doc.Users {
		t := strings.TrimSpace(u.Token)
		// Tokens are 64-hex like the shared token; anything else is skipped so a
		// truncated entry can never widen access.
		if u.Name == "" || len(t) != 64 {
			continue
		}
		out = append(out, User{Name: u.Name, token: t, Role: parseRole(u.Role)})
	}
	return out
}

// identify resolves a presented token to a caller. When a roster is configured
// it must match one of its tokens; otherwise the shared server token is
// accepted as a full-access admin. The comparison is constant-time so it does
// not leak how many leading bytes matched.
func (s *Server) identify(got string) (identity, bool) {
	if got == "" {
		return identity{}, false
	}
	if len(s.users) > 0 {
		for _, u := range s.users {
			if subtle.ConstantTimeCompare([]byte(got), []byte(u.token)) == 1 {
				return identity{Name: u.Name, Role: u.Role}, true
			}
		}
		return identity{}, false
	}
	if s.token != "" && subtle.ConstantTimeCompare([]byte(got), []byte(s.token)) == 1 {
		return identity{Name: "shared", Role: RoleAdmin}, true
	}
	return identity{}, false
}

func identityFromCtx(ctx context.Context) (identity, bool) {
	id, ok := ctx.Value(identityKey).(identity)
	return id, ok
}

// requireRole wraps a handler so it runs only for callers at or above min. Every
// authorised privileged call is audit-logged with the acting user so team
// servers have per-user attribution for state-changing actions.
func (s *Server) requireRole(min Role, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, ok := identityFromCtx(r.Context())
		if !ok || id.Role < min {
			http.Error(w, "Forbidden: requires "+min.String()+" role", http.StatusForbidden)
			return
		}
		log.Printf("audit: user=%q role=%s %s %s", id.Name, id.Role, r.Method, r.URL.Path)
		h(w, r)
	}
}
