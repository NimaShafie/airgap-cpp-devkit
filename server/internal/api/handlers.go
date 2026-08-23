package api

import (
	"archive/zip"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	devconfig "github.com/nimzshafie/airgap-devkit/server/internal/config"
	"github.com/nimzshafie/airgap-devkit/server/internal/export"
	"github.com/nimzshafie/airgap-devkit/server/internal/team"
	"github.com/nimzshafie/airgap-devkit/server/internal/timefmt"
	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

type ctxKey int

const (
	nonceKey ctxKey = iota
	identityKey
)

// Shared literals used across the api package.
const (
	pathSetup       = "/setup"
	pathAPIPrefix   = "/api/prefix"
	pathAPILayout   = "/api/layout"
	pathAPIProfiles = "/api/profiles"

	errToolNotFound = "tool not found"
	errInvalidBody  = "invalid body"
	errSaveConfig   = "failed to save config: "

	devkitDirName     = "airgap-cpp-devkit"
	devToolsDir       = "dev-tools"
	devkitJSONFile    = "devkit.json"
	setupScriptName   = "setup.sh"
	userPackagesDir   = "user-packages"
	headerContentType = "Content-Type"
	mimeJSON          = "application/json"
	noneLabel         = "(none)"
	errLinePrefix     = "✗ ERROR: "
)

func generateNonce() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(b), nil
}

func nonceFromCtx(ctx context.Context) string {
	if v, ok := ctx.Value(nonceKey).(string); ok {
		return v
	}
	return ""
}

type Server struct {
	RepoRoot    string
	PrebuiltDir string
	OS          string
	Bash        string
	Config      devconfig.Config
	webFS       fs.FS
	token       string
	users       []User
	startTime   time.Time

	mu            sync.RWMutex
	allTools      []tools.Tool
	prefix        string
	profiles      map[string]Profile
	metaOverrides map[string]ToolMetaOverride
	teamStatus    team.Status
}

type ToolMetaOverride struct {
	Name         string `json:"name,omitempty"`
	Version      string `json:"version,omitempty"`
	VersionLabel string `json:"version_label,omitempty"`
	Category     string `json:"category,omitempty"`
	Description  string `json:"description,omitempty"`
	Estimate     string `json:"estimate,omitempty"`
}

type Profile struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	ToolIDs     []string `json:"tool_ids"`
	Color       string   `json:"color"`
}

func New(repoRoot, prebuiltDir, currentOS string, cfg devconfig.Config, webFS fs.FS) (*Server, error) {
	loaded, err := tools.Load(repoRoot)
	if err != nil {
		return nil, err
	}

	// Apply the persisted timestamp style before any page renders.
	timefmt.SetFormat(cfg.TimeFormat)

	tok, err := loadOrCreateToken(repoRoot)
	if err != nil {
		return nil, fmt.Errorf("auth token: %w", err)
	}

	allIDs := make([]string, 0, len(loaded))
	for _, t := range loaded {
		allIDs = append(allIDs, t.ID)
	}

	s := &Server{
		RepoRoot:    repoRoot,
		PrebuiltDir: prebuiltDir,
		OS:          currentOS,
		Bash:        tools.FindBash(),
		Config:      cfg,
		webFS:       webFS,
		token:       tok,
		startTime:   time.Now(),
		allTools:    loaded,
		prefix:      detectPrefix(currentOS),
		profiles:    defaultProfiles(repoRoot, allIDs),
	}

	// Optional per-user token roster. Absent file → single-shared-token mode.
	s.users = loadUsers(repoRoot)

	// Load persisted prefix override
	if p := readPrefixOverride(repoRoot); p != "" {
		s.prefix = p
	}

	// Load persisted profiles (overrides defaults if file exists)
	s.loadProfiles()

	// Load persisted tool meta overrides
	s.metaOverrides = make(map[string]ToolMetaOverride)
	s.loadMetaOverrides()

	// Background team config sync on startup
	if cfg.TeamConfigRepo != "" {
		s.teamStatus = team.Status{Configured: true, RepoURL: cfg.TeamConfigRepo}
		go s.syncTeamConfig()
	}

	return s, nil
}

func (s *Server) Token() string { return s.token }

func responseHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Fail closed: without a fresh unpredictable nonce the CSP would have to
		// fall back to a static value that injected inline scripts could reuse.
		nonce, err := generateNonce()
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		ctx := context.WithValue(r.Context(), nonceKey, nonce)
		r = r.WithContext(ctx)

		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		// The UI is entirely first-party: isolate its browsing context and turn off
		// browser features it never uses, so injected content has nothing to reach for.
		w.Header().Set("Permissions-Policy", "geolocation=(), camera=(), microphone=(), payment=(), usb=()")
		w.Header().Set("Cross-Origin-Opener-Policy", "same-origin")
		w.Header().Set("Cross-Origin-Resource-Policy", "same-origin")
		if r.TLS != nil {
			w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		// Inline <script> blocks carry this per-request nonce; script-src-attr keeps
		// existing inline event handlers working without a blanket unsafe-inline for
		// script blocks. Inline style attributes still need unsafe-inline in style-src.
		// form-action and frame-src are pinned explicitly because they do not inherit default-src.
		w.Header().Set("Content-Security-Policy",
			"default-src 'self'; script-src 'self' 'nonce-"+nonce+"'; "+
				"script-src-attr 'unsafe-inline'; style-src 'self' 'unsafe-inline'; "+
				"img-src 'self' data:; object-src 'none'; base-uri 'self'; "+
				"form-action 'self'; frame-src 'none'; frame-ancestors 'none'")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) setupCheck(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if s.Config.SetupComplete ||
			p == pathSetup || p == "/api/setup" ||
			strings.HasPrefix(p, "/auth/") ||
			strings.HasPrefix(p, "/static/") ||
			p == "/health" {
			next.ServeHTTP(w, r)
			return
		}
		http.Redirect(w, r, pathSetup, http.StatusFound)
	})
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(responseHeaders)
	r.Use(s.tokenAuth)
	r.Use(s.setupCheck)
	// Authorization: read-only endpoints accept any authenticated caller
	// (viewer). State-changing tool operations require operator; uploads,
	// config, import, and shutdown require admin. In single-shared-token mode
	// the shared token resolves to admin, so this leaves that mode unchanged.
	r.Get("/auth/bootstrap", s.handleAuthBootstrap)
	r.Get(pathSetup, s.handleSetup)
	r.Post("/api/setup", s.requireRole(RoleAdmin, s.handleSaveSetup))
	r.Get("/", s.handleDashboard)
	r.Get("/logs", s.handleLogs)
	r.Get("/health", s.handleHealth)
	r.Get("/status", s.handleStatusPage)
	r.Get("/api-docs", s.handleAPIDocs)
	r.Get("/api/network", s.handleNetworkStatus)
	r.Get("/api/updates", s.handleCheckUpdates)
	r.Get("/api/update-history", s.handleUpdateHistory)
	r.Get("/download-update/{id}", s.requireRole(RoleOperator, s.handleDownloadUpdate))
	r.Get("/api/tool/{id}/versions", s.handleToolVersions)
	r.Delete("/api/tool/{id}/versions/{ver}", s.requireRole(RoleOperator, s.handleDeleteVersion))
	r.Post("/api/tool/{id}/versions/{ver}/use", s.requireRole(RoleOperator, s.handleUseVersion))
	r.Get("/api/tools", s.handleAPITools)
	r.Get("/api/tool/{id}", s.handleAPITool)
	r.Get("/api/tool/{id}/manual-install", s.handleManualInstall)
	r.Get(pathAPIPrefix, s.handleGetPrefix)
	r.Post(pathAPIPrefix, s.requireRole(RoleOperator, s.handleSetPrefix))
	r.Delete(pathAPIPrefix, s.requireRole(RoleOperator, s.handleResetPrefix))
	r.Get("/api/export", s.handleExport)
	r.Post("/api/import", s.requireRole(RoleAdmin, s.handleImport))
	r.Get(pathAPIProfiles, s.handleGetProfiles)
	r.Post(pathAPIProfiles, s.requireRole(RoleOperator, s.handleSaveProfile))
	r.Delete("/api/profiles/{id}", s.requireRole(RoleOperator, s.handleDeleteProfile))
	r.Post("/api/config", s.requireRole(RoleAdmin, s.handleSaveConfig))
	r.Post("/api/time-format", s.requireRole(RoleOperator, s.handleSaveTimeFormat))
	r.Get("/api/team/status", s.handleTeamStatus)
	r.Post("/api/team/sync", s.requireRole(RoleOperator, s.handleTeamSync))
	r.Get("/install/{id}", s.requireRole(RoleOperator, s.handleInstall))
	r.Delete("/uninstall/{id}", s.requireRole(RoleOperator, s.handleUninstall))
	r.Get("/install-profile/{id}", s.requireRole(RoleOperator, s.handleInstallProfile))
	r.Get("/check/{id}", s.requireRole(RoleOperator, s.handleCheck))
	r.Get("/api/tool/{id}/log", s.handleToolLog)
	r.Get("/api/tool/{id}/logs", s.handleToolLogList)
	r.Get("/api/tool/{id}/logs/{file}", s.handleToolLogFile)
	r.Get("/api/tool/{id}/packages/status", s.handleBundlePackageStatus)
	r.Get("/install-pkg/{id}/{pkg}", s.requireRole(RoleOperator, s.handleInstallPackage))
	r.Get("/remove-pkg/{id}/{pkg}", s.requireRole(RoleOperator, s.handleRemovePackage))
	// Resumable chunked upload (tus protocol). The handler owns every method
	// under this prefix (POST create, PATCH chunk, HEAD offset, DELETE abort).
	// Uploaded packages carry an executable setup.sh, so the whole prefix is
	// admin-gated.
	if tush := s.tusHandler(); tush != nil {
		r.Handle("/packages/upload", s.requireRole(RoleAdmin, tush.ServeHTTP))
		r.Handle("/packages/upload/*", s.requireRole(RoleAdmin, tush.ServeHTTP))
	}
	r.Get("/packages/upload-config", s.handleUploadConfig)
	r.Post("/packages/import", s.requireRole(RoleAdmin, s.handlePackageImport))
	r.Delete("/packages/{id}", s.requireRole(RoleOperator, s.handlePackageDelete))
	r.Get(pathAPILayout, s.handleGetLayout)
	r.Post(pathAPILayout, s.requireRole(RoleOperator, s.handleSaveLayout))
	r.Delete(pathAPILayout, s.requireRole(RoleOperator, s.handleResetLayout))
	r.Post("/api/open-prefix", s.requireRole(RoleOperator, s.handleOpenPrefix))
	r.Post("/api/tool/{id}/meta", s.requireRole(RoleOperator, s.handleSaveToolMeta))
	r.Delete("/api/tool/{id}/meta", s.requireRole(RoleOperator, s.handleResetToolMeta))
	r.Get("/api/health/tools", s.handleHealthTools)
	r.Post("/shutdown", s.requireRole(RoleAdmin, s.handleShutdown))
	return r
}

