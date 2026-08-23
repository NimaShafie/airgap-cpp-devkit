package api

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

const sessionMaxAge = 12 * 3600 // seconds

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

// tokenMatches compares the presented token to the server token in constant
// time so the comparison does not leak how many leading bytes matched.
func (s *Server) tokenMatches(got string) bool {
	return subtle.ConstantTimeCompare([]byte(got), []byte(s.token)) == 1
}

// requestToken extracts the presented token from the request header or the
// session cookie — the only two sources the server accepts. It is deliberately
// not read from the query string, which would persist in browser history,
// referrer headers and access logs.
func (s *Server) requestToken(r *http.Request) string {
	if got := r.Header.Get("X-DevKit-Token"); got != "" {
		return got
	}
	if c, err := r.Cookie("devkit_token"); err == nil {
		return c.Value
	}
	return ""
}

func (s *Server) tokenAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if p == "/health" || p == "/auth/bootstrap" || strings.HasPrefix(p, "/static/") {
			next.ServeHTTP(w, r)
			return
		}

		id, ok := s.identify(s.requestToken(r))
		if !ok {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		r = r.WithContext(context.WithValue(r.Context(), identityKey, id))
		next.ServeHTTP(w, r)
	})
}

// safeNext returns a local redirect target rebuilt from a parsed path. Anything
// with a scheme or host (including protocol-relative "//host" and backslash
// "/\\host" forms a browser treats as absolute) collapses to "/".
func safeNext(next string) string {
	if next == "" {
		return "/"
	}
	u, err := url.Parse(next)
	if err != nil || u.IsAbs() || u.Host != "" ||
		!strings.HasPrefix(u.Path, "/") || strings.HasPrefix(u.Path, "//") {
		return "/"
	}
	return u.Path
}

func (s *Server) handleAuthBootstrap(w http.ResponseWriter, r *http.Request) {
	// The one-time hand-off token still arrives in the query string here; make
	// sure it cannot leak onward through the referrer header.
	w.Header().Set("Referrer-Policy", "no-referrer")

	presented := r.URL.Query().Get("devkit_token")
	if _, ok := s.identify(presented); !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	next := safeNext(r.URL.Query().Get("next"))
	http.SetCookie(w, &http.Cookie{
		Name:     "devkit_token",
		Value:    presented,
		Path:     "/",
		HttpOnly: true,
		Secure:   r.TLS != nil,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   sessionMaxAge,
	})
	http.Redirect(w, r, next, http.StatusFound)
}
