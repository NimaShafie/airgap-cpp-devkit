package api

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	devconfig "github.com/nimzshafie/airgap-devkit/server/internal/config"
	"github.com/nimzshafie/airgap-devkit/server/internal/export"
	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

type Server struct {
	RepoRoot   string
	PrebuiltDir string
	OS         string
	Bash       string
	Config     devconfig.Config
	webFS      fs.FS

	mu     sync.RWMutex
	allTools []tools.Tool
	prefix  string

	profiles      map[string]Profile
	metaOverrides map[string]ToolMetaOverride
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
		allTools:    loaded,
		prefix:      detectPrefix(currentOS),
		profiles: map[string]Profile{
			"minimal": {ID: "minimal", Name: "Minimal", Description: "Required tools only", Color: "gray",
				ToolIDs: []string{"toolchains/clang", "cmake", "python", "style-formatter"}},
			"cpp-dev": {ID: "cpp-dev", Name: "C++ Developer", Description: "Core C++ development tools", Color: "blue",
				ToolIDs: []string{"toolchains/clang", "cmake", "python", "conan", "vscode-extensions", "sqlite", "7zip"}},
			"devops": {ID: "devops", Name: "DevOps", Description: "Infrastructure and automation tools", Color: "green",
				ToolIDs: []string{"cmake", "python", "conan", "sqlite", "7zip"}},
			"full": {ID: "full", Name: "Full Install", Description: "All available tools", Color: "purple",
				ToolIDs: allIDs},
		},
	}

	// Load persisted prefix override
	if p := readPrefixOverride(repoRoot); p != "" {
		s.prefix = p
	}

	// Load persisted profiles (overrides defaults if file exists)
	s.loadProfiles()

	// Load persisted tool meta overrides
	s.metaOverrides = make(map[string]ToolMetaOverride)
	s.loadMetaOverrides()

	return s, nil
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/", s.handleDashboard)
	r.Get("/logs", s.handleLogs)
	r.Get("/health", s.handleHealth)
	r.Get("/api/network", s.handleNetworkStatus)
	r.Get("/api/updates", s.handleCheckUpdates)
	r.Get("/api/update-history", s.handleUpdateHistory)
	r.Get("/download-update/{id}", s.handleDownloadUpdate)
	r.Get("/api/tool/{id}/versions", s.handleToolVersions)
	r.Delete("/api/tool/{id}/versions/{ver}", s.handleDeleteVersion)
	r.Post("/api/tool/{id}/versions/{ver}/use", s.handleUseVersion)
	r.Get("/api/tools", s.handleAPITools)
	r.Get("/api/tool/{id}", s.handleAPITool)
	r.Get("/api/prefix", s.handleGetPrefix)
	r.Post("/api/prefix", s.handleSetPrefix)
	r.Delete("/api/prefix", s.handleResetPrefix)
	r.Get("/api/export", s.handleExport)
	r.Post("/api/import", s.handleImport)
	r.Get("/api/profiles", s.handleGetProfiles)
	r.Post("/api/profiles", s.handleSaveProfile)
	r.Delete("/api/profiles/{id}", s.handleDeleteProfile)
	r.Post("/api/config", s.handleSaveConfig)
	r.Get("/install/{id}", s.handleInstall)
	r.Delete("/uninstall/{id}", s.handleUninstall)
	r.Get("/install-profile/{id}", s.handleInstallProfile)
	r.Get("/check/{id}", s.handleCheck)
	r.Get("/api/tool/{id}/log", s.handleToolLog)
	r.Get("/api/tool/{id}/logs", s.handleToolLogList)
	r.Get("/api/tool/{id}/logs/{file}", s.handleToolLogFile)
	r.Get("/api/tool/{id}/packages/status", s.handleBundlePackageStatus)
	r.Get("/install-pkg/{id}/{pkg}", s.handleInstallPackage)
	r.Get("/remove-pkg/{id}/{pkg}", s.handleRemovePackage)
	r.Post("/packages/upload", s.handlePackageUpload)
	r.Delete("/packages/{id}", s.handlePackageDelete)
	r.Get("/api/layout", s.handleGetLayout)
	r.Post("/api/layout", s.handleSaveLayout)
	r.Delete("/api/layout", s.handleResetLayout)
	r.Post("/api/open-prefix", s.handleOpenPrefix)
	r.Post("/api/tool/{id}/meta", s.handleSaveToolMeta)
	r.Delete("/api/tool/{id}/meta", s.handleResetToolMeta)
	r.Get("/api/health/tools", s.handleHealthTools)
	r.Get("/shutdown", s.handleShutdown)
	return r
}