// ── Profile persistence ──────────────────────────────────────────────────────

// defaultProfiles returns the built-in install profiles. If
// profiles.defaults.json exists at the repo root it is the source of truth
// (keys beginning with "_" are treated as documentation and skipped; a
// "__all__" sentinel in tool_ids expands to every discovered tool id).
// A compiled-in fallback is returned when the file is missing or invalid so
// the server always has working defaults.
func defaultProfiles(repoRoot string, allIDs []string) map[string]Profile {
	builtin := map[string]Profile{
		"minimal": {ID: "minimal", Name: "Minimal", Description: "Required tools only", Color: "gray",
			ToolIDs: []string{"toolchains/clang", "cmake", "python", "style-formatter"}},
		"cpp-dev": {ID: "cpp-dev", Name: "C++ Developer", Description: "Core C++ development tools", Color: "blue",
			ToolIDs: []string{"toolchains/clang", "cmake", "python", "conan", "vscode-extensions", "sqlite", "zlib"}},
		"devops": {ID: "devops", Name: "DevOps", Description: "Infrastructure and automation tools", Color: "green",
			ToolIDs: []string{"cmake", "python", "conan", "sqlite"}},
		"full": {ID: "full", Name: "Full Install", Description: "All available tools", Color: "purple",
			ToolIDs: allIDs},
	}

	data, err := os.ReadFile(filepath.Join(repoRoot, "profiles.defaults.json"))
	if err != nil {
		return builtin
	}
	// Decode per-key so documentation entries (e.g. "_doc": "...") that are not
	// profile objects don't fail the whole parse.
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return builtin
	}
	out := make(map[string]Profile, len(raw))
	for id, msg := range raw {
		if strings.HasPrefix(id, "_") {
			continue
		}
		var p Profile
		if err := json.Unmarshal(msg, &p); err != nil {
			continue
		}
		p.ID = id
		if len(p.ToolIDs) == 1 && p.ToolIDs[0] == "__all__" {
			p.ToolIDs = allIDs
		}
		out[id] = p
	}
	if len(out) == 0 {
		return builtin
	}
	return out
}

func (s *Server) profilesPath() string {
	return filepath.Join(s.RepoRoot, "profiles.json")
}

func (s *Server) loadProfiles() {
	data, err := os.ReadFile(s.profilesPath())
	if err != nil {
		return // keep hardcoded defaults
	}
	var loaded map[string]Profile
	if json.Unmarshal(data, &loaded) == nil && len(loaded) > 0 {
		s.mu.Lock()
		s.profiles = loaded
		s.mu.Unlock()
	}
}

func (s *Server) saveProfiles() error {
	s.mu.RLock()
	data, err := json.MarshalIndent(s.profiles, "", "  ")
	s.mu.RUnlock()
	if err != nil {
		return err
	}
	return os.WriteFile(s.profilesPath(), data, 0o600)
}

// ── Profile CRUD handlers ────────────────────────────────────────────────────

func (s *Server) handleGetProfiles(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	p := s.profiles
	s.mu.RUnlock()
	jsonOK(w, p)
}

func (s *Server) handleSaveProfile(w http.ResponseWriter, r *http.Request) {
	var p Profile
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil || p.ID == "" {
		jsonErr(w, "invalid profile: id required", 400)
		return
	}
	s.mu.Lock()
	s.profiles[p.ID] = p
	s.mu.Unlock()
	if err := s.saveProfiles(); err != nil {
		jsonErr(w, "failed to save profiles: "+err.Error(), 500)
		return
	}
	jsonOK(w, map[string]any{"ok": true, "profile": p})
}

func (s *Server) handleDeleteProfile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	s.mu.Lock()
	_, exists := s.profiles[id]
	if exists {
		delete(s.profiles, id)
	}
	s.mu.Unlock()
	if !exists {
		jsonErr(w, "profile not found", 404)
		return
	}
	if err := s.saveProfiles(); err != nil {
		jsonErr(w, "failed to save profiles: "+err.Error(), 500)
		return
	}
	jsonOK(w, map[string]any{"ok": true})
}

// ── Tool meta override persistence ──────────────────────────────────────────

func (s *Server) metaOverridesPath() string {
	return filepath.Join(s.RepoRoot, "tool-meta-overrides.json")
}

func (s *Server) loadMetaOverrides() {
	data, err := os.ReadFile(s.metaOverridesPath())
	if err != nil {
		return
	}
	var loaded map[string]ToolMetaOverride
	if json.Unmarshal(data, &loaded) == nil && len(loaded) > 0 {
		s.mu.Lock()
		s.metaOverrides = loaded
		s.mu.Unlock()
	}
}

func (s *Server) saveMetaOverrides() error {
	s.mu.RLock()
	data, err := json.MarshalIndent(s.metaOverrides, "", "  ")
	s.mu.RUnlock()
	if err != nil {
		return err
	}
	return os.WriteFile(s.metaOverridesPath(), data, 0o600)
}

func (s *Server) applyMetaOverride(t tools.Tool) tools.Tool {
	s.mu.RLock()
	ov, ok := s.metaOverrides[t.ID]
	s.mu.RUnlock()
	if !ok {
		return t
	}
	if ov.Name != "" {
		t.Name = ov.Name
	}
	if ov.Version != "" {
		t.Version = ov.Version
	}
	if ov.VersionLabel != "" {
		t.VersionLabel = ov.VersionLabel
	}
	if ov.Category != "" {
		t.Category = ov.Category
	}
	if ov.Description != "" {
		t.Description = ov.Description
	}
	if ov.Estimate != "" {
		t.Estimate = ov.Estimate
	}
	return t
}

func (s *Server) handleSaveToolMeta(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if _, ok := s.findTool(id); !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}
	var ov ToolMetaOverride
	if err := json.NewDecoder(r.Body).Decode(&ov); err != nil {
		jsonErr(w, errInvalidBody, 400)
		return
	}
	s.mu.Lock()
	s.metaOverrides[id] = ov
	s.mu.Unlock()
	if err := s.saveMetaOverrides(); err != nil {
		jsonErr(w, "failed to save: "+err.Error(), 500)
		return
	}
	jsonOK(w, map[string]any{"ok": true})
}

func (s *Server) handleResetToolMeta(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	s.mu.Lock()
	delete(s.metaOverrides, id)
	s.mu.Unlock()
	if err := s.saveMetaOverrides(); err != nil {
		jsonErr(w, "failed to save: "+err.Error(), 500)
		return
	}
	jsonOK(w, map[string]any{"ok": true})
}

// ── Config save handler ──────────────────────────────────────────────────────

