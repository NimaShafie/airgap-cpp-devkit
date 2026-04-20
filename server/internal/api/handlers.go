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

	profiles map[string]Profile
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

	return s, nil
}

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/", s.handleDashboard)
	r.Get("/logs", s.handleLogs)
	r.Get("/health", s.handleHealth)
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
	r.Post("/packages/upload", s.handlePackageUpload)
	r.Delete("/packages/{id}", s.handlePackageDelete)
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
		result = append(result, tools.GetStatus(t, prefix, s.OS))
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
	jsonOK(w, map[string]string{"status": "ok", "version": "2.0"})
}

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	ts := s.getTools()

	categories := map[string][]tools.ToolStatus{}
	for _, t := range ts {
		categories[t.Category] = append(categories[t.Category], t)
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
		"Profiles":       s.profiles,
		"InstalledCount": installed,
		"TotalCount":     len(ts),
		"OS":             s.OS,
		"Prefix":         s.currentPrefix(),
		"Hostname":       hostname,
		"Privilege":      privilege,
		"Year":           time.Now().Year(),
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
	jsonOK(w, tools.GetStatus(t, s.currentPrefix(), s.OS))
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
	sse.Done(doneStatus)
}

func (s *Server) handleUninstall(w http.ResponseWriter, r *http.Request) {
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

	sse.Send(fmt.Sprintf("Uninstalling %s...", t.Name))
	clean := strings.ReplaceAll(t.ReceiptName, "/", string(os.PathSeparator))
	installDir := filepath.Join(s.currentPrefix(), clean)
	if _, err := os.Stat(installDir); os.IsNotExist(err) {
		sse.Send("Nothing to remove — directory does not exist.")
		sse.Done("success")
		return
	}
	if err := os.RemoveAll(installDir); err != nil {
		sse.Send("✗ ERROR: " + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send("✓ Removed " + installDir)
	sse.Done("success")
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

func (s *Server) handleCheck(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, "tool not found", 404)
		return
	}

	// No check_cmd: fall back to reading the install receipt
	if t.CheckCmd == "" {
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
			jsonOK(w, map[string]any{
				"ok":        true,
				"output":    strings.Join(lines, "\n"),
				"check_cmd": "(receipt file)",
			})
		} else {
			jsonOK(w, map[string]any{
				"ok":        false,
				"error":     "No check_cmd defined for this tool and no receipt file found.\nAdd a \"check_cmd\" field to its devkit.json to enable live version probing.",
				"check_cmd": "(none)",
			})
		}
		return
	}

	// Run the configured check command
	// On Windows run via cmd /c so PATH-aware commands resolve correctly
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.Command("cmd", append([]string{"/c"}, t.CheckCmd)...)
	} else {
		parts := strings.Fields(t.CheckCmd)
		cmd = exec.Command(parts[0], parts[1:]...)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		jsonOK(w, map[string]any{
			"ok":        false,
			"output":    string(out),
			"error":     err.Error(),
			"check_cmd": t.CheckCmd,
		})
		return
	}
	jsonOK(w, map[string]any{
		"ok":        true,
		"output":    string(out),
		"check_cmd": t.CheckCmd,
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

func (s *Server) handleToolLogList(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	logDir := filepath.Join(s.RepoRoot, "devkit-logs", strings.ReplaceAll(id, "/", "_"))
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
	logDir := filepath.Join(s.RepoRoot, "devkit-logs", strings.ReplaceAll(id, "/", "_"))
	b, err := os.ReadFile(filepath.Join(logDir, file))
	if err != nil {
		jsonErr(w, "log not found", 404)
		return
	}
	jsonOK(w, map[string]any{"ok": true, "log": string(b), "filename": file})
}

func (s *Server) handleShutdown(w http.ResponseWriter, r *http.Request) {
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
	if err := r.ParseMultipartForm(128 << 20); err != nil {
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

	// Extract zip (guard against path traversal)
	for _, f := range zr.File {
		rel := filepath.Clean(f.Name)
		if strings.HasPrefix(rel, "..") {
			continue
		}
		target := filepath.Join(destDir, rel)
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
	destDir := filepath.Join(s.RepoRoot, "user-packages", id)
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