// ── Profile persistence ──────────────────────────────────────────────────────

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
	return os.WriteFile(s.profilesPath(), data, 0o644)
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
	return os.WriteFile(s.metaOverridesPath(), data, 0o644)
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
		jsonErr(w, "tool not found", 404)
		return
	}
	var ov ToolMetaOverride
	if err := json.NewDecoder(r.Body).Decode(&ov); err != nil {
		jsonErr(w, "invalid body", 400)
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
		TeamName   string `json:"team_name"`
		OrgName    string `json:"org_name"`
		DevkitName string `json:"devkit_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonErr(w, "invalid body", 400)
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
	cfg := s.Config
	s.mu.Unlock()

	if err := devconfig.Save(s.RepoRoot, cfg); err != nil {
		jsonErr(w, "failed to save config: "+err.Error(), 500)
		return
	}
	jsonOK(w, map[string]any{"ok": true})
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
	if goos != "windows" {
		return goos
	}
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

func detectPrefix(currentOS string) string {
	if currentOS == "windows" {
		if la := winLocalAppData(); la != "" {
			return filepath.Join(la, "airgap-cpp-devkit")
		}
	}
	if _, err := os.Stat("/opt/airgap-cpp-devkit"); err == nil {
		return "/opt/airgap-cpp-devkit"
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share", "airgap-cpp-devkit")
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

func prefixOverridePath(repoRoot string) string {
	return filepath.Join(repoRoot, "manager", "src", "airgap_devkit", ".devkit-prefix")
}

func readPrefixOverride(repoRoot string) string {
	data, err := os.ReadFile(prefixOverridePath(repoRoot))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func jsonErr(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	fmt.Fprintf(w, `{"error":%q}`, msg)
}

func jsonOK(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

// ─── route handlers ──────────────────────────────────────────────────────────

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	jsonOK(w, map[string]string{"status": "ok", "version": AppVersion})
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
	privilege := "user"
	if runtime.GOOS == "windows" {
		// simple heuristic: check if we can write to Program Files
		if _, err := os.Stat(`C:\Program Files`); err == nil {
			f, err2 := os.CreateTemp(`C:\Program Files`, ".devkit-priv-*")
			if err2 == nil {
				f.Close()
				os.Remove(f.Name())
				privilege = "admin"
			}
		}
	} else {
		if os.Getuid() == 0 {
			privilege = "admin"
		}
	}

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
		"Prefix":         s.currentPrefix(),
		"Hostname":       hostname,
		"Privilege":      privilege,
		"Year":           time.Now().Year(),
		"AppVersion":     AppVersion,
	}

	if err := renderTemplate(s.webFS, "dashboard.html", w, data); err != nil {
		http.Error(w, "template error: "+err.Error(), 500)
	}
}

func (s *Server) handleLogs(w http.ResponseWriter, r *http.Request) {
	data := map[string]any{
		"Config": s.Config,
		"OS":     s.OS,
	}
	if err := renderTemplate(s.webFS, "logs.html", w, data); err != nil {
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
		jsonErr(w, "tool not found", 404)
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
	if err := os.WriteFile(prefixOverridePath(s.RepoRoot), []byte(body.Prefix), 0o644); err != nil {
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
	w.Header().Set("Content-Type", "application/json")
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
		_ = os.WriteFile(prefixOverridePath(s.RepoRoot), []byte(tc.Prefix), 0o644)
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
		jsonErr(w, "tool not found", 404)
		return
	}

	sse, ok2 := newSSE(w)
	if !ok2 {
		http.Error(w, "streaming not supported", 500)
		return
	}

	// Save full install output to a timestamped log file
	logDir := filepath.Join(s.RepoRoot, "devkit-logs", strings.ReplaceAll(id, "/", "_"))
	_ = os.MkdirAll(logDir, 0o755)
	logFile := filepath.Join(logDir, time.Now().UTC().Format("20060102-150405")+".log")
	ssePipe := newPipe(sse)
	var pw io.Writer = ssePipe
	if f, err := os.Create(logFile); err == nil {
		pw = io.MultiWriter(ssePipe, f)
		defer f.Close()
	}

	env := s.installEnv(t)
	rc := tools.RunInstall(s.Bash, s.RepoRoot, t, t.SetupArgs, env, pw)
	finalMsg := "✓ Installation complete"
	doneStatus := "success"
	if rc != 0 {
		finalMsg = fmt.Sprintf("✗ Installation failed (exit %d)", rc)
		doneStatus = "failed"
	}
	sse.Send(finalMsg)
	// Also append final line to log file
	if f, err := os.OpenFile(logFile, os.O_APPEND|os.O_WRONLY, 0o644); err == nil {
		fmt.Fprintln(f, finalMsg)
		f.Close()
	}

	// Post-install verification: run check_cmd to confirm the binary is reachable.
	if rc == 0 && (t.CheckBinary != "" || t.ResolvedCheckCmd(runtime.GOOS) != "") {
		sse.Send("── Verifying install ──")
		res := s.runCheckCmd(t)
		firstLine := strings.SplitN(strings.TrimSpace(res.Output), "\n", 2)[0]
		if res.OK {
			if firstLine != "" {
				sse.Send("✓ " + firstLine)
			} else {
				sse.Send("✓ Check passed")
			}
		} else {
			if firstLine != "" {
				sse.Send("⚠ Check after install: " + firstLine)
			}
			if res.Error != "" {
				sse.Send("  " + res.Error)
			}
			sse.Send("  Binary may not be on PATH until you restart your shell.")
		}
	}

	sse.Done(doneStatus)
}

func (s *Server) handleUninstall(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, "tool not found", 404)
		return
	}

	w.Header().Set("Content-Type", "application/json")
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
			_ = os.WriteFile(path, []byte(strings.Join(kept, "\n")), 0o644)
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
		rc := tools.RunInstall(s.Bash, s.RepoRoot, t, t.SetupArgs, env, pw)
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
	extra := instDir + sep + instDir + string(os.PathSeparator) + "bin"
	env := os.Environ()
	for i, e := range env {
		if strings.HasPrefix(strings.ToUpper(e), "PATH=") {
			env[i] = e[:5] + extra + sep + e[5:]
			return env
		}
	}
	return append(env, "PATH="+extra)
}

// runCheckResult holds the outcome of a single tool check.
type runCheckResult struct {
	OK       bool
	Output   string
	Error    string
	CheckCmd string // the command that was actually run
}

// runCheckCmd executes the check for a tool and returns the result.
// Uses check_binary for a direct exec (no bash, no shell escaping) when set;
// otherwise resolves check_cmd_windows / check_cmd_linux / check_cmd and runs
// it through bash so shell metacharacters work consistently across platforms.
func (s *Server) runCheckCmd(t tools.Tool) runCheckResult {
	checkCmd := t.ResolvedCheckCmd(runtime.GOOS)

	// Native binary probe — bypasses bash entirely, no shell-escape issues.
	if t.CheckBinary != "" {
		args := t.CheckArgs
		if len(args) == 0 {
			args = []string{"--version"}
		}
		cmd := exec.Command(t.CheckBinary, args...)
		if env := s.checkEnv(t); env != nil {
			cmd.Env = env
		}
		out, err := cmd.CombinedOutput()
		if err != nil {
			return runCheckResult{OK: false, Output: string(out), Error: err.Error(), CheckCmd: t.CheckBinary + " " + strings.Join(args, " ")}
		}
		return runCheckResult{OK: true, Output: string(out), CheckCmd: t.CheckBinary + " " + strings.Join(args, " ")}
	}

	if checkCmd == "" {
		return runCheckResult{OK: false, Error: "no check_cmd configured", CheckCmd: "(none)"}
	}

	cmd := exec.Command("bash", "-c", checkCmd)
	if env := s.checkEnv(t); env != nil {
		cmd.Env = env
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return runCheckResult{OK: false, Output: string(out), Error: err.Error(), CheckCmd: checkCmd}
	}
	return runCheckResult{OK: true, Output: string(out), CheckCmd: checkCmd}
}

func (s *Server) handleCheck(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, "tool not found", 404)
		return
	}

	// No check configured: fall back to reading the install receipt.
	if t.CheckBinary == "" && t.ResolvedCheckCmd(runtime.GOOS) == "" {
		receipt := tools.GetReceipt(s.currentPrefix(), t.ReceiptName)
		if receipt.Exists {
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
		} else {
			jsonOK(w, map[string]any{
				"ok":        false,
				"error":     "No check_cmd defined for this tool and no receipt file found.\nAdd a \"check_cmd\" field to its devkit.json to enable live version probing.",
				"check_cmd": "(none)",
			})
		}
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
		jsonErr(w, "tool not found", 404)
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
			ts = t.Format("Jan 02, 2006 15:04:05 UTC")
		}
		logs = append(logs, logEntry{File: e.Name(), Size: sz, Time: ts})
	}
	jsonOK(w, map[string]any{"ok": true, "logs": logs})
}

func (s *Server) handleToolLogFile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	file := chi.URLParam(r, "file")
	// Sanitise: only allow safe filenames (digits, dash, .log)
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
				hr.CheckCmd = "(none)"
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

var reSlug = regexp.MustCompile(`[^a-z0-9\-]`)

func slugify(name string) string {
	s := strings.ToLower(strings.TrimSpace(name))
	s = reSlug.ReplaceAllString(s, "-")
	s = regexp.MustCompile(`-+`).ReplaceAllString(s, "-")
	return strings.Trim(s, "-")
}

func (s *Server) handlePackageUpload(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(512 << 20); err != nil {
		jsonErr(w, "request too large or not multipart", 400)
		return
	}
	file, header, err := r.FormFile("package")
	if err != nil {
		jsonErr(w, "missing 'package' file field", 400)
		return
	}
	defer file.Close()

	if !strings.HasSuffix(strings.ToLower(header.Filename), ".zip") {
		jsonErr(w, "only .zip packages are supported", 400)
		return
	}

	// Read entire zip into memory so we can inspect it first
	data, err := io.ReadAll(file)
	if err != nil {
		jsonErr(w, "failed to read upload: "+err.Error(), 500)
		return
	}

	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		jsonErr(w, "invalid zip: "+err.Error(), 400)
		return
	}

	// Derive tool ID from filename: "My Tool 1.2.zip" → "my-tool"
	base := strings.TrimSuffix(filepath.Base(header.Filename), ".zip")
	toolID := slugify(base)
	if toolID == "" {
		toolID = "user-package"
	}

	destDir := filepath.Join(s.RepoRoot, "user-packages", toolID)
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		jsonErr(w, "cannot create package dir: "+err.Error(), 500)
		return
	}

	// Extract zip — reject any entry whose resolved path escapes destDir.
	safeRoot := filepath.Clean(destDir) + string(os.PathSeparator)
	for _, f := range zr.File {
		target := filepath.Join(destDir, filepath.Clean(f.Name))
		if !strings.HasPrefix(target, safeRoot) {
			continue
		}
		if f.FileInfo().IsDir() {
			_ = os.MkdirAll(target, 0o755)
			continue
		}
		_ = os.MkdirAll(filepath.Dir(target), 0o755)
		rc, err := f.Open()
		if err != nil {
			continue
		}
		out, err := os.Create(target)
		if err != nil {
			rc.Close()
			continue
		}
		_, _ = io.Copy(out, rc)
		out.Close()
		rc.Close()
	}

	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "unknown"
	}
	uploadedAt := time.Now().UTC().Format("2006-01-02 15:04 UTC")

	// Generate devkit.json if not included in the zip
	devkitJSON := filepath.Join(destDir, "devkit.json")
	if _, err := os.Stat(devkitJSON); os.IsNotExist(err) {
		manifest := map[string]any{
			"id":           toolID,
			"name":         base,
			"version":      "1.0.0",
			"category":     "Developer Tools",
			"platform":     "both",
			"description":  "User-uploaded package: " + base,
			"setup":        "setup.sh",
			"receipt_name": toolID,
			"source":       "user",
			"uploaded_by":  hostname,
			"uploaded_at":  uploadedAt,
		}
		mjson, _ := json.MarshalIndent(manifest, "", "  ")
		_ = os.WriteFile(devkitJSON, mjson, 0o644)

		// Generate a minimal setup.sh
		setupSh := filepath.Join(destDir, "setup.sh")
		setupContent := fmt.Sprintf(`#!/usr/bin/env bash
set -euo pipefail
TOOL_DIR="${INSTALL_PREFIX}"
mkdir -p "$TOOL_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$SCRIPT_DIR/"* "$TOOL_DIR/" 2>/dev/null || true
{
  echo "Status: success"
  echo "Version: 1.0.0"
  echo "Installed-At: $(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ)"
  echo "Install-Path: $TOOL_DIR"
} > "$TOOL_DIR/INSTALL_LOG.txt"
echo "✓ %s installed to $TOOL_DIR"
`, base)
		_ = os.WriteFile(setupSh, []byte(setupContent), 0o755)
	}

	// Reload tool list
	s.mu.Lock()
	if loaded, err := tools.Load(s.RepoRoot); err == nil {
		s.allTools = loaded
	}
	s.mu.Unlock()

	jsonOK(w, map[string]any{
		"ok":      true,
		"id":      toolID,
		"name":    base,
		"message": fmt.Sprintf("Package '%s' uploaded and registered as tool '%s'", base, toolID),
	})
}

func (s *Server) handlePackageDelete(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	userPkgRoot := filepath.Clean(filepath.Join(s.RepoRoot, "user-packages"))
	destDir := filepath.Join(userPkgRoot, id)
	// Reject any id that escapes the user-packages/ directory (e.g. "../tools").
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