func (s *Server) handleSaveConfig(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TeamName       string `json:"team_name"`
		OrgName        string `json:"org_name"`
		DevkitName     string `json:"devkit_name"`
		TeamConfigRepo string `json:"team_config_repo"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonErr(w, errInvalidBody, 400)
		return
	}
	if err := validateRepoURL(body.TeamConfigRepo); err != nil {
		jsonErr(w, err.Error(), 400)
		return
	}
	s.mu.Lock()
	if body.TeamName == "" {
		s.Config.TeamName = "My Team"
	} else {
		s.Config.TeamName = body.TeamName
	}
	s.Config.OrgName = body.OrgName
	if body.DevkitName == "" {
		s.Config.DevkitName = "AirGap DevKit"
	} else {
		s.Config.DevkitName = body.DevkitName
	}
	repoChanged := body.TeamConfigRepo != s.Config.TeamConfigRepo
	s.Config.TeamConfigRepo = body.TeamConfigRepo
	cfg := s.Config
	s.mu.Unlock()

	if err := devconfig.Save(s.RepoRoot, cfg); err != nil {
		jsonErr(w, errSaveConfig+err.Error(), 500)
		return
	}
	if repoChanged && body.TeamConfigRepo != "" {
		s.mu.Lock()
		s.teamStatus = team.Status{Configured: true, RepoURL: body.TeamConfigRepo}
		s.mu.Unlock()
		go s.syncTeamConfig()
	}
	jsonOK(w, map[string]any{"ok": true})
}

// handleSaveTimeFormat persists the chosen timestamp style and applies it
// immediately, so every subsequently rendered page and API response uses it.
func (s *Server) handleSaveTimeFormat(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Format string `json:"format"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonErr(w, errInvalidBody, 400)
		return
	}
	valid := false
	for _, f := range timefmt.Formats() {
		if f.ID == body.Format {
			valid = true
			break
		}
	}
	if !valid {
		jsonErr(w, "unknown time format", 400)
		return
	}
	s.mu.Lock()
	s.Config.TimeFormat = body.Format
	cfg := s.Config
	s.mu.Unlock()

	if err := devconfig.Save(s.RepoRoot, cfg); err != nil {
		jsonErr(w, errSaveConfig+err.Error(), 500)
		return
	}
	timefmt.SetFormat(body.Format)
	jsonOK(w, map[string]any{"ok": true, "format": body.Format})
}

// timeFormatID resolves a stored (possibly empty) format id to the concrete id
// the dashboard should show as selected.
func timeFormatID(stored string) string {
	if stored == "" {
		return timefmt.DefaultID
	}
	return stored
}

// ─── helpers ────────────────────────────────────────────────────────────────

func (s *Server) getTools() []tools.ToolStatus {
	s.mu.RLock()
	ts := s.allTools
	prefix := s.prefix
	s.mu.RUnlock()

	result := make([]tools.ToolStatus, 0, len(ts))
	for _, t := range ts {
		result = append(result, tools.GetStatus(s.applyMetaOverride(t), prefix, s.OS))
	}
	return result
}

func (s *Server) findTool(id string) (tools.Tool, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, t := range s.allTools {
		if t.ID == id {
			return t, true
		}
	}
	return tools.Tool{}, false
}

func (s *Server) currentPrefix() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.prefix
}

func (s *Server) installEnv(t tools.Tool) []string {
	return tools.BuildEnv(t, s.currentPrefix(), s.PrebuiltDir, s.OS)
}

func osLabel(goos string) string {
	switch goos {
	case "windows":
		return windowsLabel()
	case "darwin":
		if v := macOSVersion(); v != "" {
			return "macOS " + v
		}
		return "macOS"
	case "linux":
		if pretty := osReleaseField("PRETTY_NAME"); pretty != "" {
			return pretty
		}
		if name := osReleaseField("NAME"); name != "" {
			return name
		}
		return "Linux"
	default:
		return goos
	}
}

func windowsLabel() string {
	productName := "Windows"
	displayVersion := ""

	if out, err := exec.Command("reg", "query",
		`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`,
		"/v", "ProductName").Output(); err == nil {
		if parts := strings.SplitN(string(out), "REG_SZ", 2); len(parts) == 2 {
			productName = strings.TrimSpace(parts[1])
		}
	}
	if out, err := exec.Command("reg", "query",
		`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`,
		"/v", "DisplayVersion").Output(); err == nil {
		if parts := strings.SplitN(string(out), "REG_SZ", 2); len(parts) == 2 {
			displayVersion = strings.TrimSpace(parts[1])
		}
	}
	if displayVersion != "" {
		return productName + " " + displayVersion
	}
	return productName
}

func macOSVersion() string {
	out, err := exec.Command("sw_vers", "-productVersion").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// osIcon returns the logo filename (under /static/img) that best represents the
// running OS. On Linux it identifies the distribution from /etc/os-release,
// falling back to a related family via ID_LIKE and finally to a generic Tux.
func osIcon(goos string) string {
	switch goos {
	case "windows":
		return "windows.png"
	case "darwin":
		return "macos.svg"
	case "linux":
		id, idLike := linuxDistroID()
		if icon := distroIcon(id); icon != "" {
			return icon
		}
		for _, like := range strings.Fields(idLike) {
			if icon := distroIcon(like); icon != "" {
				return icon
			}
		}
		return "linux.png"
	default:
		return "linux.png"
	}
}

// distroIcon maps an /etc/os-release ID (or ID_LIKE token) to a logo filename.
// Returns "" when the id is unknown so the caller can fall back.
func distroIcon(id string) string {
	switch id {
	case "rhel", "redhat", "redhatenterpriseserver":
		return "rhel.svg"
	case "rocky":
		return "rocky.svg"
	case "almalinux", "alma":
		return "almalinux.svg"
	case "centos":
		return "centos.svg"
	case "fedora":
		return "fedora.svg"
	case "ubuntu":
		return "ubuntu.svg"
	case "debian":
		return "debian.svg"
	case "linuxmint", "mint":
		return "mint.svg"
	case "opensuse", "opensuse-leap", "opensuse-tumbleweed", "opensuse-microos":
		return "opensuse.svg"
	case "sles", "sles_sap", "sled", "suse":
		return "suse.svg"
	case "arch", "archlinux":
		return "arch.svg"
	case "alpine":
		return "alpine.svg"
	}
	return ""
}

func linuxDistroID() (id, idLike string) {
	return strings.ToLower(osReleaseField("ID")), strings.ToLower(osReleaseField("ID_LIKE"))
}

// osReleaseField reads a single field from /etc/os-release (falling back to the
// /usr/lib copy). Surrounding quotes are stripped.
func osReleaseField(key string) string {
	for _, p := range []string{"/etc/os-release", "/usr/lib/os-release"} {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			k, v, ok := strings.Cut(strings.TrimSpace(line), "=")
			if ok && k == key {
				return strings.Trim(strings.TrimSpace(v), `"'`)
			}
		}
	}
	return ""
}

func detectPrefix(currentOS string) string {
	if currentOS == "windows" {
		if la := winLocalAppData(); la != "" {
			return filepath.Join(la, devkitDirName)
		}
	}
	if _, err := os.Stat("/opt/airgap-cpp-devkit"); err == nil {
		return "/opt/airgap-cpp-devkit"
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share", devkitDirName)
}

func winLocalAppData() string {
	if la := os.Getenv("LOCALAPPDATA"); la != "" && len(la) > 1 && la[1] == ':' {
		return la
	}
	if up := os.Getenv("USERPROFILE"); up != "" && len(up) > 1 && up[1] == ':' {
		return filepath.Join(up, "AppData", "Local")
	}
	return ""
}

func prefixOverridePath(_ string) string {
	// Store outside the repo so it survives git operations and works when the
	// repo is mounted read-only.
	if cfgDir, err := os.UserConfigDir(); err == nil {
		return filepath.Join(cfgDir, devkitDirName, "prefix")
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, ".config", devkitDirName, "prefix")
	}
	return filepath.Join(os.TempDir(), ".devkit-prefix")
}

