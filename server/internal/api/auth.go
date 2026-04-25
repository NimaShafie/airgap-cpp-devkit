package api

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func loadOrCreateToken(repoRoot string) (string, error) {
	tokenPath := filepath.Join(repoRoot, ".devkit-token")
	if data, err := os.ReadFile(tokenPath); err == nil {
		if t := strings.TrimSpace(string(data)); len(t) == 64 {
			return t, nil
		}
	}
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	token := hex.EncodeToString(b)
	_ = os.WriteFile(tokenPath, []byte(token+"\n"), 0o600)
	return token, nil
}

// tokenAuth enforces token authentication on every request except health,
// bootstrap, and static assets. The token is accepted via:
//   - X-DevKit-Token header
//   - devkit_token cookie
//   - ?devkit_token= query param
func (s *Server) tokenAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if p == "/health" || p == "/auth/bootstrap" || strings.HasPrefix(p, "/static/") {
			next.ServeHTTP(w, r)
			return
		}

		got := r.Header.Get("X-DevKit-Token")
		if got == "" {
			if c, err := r.Cookie("devkit_token"); err == nil {
				got = c.Value
			}
		}
		if got == "" {
			got = r.URL.Query().Get("devkit_token")
		}

		if got != s.token {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// handleAuthBootstrap validates the token from the URL and sets a session
// cookie, then redirects to the requested path.
func (s *Server) handleAuthBootstrap(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("token") != s.token {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	next := r.URL.Query().Get("next")
	if next == "" || !strings.HasPrefix(next, "/") {
		next = "/"
	}
	http.SetCookie(w, &http.Cookie{
		Name:     "devkit_token",
		Value:    s.token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
	})
	http.Redirect(w, r, next, http.StatusFound)
}