func readPrefixOverride(repoRoot string) string {
	data, err := os.ReadFile(prefixOverridePath(repoRoot))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func jsonErr(w http.ResponseWriter, msg string, code int) {
	w.Header().Set(headerContentType, mimeJSON)
	w.WriteHeader(code)
	fmt.Fprintf(w, `{"error":%q}`, msg)
}

func jsonOK(w http.ResponseWriter, v any) {
	w.Header().Set(headerContentType, mimeJSON)
	_ = json.NewEncoder(w).Encode(v)
}

func currentOSUsername() string {
	if u, err := user.Current(); err == nil && u.Username != "" {
		// On Windows this is often DOMAIN\username — strip the domain part.
		parts := strings.SplitN(u.Username, `\`, 2)
		return parts[len(parts)-1]
	}
	if name := os.Getenv("USER"); name != "" {
		return name
	}
	if name := os.Getenv("USERNAME"); name != "" {
		return name
	}
	h, _ := os.Hostname()
	if h != "" {
		return h
	}
	return "unknown"
}

// ─── route handlers ──────────────────────────────────────────────────────────

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	// /health is intentionally reachable without a token (liveness probes, load
	// balancers). In team-server mode that means anyone who can reach the port
	// hits it pre-authentication, so the version is disclosed only to a caller
	// that already holds the token — an unauthenticated probe gets liveness only.
	resp := map[string]string{"status": "ok"}
	if _, ok := s.identify(s.requestToken(r)); ok {
		resp["version"] = AppVersion
	}
	jsonOK(w, resp)
}

// detectPrivilege reports "admin" when the process appears to have
// administrator/root rights, else "user". On Windows it probes writability of
// Program Files; on Unix it checks for uid 0.
func detectPrivilege() string {
	if runtime.GOOS == "windows" {
		if _, err := os.Stat(`C:\Program Files`); err != nil {
			return "user"
		}
		f, err := os.CreateTemp(`C:\Program Files`, ".devkit-priv-*")
		if err != nil {
			return "user"
		}
		f.Close()
		os.Remove(f.Name())
		return "admin"
	}
	if os.Getuid() == 0 {
		return "admin"
	}
	return "user"
}

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	ts := s.getTools()

	categories := map[string][]tools.ToolStatus{}
	var bundles []tools.ToolStatus
	for _, t := range ts {
		if t.Category == "Bundles" {
			bundles = append(bundles, t)
		} else {
			categories[t.Category] = append(categories[t.Category], t)
		}
	}

	installed := 0
	for _, t := range ts {
		if t.Installed {
			installed++
		}
	}

	hostname, _ := os.Hostname()
	osUsername := currentOSUsername()
	privilege := detectPrivilege()

	data := map[string]any{
		"Config":         s.Config,
		"Tools":          ts,
		"Categories":     categories,
		"Bundles":        bundles,
		"Profiles":       s.profiles,
		"InstalledCount": installed,
		"TotalCount":     len(ts),
		"OS":             s.OS,
		"OSLabel":        osLabel(s.OS),
		"OSIcon":         osIcon(s.OS),
		"Prefix":         s.currentPrefix(),
		"Hostname":       hostname,
		"OSUsername":     osUsername,
		"Privilege":      privilege,
		"Year":           time.Now().Year(),
		"AppVersion":     AppVersion,
		"TimeFormats":    timefmt.Formats(),
		"TimeFormat":     timeFormatID(s.Config.TimeFormat),
	}

	if err := renderTemplate(s.webFS, "dashboard.html", w, r, data); err != nil {
		http.Error(w, "template error: "+err.Error(), 500)
	}
}

func (s *Server) handleLogs(w http.ResponseWriter, r *http.Request) {
	data := map[string]any{
		"Config": s.Config,
		"OS":     s.OS,
	}
	if err := renderTemplate(s.webFS, "logs.html", w, r, data); err != nil {
		http.Error(w, "template error: "+err.Error(), 500)
	}
}

func (s *Server) handleAPITools(w http.ResponseWriter, r *http.Request) {
	jsonOK(w, s.getTools())
}

func (s *Server) handleAPITool(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}
	jsonOK(w, tools.GetStatus(s.applyMetaOverride(t), s.currentPrefix(), s.OS))
}

func (s *Server) handleGetPrefix(w http.ResponseWriter, r *http.Request) {
	jsonOK(w, map[string]string{"prefix": s.currentPrefix()})
}

func (s *Server) handleSetPrefix(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Prefix string `json:"prefix"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Prefix == "" {
		jsonErr(w, "prefix cannot be empty", 400)
		return
	}
	if !filepath.IsAbs(body.Prefix) || filepath.Clean(body.Prefix) != body.Prefix {
		jsonErr(w, "prefix must be an absolute, clean path", 400)
		return
	}
	p := prefixOverridePath(s.RepoRoot)
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	if err := os.WriteFile(p, []byte(body.Prefix), 0o600); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	s.mu.Lock()
	s.prefix = body.Prefix
	s.mu.Unlock()
	jsonOK(w, map[string]any{"prefix": body.Prefix, "ok": true})
}

func (s *Server) handleResetPrefix(w http.ResponseWriter, r *http.Request) {
	_ = os.Remove(prefixOverridePath(s.RepoRoot))
	p := detectPrefix(s.OS)
	s.mu.Lock()
	s.prefix = p
	s.mu.Unlock()
	jsonOK(w, map[string]any{"prefix": p, "ok": true})
}

func (s *Server) handleOpenPrefix(w http.ResponseWriter, r *http.Request) {
	prefix := s.currentPrefix()

	// Ensure the target directory exists; create it if needed so the explorer has somewhere to go.
	_ = os.MkdirAll(prefix, 0o755)

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		// Walk up to the deepest path that actually exists (in case subdirs are missing).
		p := filepath.FromSlash(prefix)
		for {
			if _, err := os.Stat(p); err == nil {
				break
			}
			parent := filepath.Dir(p)
			if parent == p {
				break
			}
			p = parent
		}
		// "cmd /c start" is the most reliable way to open Explorer from a Go process on Windows.
		cmd = exec.Command("cmd", "/c", "start", "", p)
	case "darwin":
		cmd = exec.Command("open", prefix)
	default:
		cmd = exec.Command("xdg-open", prefix)
	}
	_ = cmd.Start()
	jsonOK(w, map[string]string{"ok": "true"})
}

func (s *Server) handleExport(w http.ResponseWriter, r *http.Request) {
	ts := s.getTools()
	var ids []string
	for _, t := range ts {
		if t.Installed {
			ids = append(ids, t.ID)
		}
	}
	s.mu.RLock()
	profs := make(map[string]export.ProfileExport, len(s.profiles))
	for id, p := range s.profiles {
		profs[id] = export.ProfileExport{
			ID: p.ID, Name: p.Name, Description: p.Description,
			ToolIDs: p.ToolIDs, Color: p.Color,
		}
	}
	s.mu.RUnlock()

	tc := export.Build(
		s.Config.TeamName, s.Config.OrgName, s.Config.DevkitName,
		s.Config.DefaultProfile, ids, s.currentPrefix(), profs,
	)
	data, err := export.Marshal(tc)
	if err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	filename := "team-config.json"
	if s.Config.TeamName != "" {
		filename = strings.ReplaceAll(strings.ToLower(s.Config.TeamName), " ", "-") + "-config.json"
	}
	w.Header().Set(headerContentType, mimeJSON)
	w.Header().Set("Content-Disposition", "attachment; filename="+filename)
	w.Write(data)
}

func (s *Server) handleImport(w http.ResponseWriter, r *http.Request) {
	var tc export.TeamConfig
	if err := json.NewDecoder(r.Body).Decode(&tc); err != nil {
		jsonErr(w, "invalid JSON: "+err.Error(), 400)
		return
	}
	// Validate all tool IDs exist
	s.mu.RLock()
	validIDs := map[string]bool{}
	for _, t := range s.allTools {
		validIDs[t.ID] = true
	}
	s.mu.RUnlock()

	var bad []string
	for _, id := range tc.ToolIDs {
		if !validIDs[id] {
			bad = append(bad, id)
		}
	}
	if len(bad) > 0 {
		jsonErr(w, "unknown tool IDs: "+strings.Join(bad, ", "), 400)
		return
	}
	if tc.Prefix != "" {
		if !filepath.IsAbs(tc.Prefix) || filepath.Clean(tc.Prefix) != tc.Prefix {
			jsonErr(w, "imported prefix must be an absolute, clean path", 400)
			return
		}
		pp := prefixOverridePath(s.RepoRoot)
		_ = os.MkdirAll(filepath.Dir(pp), 0o700)
		_ = os.WriteFile(pp, []byte(tc.Prefix), 0o600)
		s.mu.Lock()
		s.prefix = tc.Prefix
		s.mu.Unlock()
	}
	jsonOK(w, map[string]any{"ok": true, "tool_ids": tc.ToolIDs, "profile": tc.Profile})
}

func (s *Server) handleInstall(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}

	sse, ok2 := newSSE(w)
	if !ok2 {
		http.Error(w, "streaming not supported", 500)
		return
	}

	// Save full install output to a timestamped log file
	logDir := filepath.Join(s.RepoRoot, "devkit-logs", strings.ReplaceAll(t.ID, "/", "_"))
	_ = os.MkdirAll(logDir, 0o750)
	logFile := filepath.Join(logDir, time.Now().UTC().Format("20060102-150405")+".log")
	ssePipe := newPipe(sse)
	var pw io.Writer = ssePipe
	if f, err := os.Create(logFile); err == nil {
		pw = io.MultiWriter(ssePipe, f)
		defer f.Close()
	}

	env := s.installEnv(t)
	installArgs := t.InstallArgs(r.URL.Query().Get("variant"))
	rc := tools.RunInstall(s.Bash, s.RepoRoot, t, installArgs, env, pw)
	finalMsg := "✓ Installation complete"
	doneStatus := "success"
	if rc != 0 {
		finalMsg = fmt.Sprintf("✗ Installation failed (exit %d)", rc)
		doneStatus = "failed"
	}
	sse.Send(finalMsg)
	// Also append final line to log file
	if f, err := os.OpenFile(logFile, os.O_APPEND|os.O_WRONLY, 0o600); err == nil {
		fmt.Fprintln(f, finalMsg)
		if cerr := f.Close(); cerr != nil {
			sse.Send("WARNING: could not finalize install log: " + cerr.Error())
		}
	}

	// Post-install verification: run check_cmd to confirm the binary is reachable.
	if rc == 0 {
		s.verifyAfterInstall(sse, t)
	}

	sse.Done(doneStatus)
}

// verifyAfterInstall runs the tool's check command (if any) and streams a
// human-readable pass/fail summary over the SSE channel.
func (s *Server) verifyAfterInstall(sse *sseWriter, t tools.Tool) {
	if t.CheckBinary == "" && t.ResolvedCheckCmd(runtime.GOOS) == "" {
		return
	}
	sse.Send("── Verifying install ──")
	res := s.runCheckCmd(t)
	firstLine := strings.SplitN(strings.TrimSpace(res.Output), "\n", 2)[0]
	if res.OK {
		if firstLine != "" {
			sse.Send("✓ " + firstLine)
		} else {
			sse.Send("✓ Check passed")
		}
		return
	}
	if firstLine != "" {
		sse.Send("⚠ Check after install: " + firstLine)
	}
	if res.Error != "" {
		sse.Send("  " + res.Error)
	}
	sse.Send("  Binary may not be on PATH until you restart your shell.")
}

func (s *Server) handleUninstall(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}

	w.Header().Set(headerContentType, mimeJSON)
	clean := strings.ReplaceAll(t.ReceiptName, "/", string(os.PathSeparator))
	installDir := filepath.Join(s.currentPrefix(), clean)
	if _, err := os.Stat(installDir); os.IsNotExist(err) {
		jsonOK(w, map[string]any{"ok": true, "message": "Nothing to remove — directory does not exist."})
		return
	}
	if err := os.RemoveAll(installDir); err != nil {
		jsonOK(w, map[string]any{"ok": false, "error": err.Error()})
		return
	}

	msg := "✓ Removed " + installDir
	// Scrub any shell-rc lines that source this install directory so stale PATH
	// entries don't linger after the files are gone.
	if cleaned := cleanupShellRc(installDir); cleaned != "" {
		msg += "\n" + cleaned
	}
	jsonOK(w, map[string]any{"ok": true, "message": msg})
}

// cleanupShellRc removes lines referencing installDir from common shell rc files.
// Returns a human-readable summary of what was removed, or "" if nothing changed.
func cleanupShellRc(installDir string) string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	// Normalise to forward slashes for string matching (handles Windows paths too).
	needle := filepath.ToSlash(installDir)
	rcFiles := []string{".bashrc", ".bash_profile", ".profile", ".zshrc"}
	var msgs []string
	for _, name := range rcFiles {
		path := filepath.Join(home, name)
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		lines := strings.Split(string(raw), "\n")
		var kept []string
		removed := 0
		for _, line := range lines {
			if strings.Contains(filepath.ToSlash(line), needle) {
				removed++
			} else {
				kept = append(kept, line)
			}
		}
		if removed > 0 {
			_ = os.WriteFile(path, []byte(strings.Join(kept, "\n")), 0o600)
			msgs = append(msgs, fmt.Sprintf("Removed %d PATH line(s) from ~/%s", removed, name))
		}
	}
	return strings.Join(msgs, "\n")
}

func (s *Server) handleInstallProfile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	profile, ok := s.profiles[id]
	if !ok {
		jsonErr(w, "profile not found", 404)
		return
	}

	wantIDs := map[string]bool{}
	for _, pid := range profile.ToolIDs {
		wantIDs[pid] = true
	}

	s.mu.RLock()
	var toInstall []tools.Tool
	for _, t := range s.allTools {
		if wantIDs[t.ID] && (t.Platform == "both" || t.Platform == s.OS) {
			toInstall = append(toInstall, t)
		}
	}
	s.mu.RUnlock()

	sse, ok2 := newSSE(w)
	if !ok2 {
		http.Error(w, "streaming not supported", 500)
		return
	}

	sse.Send(fmt.Sprintf("Installing profile: %s (%d tools)", profile.Name, len(toInstall)))
	for _, t := range toInstall {
		sse.Send("")
		sse.Send(fmt.Sprintf("── %s %s", t.Name, t.Version))
		pw := newPipe(sse)
		env := s.installEnv(t)
		// Profile installs use each tool's default variant (e.g. gRPC v143).
		rc := tools.RunInstall(s.Bash, s.RepoRoot, t, t.InstallArgs(""), env, pw)
		if rc == 0 {
			sse.Send(fmt.Sprintf("✓ %s done", t.Name))
		} else {
			sse.Send(fmt.Sprintf("✗ %s failed (exit %d)", t.Name, rc))
		}
	}
	sse.Send("")
	sse.Send("✓ Profile installation complete")
	sse.Done("success")
}

// checkEnv builds a copy of os.Environ() with the tool's install directory
// prepended to PATH, so devkit-installed binaries are found even when the
// server process was launched before the tool was added to the system PATH.
// Common nested locations (bin/, usr/bin/, usr/local/bin/) are all included
// to cover tools that unpack an RPM payload (e.g. gcc → usr/bin/gcc).
func (s *Server) checkEnv(t tools.Tool) []string {
	receipt := tools.GetReceipt(s.currentPrefix(), t.ReceiptName)
	if !receipt.Exists {
		return nil
	}
	instDir := receipt.InstallPath
	if instDir == "" {
		instDir = filepath.Join(s.currentPrefix(), t.ReceiptName)
	}
	sep := string(os.PathListSeparator)
	ps := string(os.PathSeparator)
	extra := strings.Join([]string{
		instDir,
		instDir + ps + "bin",
		instDir + ps + "usr" + ps + "bin",
		instDir + ps + "usr" + ps + "local" + ps + "bin",
	}, sep)
	env := os.Environ()
	for i, e := range env {
		if strings.HasPrefix(strings.ToUpper(e), "PATH=") {
			env[i] = e[:5] + extra + sep + e[5:]
			return env
		}
	}
	return append(env, "PATH="+extra)
}

// resolveInExtendedPath looks up binary in the PATH value found inside env,
// returning the full path if found or the original name if not.
// This is necessary because exec.Command resolves names using the server
// process's own PATH, not the child's modified PATH set via cmd.Env.
// probeExecutable looks for binary (and, on Windows, its .exe/.cmd/.bat
// variants) inside dir. Returns the full path if found, or "" otherwise.
func probeExecutable(dir, binary string) string {
	candidate := filepath.Join(dir, binary)
	if fi, err := os.Stat(candidate); err == nil && !fi.IsDir() {
		return candidate
	}
	if runtime.GOOS == "windows" {
		for _, ext := range []string{".exe", ".cmd", ".bat"} {
			c := candidate + ext
			if fi, err := os.Stat(c); err == nil && !fi.IsDir() {
				return c
			}
		}
	}
	return ""
}

func resolveInExtendedPath(binary string, env []string) string {
	for _, e := range env {
		if !strings.HasPrefix(strings.ToUpper(e), "PATH=") {
			continue
		}
		for _, dir := range strings.Split(e[5:], string(os.PathListSeparator)) {
			if found := probeExecutable(dir, binary); found != "" {
				return found
			}
		}
		break
	}
	return binary
}

// runCheckResult holds the outcome of a single tool check.
type runCheckResult struct {
	OK       bool
	Output   string
	Error    string
	CheckCmd string // the command that was actually run
}

func (s *Server) runCheckCmd(t tools.Tool) runCheckResult {
	if t.Source == "user" {
		return runCheckResult{
			OK:       false,
			Error:    "check_cmd execution is disabled for user-uploaded packages",
			CheckCmd: "(blocked — user source)",
		}
	}

	checkCmd := t.ResolvedCheckCmd(runtime.GOOS)

	if t.CheckBinary != "" {
		args := t.CheckArgs
		if len(args) == 0 {
			args = []string{"--version"}
		}
		env := s.checkEnv(t)
		binPath := resolveInExtendedPath(t.CheckBinary, env)
		cmd := exec.Command(binPath, args...)
		if env != nil {
			cmd.Env = env
		}
		out, err := cmd.CombinedOutput()
		if err != nil {
			return runCheckResult{OK: false, Output: string(out), Error: err.Error(), CheckCmd: binPath + " " + strings.Join(args, " ")}
		}
		return runCheckResult{OK: true, Output: string(out), CheckCmd: binPath + " " + strings.Join(args, " ")}
	}

	if checkCmd == "" {
		return runCheckResult{OK: false, Error: "no check_cmd configured", CheckCmd: noneLabel}
	}

	parts := strings.Fields(checkCmd)
	if len(parts) == 0 {
		return runCheckResult{OK: false, Error: "no check_cmd configured", CheckCmd: noneLabel}
	}
	env := s.checkEnv(t)
	binPath := resolveInExtendedPath(parts[0], env)
	cmd := exec.Command(binPath, parts[1:]...)
	if env != nil {
		cmd.Env = env
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return runCheckResult{OK: false, Output: string(out), Error: err.Error(), CheckCmd: checkCmd}
	}
	return runCheckResult{OK: true, Output: string(out), CheckCmd: checkCmd}
}

// writeReceiptFallback responds with the tool's install receipt details when no
// check command is configured, or an explanatory error if no receipt exists.
func (s *Server) writeReceiptFallback(w http.ResponseWriter, t tools.Tool) {
	receipt := tools.GetReceipt(s.currentPrefix(), t.ReceiptName)
	if !receipt.Exists {
		jsonOK(w, map[string]any{
			"ok":        false,
			"error":     "No check_cmd defined for this tool and no receipt file found.\nAdd a \"check_cmd\" field to its devkit.json to enable live version probing.",
			"check_cmd": noneLabel,
		})
		return
	}
	lines := []string{"(no check_cmd defined — showing install receipt)", ""}
	if receipt.Version != "" {
		lines = append(lines, "Version:      "+receipt.Version)
	}
	if receipt.Status != "" {
		lines = append(lines, "Status:       "+receipt.Status)
	}
	if receipt.Date != "" {
		lines = append(lines, "Installed on: "+receipt.Date)
	}
	if receipt.InstallPath != "" {
		lines = append(lines, "Install path: "+receipt.InstallPath)
	}
	jsonOK(w, map[string]any{"ok": true, "output": strings.Join(lines, "\n"), "check_cmd": "(receipt file)"})
}

func (s *Server) handleCheck(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}

	// No check configured: fall back to reading the install receipt.
	if t.CheckBinary == "" && t.ResolvedCheckCmd(runtime.GOOS) == "" {
		s.writeReceiptFallback(w, t)
		return
	}

	res := s.runCheckCmd(t)
	jsonOK(w, map[string]any{
		"ok":        res.OK,
		"output":    res.Output,
		"error":     res.Error,
		"check_cmd": res.CheckCmd,
	})
}

func (s *Server) handleToolLog(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}
	prefix := s.currentPrefix()
	clean := strings.ReplaceAll(t.ReceiptName, "/", string(os.PathSeparator))
	toolDir := filepath.Join(prefix, clean)

	for _, name := range []string{"INSTALL_LOG.txt", "INSTALL_RECEIPT.txt"} {
		p := filepath.Join(toolDir, name)
		b, err := os.ReadFile(p)
		if err == nil {
			jsonOK(w, map[string]any{
				"ok":       true,
				"log":      string(b),
				"filename": name,
				"path":     p,
			})
			return
		}
	}
	jsonOK(w, map[string]any{"ok": false, "error": "No install log found for this tool."})
}

func (s *Server) logDirForID(id string) (string, bool) {
	logsRoot := filepath.Clean(filepath.Join(s.RepoRoot, "devkit-logs"))
	dir := filepath.Join(logsRoot, strings.ReplaceAll(id, "/", "_"))
	// Ensure the resolved path stays inside devkit-logs/.
	if !strings.HasPrefix(dir, logsRoot+string(os.PathSeparator)) {
		return "", false
	}
	return dir, true
}

func (s *Server) handleToolLogList(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	logDir, ok := s.logDirForID(id)
	if !ok {
		jsonErr(w, "invalid tool id", 400)
		return
	}
	entries, err := os.ReadDir(logDir)
	if err != nil {
		jsonOK(w, map[string]any{"ok": true, "logs": []any{}})
		return
	}
	type logEntry struct {
		File string `json:"file"`
		Size int64  `json:"size"`
		Time string `json:"time"`
	}
	var logs []logEntry
	for i := len(entries) - 1; i >= 0; i-- { // newest first
		e := entries[i]
		if e.IsDir() || filepath.Ext(e.Name()) != ".log" {
			continue
		}
		info, _ := e.Info()
		sz := int64(0)
		if info != nil {
			sz = info.Size()
		}
		// Parse timestamp from filename 20060102-150405.log
		ts := strings.TrimSuffix(e.Name(), ".log")
		if t, err := time.ParseInLocation("20060102-150405", ts, time.UTC); err == nil {
			ts = timefmt.Display(t)
		}
		logs = append(logs, logEntry{File: e.Name(), Size: sz, Time: ts})
	}
	jsonOK(w, map[string]any{"ok": true, "logs": logs})
}

func (s *Server) handleToolLogFile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	file := chi.URLParam(r, "file")
	if file == "" || file == "." || file == ".." {
		jsonErr(w, "invalid filename", 400)
		return
	}
	// Log filenames are timestamps like 20260802-141530.log, so only digits,
	// dashes and dots are ever legitimate. Restricting to that set keeps the
	// value a single leaf name: no separator can appear, so the join below
	// always resolves inside logDir.
	for _, c := range file {
		if !((c >= '0' && c <= '9') || c == '-' || c == '.') {
			jsonErr(w, "invalid filename", 400)
			return
		}
	}
	logDir, ok := s.logDirForID(id)
	if !ok {
		jsonErr(w, "invalid tool id", 400)
		return
	}
	b, err := os.ReadFile(filepath.Join(logDir, file))
	if err != nil {
		jsonErr(w, "log not found", 404)
		return
	}
	jsonOK(w, map[string]any{"ok": true, "log": string(b), "filename": file})
}

// handleHealthTools runs every installed tool's check command in parallel and
// returns a pass/fail summary — used by the "Validate All" UI feature.
func (s *Server) handleHealthTools(w http.ResponseWriter, r *http.Request) {
	type HealthResult struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		Category   string `json:"category"`
		OK         bool   `json:"ok"`
		Output     string `json:"output"`
		Error      string `json:"error,omitempty"`
		CheckCmd   string `json:"check_cmd"`
		DurationMS int64  `json:"duration_ms"`
		NoCheck    bool   `json:"no_check,omitempty"`
	}

	allTools := s.getTools()
	prefix := s.currentPrefix()

	type workItem struct {
		t      tools.Tool
		status tools.ToolStatus
	}
	var work []workItem
	for _, ts := range allTools {
		if ts.Installed {
			work = append(work, workItem{t: ts.Tool, status: ts})
		}
	}
	_ = prefix // held for future per-check override; runCheckCmd uses s.currentPrefix()

	results := make([]HealthResult, len(work))
	var wg sync.WaitGroup
	for i, w2 := range work {
		wg.Add(1)
		go func(idx int, t tools.Tool) {
			defer wg.Done()
			hr := HealthResult{
				ID:       t.ID,
				Name:     t.Name,
				Category: t.Category,
			}
			hasCheck := t.CheckBinary != "" || t.ResolvedCheckCmd(runtime.GOOS) != ""
			if !hasCheck {
				hr.OK = true
				hr.NoCheck = true
				hr.CheckCmd = noneLabel
				results[idx] = hr
				return
			}
			start := time.Now()
			res := s.runCheckCmd(t)
			hr.OK = res.OK
			hr.Output = strings.TrimSpace(res.Output)
			hr.Error = res.Error
			hr.CheckCmd = res.CheckCmd
			hr.DurationMS = time.Since(start).Milliseconds()
			results[idx] = hr
		}(i, w2.t)
	}
	wg.Wait()

	passed, failed, noCheck := 0, 0, 0
	for _, r2 := range results {
		switch {
		case r2.NoCheck:
			noCheck++
		case r2.OK:
			passed++
		default:
			failed++
		}
	}
	jsonOK(w, map[string]any{
		"results": results,
		"summary": map[string]int{
			"total":    len(results),
			"passed":   passed,
			"failed":   failed,
			"no_check": noCheck,
		},
	})
}

func (s *Server) handleShutdown(w http.ResponseWriter, r *http.Request) {
	// Only allow shutdown from loopback — reject remote clients even when
	// the server is bound to 0.0.0.0.
	host, _, _ := strings.Cut(r.RemoteAddr, ":")
	if host != "127.0.0.1" && host != "::1" {
		jsonErr(w, "forbidden", 403)
		return
	}
	jsonOK(w, map[string]string{"status": "shutting down"})
	go func() {
		time.Sleep(200 * time.Millisecond)
		os.Exit(0)
	}()
}

// ─── Package upload ──────────────────────────────────────────────────────────
//
// The upload transport (resumable chunked upload via tus, plus the localhost
// import-from-disk path) lives in upload.go. This file keeps the shared
// archive-handling primitives — slug/name sanitisation, streaming extraction,
// and manifest generation — that both intake paths converge on.

var reSlug = regexp.MustCompile(`[^a-z0-9\-]`)

var reUnsafeName = regexp.MustCompile(`['"\\<>]`)

func sanitizeDisplayName(s string) string {
	return strings.TrimSpace(reUnsafeName.ReplaceAllString(s, ""))
}

func slugify(name string) string {
	s := strings.ToLower(strings.TrimSpace(name))
	s = reSlug.ReplaceAllString(s, "-")
	s = regexp.MustCompile(`-+`).ReplaceAllString(s, "-")
	return strings.Trim(s, "-")
}

// extractZipTo unpacks the archive into destDir, guarding against path
// traversal. maxEntry caps each individual file. Returns an HTTP status and
// message on a fatal error (errMsg == "" on success); unreadable individual
// entries are skipped.
func extractZipTo(zr *zip.Reader, destDir string, maxEntry int64) (code int, errMsg string) {
	safeRoot := filepath.Clean(destDir) + string(os.PathSeparator)
	for _, f := range zr.File {
		target := filepath.Join(destDir, filepath.Clean(f.Name))
		rel, err := filepath.Rel(safeRoot, target+string(os.PathSeparator))
		if err != nil || strings.HasPrefix(rel, "..") || !strings.HasPrefix(target, safeRoot) {
			continue
		}
		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(target, 0o750)
			continue
		}
		if code, errMsg := extractZipEntry(f, target, maxEntry); errMsg != "" {
			return code, errMsg
		}
	}
	return 0, ""
}

// extractZipEntry writes a single zip file entry to target, capping the size at
// maxEntry. Unreadable entries are skipped (errMsg ""); a size overrun is fatal.
func extractZipEntry(f *zip.File, target string, maxEntry int64) (code int, errMsg string) {
	_ = os.MkdirAll(filepath.Dir(target), 0o750)
	rc, err := f.Open()
	if err != nil {
		return 0, ""
	}
	defer rc.Close()
	out, err := os.Create(target)
	if err != nil {
		return 0, ""
	}
	n, cpErr := io.Copy(out, io.LimitReader(rc, maxEntry))
	out.Close()
	if cpErr != nil || n >= maxEntry {
		os.Remove(target)
		return 400, "zip entry exceeds maximum allowed size"
	}
	return 0, ""
}

// ensurePackageManifest guarantees destDir holds a valid devkit.json. A
// well-formed manifest bundled in the archive is left untouched; a missing or
// unparseable one is replaced with a generated default so the package always
// registers even when its bundled manifest is malformed.
func ensurePackageManifest(devkitJSON, toolID, base, uploadedBy, uploadedAt string) {
	if raw, err := os.ReadFile(devkitJSON); err == nil {
		var probe map[string]any
		if json.Unmarshal(raw, &probe) == nil {
			return // valid manifest provided — keep it
		}
	}
	manifest := map[string]any{
		"id":           toolID,
		"name":         base,
		"version":      "1.0.0",
		"category":     "Developer Tools",
		"platform":     "both",
		"description":  "User-uploaded package: " + base,
		"setup":        setupScriptName,
		"receipt_name": toolID,
		"source":       "user",
		"uploaded_by":  uploadedBy,
		"uploaded_at":  uploadedAt,
	}
	mjson, _ := json.MarshalIndent(manifest, "", "  ")
	_ = os.WriteFile(devkitJSON, mjson, 0o600)
}

// ensurePackageSetup guarantees the installer referenced by the manifest exists.
// A package that ships its own setup script is left as-is; when the referenced
// script is missing, a robust default is generated. Generation is independent
// of manifest generation so a package that bundles one file but not the other
// still ends up with both.
func ensurePackageSetup(destDir, devkitJSON, toolID, base string) {
	setupName := setupScriptName
	if raw, err := os.ReadFile(devkitJSON); err == nil {
		var meta map[string]any
		if json.Unmarshal(raw, &meta) == nil {
			if s, ok := meta["setup"].(string); ok && strings.TrimSpace(s) != "" {
				setupName = s
			}
		}
	}
	// Keep the resolved script inside the package directory.
	target := filepath.Join(destDir, filepath.Clean(setupName))
	safeRoot := filepath.Clean(destDir) + string(os.PathSeparator)
	if !strings.HasPrefix(target, safeRoot) {
		target = filepath.Join(destDir, setupScriptName)
	}
	if _, err := os.Stat(target); err == nil {
		return // installer provided by the package
	}
	_ = os.MkdirAll(filepath.Dir(target), 0o750)
	_ = os.WriteFile(target, []byte(generatedSetupScript(toolID, base)), 0o755)
}

// generatedSetupScript builds the fallback installer for a user-uploaded
// package. It installs into a per-user location and degrades gracefully so it
// never requires administrator rights: it honours the prefix the devkit passes
// in, falls back to a user directory when that prefix is unset, and falls back
// again to $HOME if the chosen directory cannot be created (e.g. an admin-owned
// prefix the user cannot write to).
func generatedSetupScript(toolID, base string) string {
	return fmt.Sprintf(`#!/usr/bin/env bash
# Auto-generated installer for the user-uploaded package %q.
# Installs per-user; no administrator rights required.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) Honour the prefix the devkit provides; otherwise pick a per-user default.
TOOL_DIR="${INSTALL_PREFIX:-}"
if [ -z "$TOOL_DIR" ]; then
  BASE="${LOCALAPPDATA:-$HOME/.local/share}"
  BASE="${BASE//\\//}"
  TOOL_DIR="$BASE/airgap-cpp-devkit/%s"
fi

# 2) If that location cannot be created, fall back to the user's home so the
#    install still succeeds without elevation.
if ! mkdir -p "$TOOL_DIR" 2>/dev/null; then
  TOOL_DIR="$HOME/.local/share/airgap-cpp-devkit/%s"
  mkdir -p "$TOOL_DIR"
fi

# 3) Copy the package payload, skipping generated metadata and this installer.
shopt -s dotglob nullglob
for entry in "$SCRIPT_DIR"/*; do
  case "$(basename "$entry")" in
    setup.sh|devkit.json|INSTALL_LOG.txt|INSTALL_RECEIPT.txt) continue ;;
  esac
  cp -r "$entry" "$TOOL_DIR/" 2>/dev/null || true
done
shopt -u dotglob nullglob

{
  echo "Status: success"
  echo "Version: 1.0.0"
  echo "Installed-At: $(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ)"
  echo "Install-Path: $TOOL_DIR"
} > "$TOOL_DIR/INSTALL_LOG.txt"

echo "✓ %s installed to $TOOL_DIR"
`, base, toolID, toolID, base)
}

// sanitizePackageManifest re-reads the devkit.json (auto-generated or
// user-provided), enforces the slug-safe id, strips JS-unsafe characters from
// display strings, and stamps upload metadata.
func sanitizePackageManifest(devkitJSON, toolID, uploadedBy, uploadedAt string) {
	raw, err := os.ReadFile(devkitJSON)
	if err != nil {
		return
	}
	var meta map[string]any
	if json.Unmarshal(raw, &meta) != nil {
		return
	}
	meta["id"] = toolID
	meta["source"] = "user"
	meta["uploaded_by"] = uploadedBy
	meta["uploaded_at"] = uploadedAt
	if n, ok := meta["name"].(string); ok {
		meta["name"] = sanitizeDisplayName(n)
	}
	if pkgs, ok := meta["packages"].([]any); ok {
		sanitizePackageItems(pkgs)
	}
	if mjson, err := json.MarshalIndent(meta, "", "  "); err == nil {
		_ = os.WriteFile(devkitJSON, mjson, 0o600)
	}
}

// sanitizePackageItems strips JS-unsafe characters from each package item's
// name and description in place.
func sanitizePackageItems(pkgs []any) {
	for _, p := range pkgs {
		pm, ok := p.(map[string]any)
		if !ok {
			continue
		}
		if n, ok := pm["name"].(string); ok {
			pm["name"] = sanitizeDisplayName(n)
		}
		if d, ok := pm["description"].(string); ok {
			pm["description"] = sanitizeDisplayName(d)
		}
	}
}

func (s *Server) handlePackageDelete(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	userPkgRoot := filepath.Clean(filepath.Join(s.RepoRoot, userPackagesDir))
	destDir := filepath.Join(userPkgRoot, id)
	if !strings.HasPrefix(destDir, userPkgRoot+string(os.PathSeparator)) {
		jsonErr(w, "invalid package id", 400)
		return
	}
	if _, err := os.Stat(destDir); os.IsNotExist(err) {
		jsonErr(w, "package not found", 404)
		return
	}
	if err := os.RemoveAll(destDir); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	s.mu.Lock()
	if loaded, err := tools.Load(s.RepoRoot); err == nil {
		s.allTools = loaded
	}
	s.mu.Unlock()
	jsonOK(w, map[string]any{"ok": true, "id": id})
}

// ── Setup (first-launch) ─────────────────────────────────────────────────────

func (s *Server) handleSetup(w http.ResponseWriter, r *http.Request) {
	if s.Config.SetupComplete {
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}
	type setupData struct {
		Config  devconfig.Config
		OSIcon  string
		OSLabel string
	}
	data := setupData{
		Config:  s.Config,
		OSIcon:  osIcon(s.OS),
		OSLabel: osLabel(s.OS),
	}
	if err := renderTemplate(s.webFS, "setup.html", w, r, data); err != nil {
		http.Error(w, err.Error(), 500)
	}
}

func (s *Server) handleSaveSetup(w http.ResponseWriter, r *http.Request) {
	var body struct {
		TeamName       string `json:"team_name"`
		OrgName        string `json:"org_name"`
		DevkitName     string `json:"devkit_name"`
		TeamConfigRepo string `json:"team_config_repo"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonErr(w, errInvalidBody, 400)
		return
	}
	if err := validateRepoURL(body.TeamConfigRepo); err != nil {
		jsonErr(w, err.Error(), 400)
		return
	}

	s.mu.Lock()
	if body.TeamName != "" {
		s.Config.TeamName = body.TeamName
	}
	s.Config.OrgName = body.OrgName
	if body.DevkitName != "" {
		s.Config.DevkitName = body.DevkitName
	}
	s.Config.TeamConfigRepo = body.TeamConfigRepo
	s.Config.SetupComplete = true
	cfg := s.Config
	s.mu.Unlock()

	if err := devconfig.Save(s.RepoRoot, cfg); err != nil {
		jsonErr(w, errSaveConfig+err.Error(), 500)
		return
	}

	if body.TeamConfigRepo != "" {
		s.mu.Lock()
		s.teamStatus = team.Status{Configured: true, RepoURL: body.TeamConfigRepo}
		s.mu.Unlock()
		go s.syncTeamConfig()
	}

	jsonOK(w, map[string]any{"ok": true, "redirect": "/"})
}

var reGitSSH = regexp.MustCompile(`^[a-zA-Z0-9._\-]+@[a-zA-Z0-9._\-]+:[a-zA-Z0-9._\-/~][a-zA-Z0-9._\-/~]*$`)

func validateRepoURL(u string) error {
	if u == "" {
		return nil
	}
	for _, prefix := range []string{"https://", "ssh://"} {
		if strings.HasPrefix(u, prefix) {
			return nil
		}
	}
	if reGitSSH.MatchString(u) {
		return nil
	}
	return fmt.Errorf("unsupported git URL scheme — use an encrypted transport: https://, ssh://, or git@host:path")
}

// ── Team config repo ─────────────────────────────────────────────────────────

func (s *Server) syncTeamConfig() {
	s.mu.RLock()
	repoURL := s.Config.TeamConfigRepo
	s.mu.RUnlock()

	if repoURL == "" {
		return
	}

	// Cloning the team-config repo reaches the network, so honor the same egress
	// switch that gates update downloads.
	s.mu.RLock()
	allowEgress := s.Config.AllowEgress
	s.mu.RUnlock()
	if !allowEgress {
		s.mu.Lock()
		s.teamStatus.Configured = true
		s.teamStatus.RepoURL = repoURL
		s.teamStatus.LastSync = time.Now().UTC()
		s.teamStatus.Error = "egress disabled — set allow_egress: true in devkit.config.json to sync team config"
		s.mu.Unlock()
		return
	}

	destDir := team.Dir(s.RepoRoot)
	commit, err := team.CloneOrPull(repoURL, destDir)

	s.mu.Lock()
	s.teamStatus.Configured = true
	s.teamStatus.RepoURL = repoURL
	s.teamStatus.LastSync = time.Now().UTC()
	s.teamStatus.Commit = commit
	if err != nil {
		s.teamStatus.Error = err.Error()
	} else {
		s.teamStatus.Error = ""
	}
	s.mu.Unlock()

	if err != nil {
		return
	}

	// Apply team-config.json if present (same logic as /api/import)
	tc, err := team.LoadConfig(destDir)
	if err != nil {
		return
	}
	if tc.Prefix != "" && filepath.IsAbs(tc.Prefix) && filepath.Clean(tc.Prefix) == tc.Prefix {
		pp := prefixOverridePath(s.RepoRoot)
		_ = os.MkdirAll(filepath.Dir(pp), 0o700)
		_ = os.WriteFile(pp, []byte(tc.Prefix), 0o600)
		s.mu.Lock()
		s.prefix = tc.Prefix
		s.mu.Unlock()
	}
	// Merge custom profiles from team config
	if len(tc.Profiles) > 0 {
		s.mu.Lock()
		for id, p := range tc.Profiles {
			s.profiles[id] = Profile{
				ID:          p.ID,
				Name:        p.Name,
				Description: p.Description,
				ToolIDs:     p.ToolIDs,
				Color:       p.Color,
			}
		}
		_ = s.saveProfiles()
		s.mu.Unlock()
	}
}

func (s *Server) handleTeamStatus(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	st := s.teamStatus
	s.mu.RUnlock()
	jsonOK(w, st)
}

func (s *Server) handleTeamSync(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	repoURL := s.Config.TeamConfigRepo
	s.mu.RUnlock()

	if repoURL == "" {
		jsonErr(w, "no team_config_repo configured", 400)
		return
	}
	go s.syncTeamConfig()
	jsonOK(w, map[string]any{"ok": true, "message": "sync started"})
}

// ── Manual install fallback ─────────────────────────────────────────────────

type manualPlatformInfo struct {
	DefaultPrefix  string   `json:"default_prefix"`
	EnvBlock       string   `json:"env_block"`
	InstallCmd     string   `json:"install_cmd"`
	CustomPrefixEx string   `json:"custom_prefix_ex"`
	Notes          []string `json:"notes"`
}

type splitPartInfo struct {
	ArchiveName      string `json:"archive_name"`
	PartsDir         string `json:"parts_dir"`
	PartCount        int    `json:"part_count"`
	WinAssembleCmd   string `json:"win_assemble_cmd"`
	LinuxAssembleCmd string `json:"linux_assemble_cmd"`
}

type manualInstallResponse struct {
	ToolID       string             `json:"tool_id"`
	ToolName     string             `json:"tool_name"`
	Version      string             `json:"version"`
	SetupScript  string             `json:"setup_script"`
	UsesPrebuilt bool               `json:"uses_prebuilt"`
	SplitParts   []splitPartInfo    `json:"split_parts,omitempty"`
	Windows      manualPlatformInfo `json:"windows"`
	Linux        manualPlatformInfo `json:"linux"`
}

// handleManualInstall returns platform-specific shell commands users can run
// directly when the web UI cannot complete an installation.
func (s *Server) handleManualInstall(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}

	// Derive the prebuilt subdirectory from the setup script path.
	// t.Setup is relative to repo root, e.g. "tools/toolchains/llvm/setup.sh"
	// → strip leading "tools/" and trailing filename to get "toolchains/llvm".
	var prebuiltSubpath string
	setupParts := strings.Split(t.Setup, "/")
	if len(setupParts) >= 3 && setupParts[0] == "tools" {
		prebuiltSubpath = strings.Join(setupParts[1:len(setupParts)-1], "/")
	}

	splitParts := s.scanPrebuiltParts(prebuiltSubpath, t.Version, t.ReceiptName)

	receipt := t.ReceiptName
	winPrefix := "${LOCALAPPDATA}/airgap-cpp-devkit/" + receipt
	linuxPrefix := "~/.local/share/airgap-cpp-devkit/" + receipt

	winEnv := "export AIRGAP_OS=windows\n" +
		`export PREBUILT_DIR="$(pwd)/prebuilt"` + "\n" +
		fmt.Sprintf(`export INSTALL_PREFIX="%s"`, winPrefix)

	linuxEnv := "export AIRGAP_OS=linux\n" +
		`export PREBUILT_DIR="$(pwd)/prebuilt"` + "\n" +
		fmt.Sprintf(`export INSTALL_PREFIX="%s"`, linuxPrefix)

	resp := manualInstallResponse{
		ToolID:       t.ID,
		ToolName:     t.Name,
		Version:      t.Version,
		SetupScript:  t.Setup,
		UsesPrebuilt: t.UsesPrebuilt,
		SplitParts:   splitParts,
		Windows: manualPlatformInfo{
			DefaultPrefix:  winPrefix,
			EnvBlock:       winEnv,
			InstallCmd:     "bash " + t.Setup,
			CustomPrefixEx: fmt.Sprintf("bash %s --prefix /c/custom/path/%s", t.Setup, receipt),
			Notes: []string{
				"Open Git Bash (MINGW64) — not PowerShell or Command Prompt",
				"cd to the devkit root (the folder containing launch.sh)",
				"The default prefix installs per-user; no administrator rights needed",
				"setup.sh handles split archives automatically",
			},
		},
		Linux: manualPlatformInfo{
			DefaultPrefix:  linuxPrefix,
			EnvBlock:       linuxEnv,
			InstallCmd:     "bash " + t.Setup,
			CustomPrefixEx: fmt.Sprintf("bash %s --prefix /opt/custom/%s", t.Setup, receipt),
			Notes: []string{
				"Run as root for a system-wide install (/opt/airgap-cpp-devkit/ prefix)",
				"cd to the devkit root (the folder containing launch.sh)",
				"The default prefix installs per-user; no root rights needed",
				"setup.sh handles split archives automatically",
			},
		},
	}
	jsonOK(w, resp)
}

// scanPrebuiltParts finds split-archive part files in the prebuilt directory
// for the given tool subpath and version, and returns reassembly commands.
func (s *Server) scanPrebuiltParts(subpath, version, receiptName string) []splitPartInfo {
	if subpath == "" || version == "" {
		return nil
	}
	searchDir := filepath.Join(s.PrebuiltDir, filepath.FromSlash(subpath), version)
	entries, err := os.ReadDir(searchDir)
	if err != nil {
		return nil
	}

	archives := map[string]int{}
	for _, e := range entries {
		if idx := strings.Index(e.Name(), ".part-"); idx != -1 {
			archives[e.Name()[:idx]]++
		}
	}
	if len(archives) == 0 {
		return nil
	}

	relDir, err := filepath.Rel(s.RepoRoot, searchDir)
	if err != nil {
		relDir = filepath.Join("prebuilt", subpath, version)
	}
	relDirSlash := filepath.ToSlash(relDir)

	var result []splitPartInfo
	for archiveName, count := range archives {
		result = append(result, splitPartInfo{
			ArchiveName: archiveName,
			PartsDir:    relDirSlash,
			PartCount:   count,
			WinAssembleCmd: fmt.Sprintf(
				`cat "%s/%s.part-"* | tar -xJ --strip-components=1 -C "${LOCALAPPDATA}/airgap-cpp-devkit/%s"`,
				relDirSlash, archiveName, receiptName),
			LinuxAssembleCmd: fmt.Sprintf(
				`cat %s/%s.part-* | tar -xJ --strip-components=1 -C ~/.local/share/airgap-cpp-devkit/%s`,
				relDirSlash, archiveName, receiptName),
		})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ArchiveName < result[j].ArchiveName })
	return result
}
