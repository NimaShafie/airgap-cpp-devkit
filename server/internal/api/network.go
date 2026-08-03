package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/nimzshafie/airgap-devkit/server/internal/timefmt"
	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

// ── Network check ──────────────────────────────────────────────────────────

type NetworkStatus struct {
	Online    bool  `json:"online"`
	LatencyMs int64 `json:"latency_ms"`
}

func checkNetwork() NetworkStatus {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", "8.8.8.8:53", 3*time.Second)
	if err != nil {
		conn2, err2 := net.DialTimeout("tcp", "1.1.1.1:53", 3*time.Second)
		if err2 != nil {
			return NetworkStatus{}
		}
		conn2.Close()
	} else {
		conn.Close()
	}
	return NetworkStatus{Online: true, LatencyMs: time.Since(start).Milliseconds()}
}

func (s *Server) handleNetworkStatus(w http.ResponseWriter, r *http.Request) {
	if !s.Config.AllowEgress {
		jsonOK(w, NetworkStatus{})
		return
	}
	jsonOK(w, checkNetwork())
}

// ── Update check ───────────────────────────────────────────────────────────

type UpdateInfo struct {
	ToolID         string `json:"tool_id"`
	ToolName       string `json:"tool_name"`
	CurrentVersion string `json:"current_version"`
	LatestTag      string `json:"latest_tag"`
	LatestVersion  string `json:"latest_version"`
	Available      bool   `json:"available"`
	DownloadURL    string `json:"download_url"`
	AssetName      string `json:"asset_name"`
}

type updateCacheEntry struct {
	mu        sync.RWMutex
	updates   []UpdateInfo
	online    bool
	checkedAt time.Time
}

var _updateCache updateCacheEntry

func (s *Server) handleCheckUpdates(w http.ResponseWriter, r *http.Request) {
	force := r.URL.Query().Get("force") == "1"

	_updateCache.mu.RLock()
	age := time.Since(_updateCache.checkedAt)
	cached := age < 30*time.Minute && !force && !_updateCache.checkedAt.IsZero()
	if cached {
		result := _updateCache.updates
		online := _updateCache.online
		_updateCache.mu.RUnlock()
		jsonOK(w, map[string]any{"online": online, "updates": result, "cached": true, "age_s": int(age.Seconds())})
		return
	}
	_updateCache.mu.RUnlock()

	if !s.Config.AllowEgress {
		jsonOK(w, map[string]any{"online": false, "updates": []any{}, "cached": false})
		return
	}
	ns := checkNetwork()
	if !ns.Online {
		jsonOK(w, map[string]any{"online": false, "updates": []any{}, "cached": false})
		return
	}

	s.mu.RLock()
	ts := s.allTools
	s.mu.RUnlock()

	client := &http.Client{Timeout: 10 * time.Second}
	var updates []UpdateInfo

	for _, t := range ts {
		if t.GithubRepo == "" {
			continue
		}
		assetMatch := t.AssetMatch
		if assetMatch == "" {
			if s.OS == "windows" {
				assetMatch = "64-bit.exe"
			} else {
				assetMatch = "linux"
			}
		}
		tag, ver, dlURL, asset, err := fetchGitHubLatest(client, t.GithubRepo, assetMatch, t.TagPrefix)
		if err != nil {
			continue
		}
		updates = append(updates, UpdateInfo{
			ToolID:         t.ID,
			ToolName:       t.Name,
			CurrentVersion: t.Version,
			LatestTag:      tag,
			LatestVersion:  ver,
			Available:      ver != t.Version,
			DownloadURL:    dlURL,
			AssetName:      asset,
		})
	}

	_updateCache.mu.Lock()
	_updateCache.updates = updates
	_updateCache.online = true
	_updateCache.checkedAt = time.Now()
	_updateCache.mu.Unlock()

	jsonOK(w, map[string]any{"online": true, "updates": updates, "cached": false})
}

func fetchGitHubLatest(client *http.Client, repo, assetMatch, tagPrefix string) (tag, version, downloadURL, assetName string, err error) {
	url := "https://api.github.com/repos/" + repo + "/releases/latest"
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/vnd.github.v3+json")
	req.Header.Set("User-Agent", "airgap-devkit/1.0")

	resp, err := client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		err = fmt.Errorf("GitHub API %d", resp.StatusCode)
		return
	}

	var release struct {
		TagName string `json:"tag_name"`
		Assets  []struct {
			Name               string `json:"name"`
			BrowserDownloadURL string `json:"browser_download_url"`
		} `json:"assets"`
	}
	if err = json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return
	}

	tag = release.TagName
	// Clean version: strip tag_prefix (default "v"), then strip ".windows.N" suffix.
	// Using TrimPrefix so tools with no "v" tag (e.g. osslsigncode "2.13") are unchanged.
	prefix := tagPrefix
	if prefix == "" {
		prefix = "v"
	}
	version = strings.TrimPrefix(tag, prefix)
	version = regexp.MustCompile(`\.windows\.\d+$`).ReplaceAllString(version, "")

	lowerMatch := strings.ToLower(assetMatch)
	for _, a := range release.Assets {
		if strings.Contains(strings.ToLower(a.Name), lowerMatch) {
			downloadURL = a.BrowserDownloadURL
			assetName = a.Name
			return
		}
	}
	err = fmt.Errorf("no asset matching %q in %s", assetMatch, tag)
	return
}

// ── Download & apply update ────────────────────────────────────────────────

func (s *Server) handleDownloadUpdate(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}
	if t.GithubRepo == "" {
		jsonErr(w, "no update source configured for this tool", 400)
		return
	}

	sse, ok2 := newSSE(w)
	if !ok2 {
		http.Error(w, "streaming not supported", 500)
		return
	}

	if !s.Config.AllowEgress {
		sse.Send("ERROR: Egress is disabled. Set allow_egress: true in devkit.config.json to enable update downloads.")
		sse.Done("failed")
		return
	}
	ns := checkNetwork()
	if !ns.Online {
		sse.Send("ERROR: No internet connection.")
		sse.Done("failed")
		return
	}

	sse.Send(fmt.Sprintf("Checking latest release for %s (%s)...", t.Name, t.GithubRepo))
	client := &http.Client{Timeout: 15 * time.Second}

	tag, ver, dlURL, assetName, err := fetchGitHubLatest(client, t.GithubRepo, s.resolveAssetMatch(t), t.TagPrefix)
	if err != nil {
		sse.Send("ERROR: " + err.Error())
		sse.Done("failed")
		return
	}

	sse.Send(fmt.Sprintf("Current version : %s", t.Version))
	sse.Send(fmt.Sprintf("Latest release  : %s (tag: %s)", ver, tag))

	if ver == t.Version {
		sse.Send("Already at latest version — nothing to download.")
		sse.Done("success")
		return
	}

	sse.Send(fmt.Sprintf("Update available: %s → %s", t.Version, ver))
	sse.Send(fmt.Sprintf("Asset           : %s", assetName))
	sse.Send(fmt.Sprintf("URL             : %s", dlURL))

	// Destination under prebuilt/ (built from the resolved tool id, not the raw
	// request parameter, and from the release tag rather than caller input).
	destDir := filepath.Join(s.PrebuiltDir, devToolsDir,
		strings.ReplaceAll(t.ID, "/", string(os.PathSeparator)), ver)
	destFile := filepath.Join(destDir, filepath.Base(assetName))

	if !ensureAssetDownloaded(sse, dlURL, destDir, destFile) {
		return
	}

	sum := s.recordChecksum(sse, destDir, destFile, id, ver, assetName, dlURL)
	s.applyVersionBump(sse, id, t.Version, ver)
	s.reloadToolRegistry(sse)

	hostname, _ := os.Hostname()
	s.appendUpdateHistory(UpdateHistoryEntry{
		ToolID:      id,
		ToolName:    t.Name,
		FromVersion: t.Version,
		ToVersion:   ver,
		Asset:       assetName,
		Sha256:      sum,
		Host:        hostname,
		PerformedAt: time.Now().UTC().Format(time.RFC3339),
	})

	sse.Send(fmt.Sprintf("✓ %s %s ready — click Install to deploy.", t.Name, ver))
	sse.Done("success")
}

// resolveAssetMatch returns the release-asset name filter for a tool, falling
// back to an OS-appropriate default when the tool defines none.
func (s *Server) resolveAssetMatch(t tools.Tool) string {
	if t.AssetMatch != "" {
		return t.AssetMatch
	}
	if s.OS == "windows" {
		return "64-bit.exe"
	}
	return "linux"
}

// ensureAssetDownloaded downloads dlURL to destFile unless it is already
// cached. Progress is streamed over sse; it returns false (after emitting a
// failure event) when a fatal error occurred.
func ensureAssetDownloaded(sse *sseWriter, dlURL, destDir, destFile string) bool {
	// Only fetch over TLS so the transport cannot be downgraded or MITM'd; the
	// recorded checksum then pins the bytes for later air-gapped installs.
	if !strings.HasPrefix(strings.ToLower(dlURL), "https://") {
		sse.Send("ERROR: refusing non-https download URL: " + dlURL)
		sse.Done("failed")
		return false
	}
	if _, statErr := os.Stat(destFile); statErr == nil {
		sse.Send(fmt.Sprintf("File already cached: %s", destFile))
		return true
	}
	if err := os.MkdirAll(destDir, 0o750); err != nil {
		sse.Send("ERROR: cannot create directory: " + err.Error())
		sse.Done("failed")
		return false
	}

	sse.Send("Downloading...")
	dlClient := &http.Client{Timeout: 20 * time.Minute}
	dlResp, dlErr := dlClient.Get(dlURL)
	if dlErr != nil {
		sse.Send("ERROR: download failed: " + dlErr.Error())
		sse.Done("failed")
		return false
	}
	defer dlResp.Body.Close()

	f, fErr := os.Create(destFile)
	if fErr != nil {
		sse.Send("ERROR: cannot write file: " + fErr.Error())
		sse.Done("failed")
		return false
	}
	written, cpErr := io.Copy(f, dlResp.Body)
	f.Close()
	if cpErr != nil {
		os.Remove(destFile)
		sse.Send("ERROR: download incomplete: " + cpErr.Error())
		sse.Done("failed")
		return false
	}
	sse.Send(fmt.Sprintf("Downloaded %.1f MB → %s", float64(written)/1024/1024, destFile))
	return true
}

// recordChecksum computes the asset's SHA-256 and writes the prebuilt
// manifest.json so air-gapped installs can verify it. Returns the checksum, or
// "" if it could not be computed.
func (s *Server) recordChecksum(sse *sseWriter, destDir, destFile, id, ver, assetName, dlURL string) string {
	sum, sumErr := sha256File(destFile)
	if sumErr != nil {
		sse.Send("WARNING: could not compute sha256: " + sumErr.Error())
		return ""
	}
	sse.Send("sha256          : " + sum)
	if err := writePrebuiltManifest(destDir, id, ver, s.OS, assetName, dlURL, sum); err != nil {
		sse.Send(fmt.Sprintf("WARNING: could not write manifest.json: %v", err))
	} else {
		sse.Send("Wrote manifest.json with checksum.")
	}
	return sum
}

// applyVersionBump updates the tool's devkit.json and sibling setup.sh to
// newVer, streaming a status line for each.
func (s *Server) applyVersionBump(sse *sseWriter, id, oldVer, newVer string) {
	devkitPath := findDevkitJSON(s.RepoRoot, id)
	if devkitPath == "" {
		return
	}
	if err := updateDevkitVersion(devkitPath, newVer); err != nil {
		sse.Send(fmt.Sprintf("WARNING: could not update devkit.json: %v", err))
	} else {
		sse.Send(fmt.Sprintf("Updated devkit.json version → %s", newVer))
	}
	setupPath := filepath.Join(filepath.Dir(devkitPath), "setup.sh")
	if err := updateSetupVersion(setupPath, oldVer, newVer); err != nil {
		sse.Send(fmt.Sprintf("WARNING: could not update setup.sh: %v", err))
	} else {
		sse.Send(fmt.Sprintf("Updated setup.sh VERSION → %s", newVer))
	}
}

// reloadToolRegistry reloads the tool list from disk and busts the update
// cache so the newly downloaded version is reflected immediately.
func (s *Server) reloadToolRegistry(sse *sseWriter) {
	loaded, lErr := tools.Load(s.RepoRoot)
	if lErr != nil {
		return
	}
	s.mu.Lock()
	s.allTools = loaded
	s.mu.Unlock()
	_updateCache.mu.Lock()
	_updateCache.checkedAt = time.Time{}
	_updateCache.mu.Unlock()
	sse.Send("Tool registry refreshed.")
}

// ── Update history ─────────────────────────────────────────────────────────

type UpdateHistoryEntry struct {
	ToolID      string `json:"tool_id"`
	ToolName    string `json:"tool_name"`
	FromVersion string `json:"from_version"`
	ToVersion   string `json:"to_version"`
	Asset       string `json:"asset"`
	Sha256      string `json:"sha256,omitempty"`
	Host        string `json:"host"`
	PerformedAt string `json:"performed_at"`
	// PerformedAtDisplay is the Pacific-time rendering shown in the UI; the
	// machine-readable PerformedAt above stays RFC3339 for sorting and parsing.
	PerformedAtDisplay string `json:"performed_at_display,omitempty"`
}

// sha256File returns the hex-encoded SHA-256 of the file at path.
func sha256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// writePrebuiltManifest writes a minimal prebuilt manifest.json recording the
// downloaded asset and its checksum, in the format the bash install path reads
// (devkit_verify_archive). osKey is "windows" or "linux".
func writePrebuiltManifest(dir, tool, version, osKey, archive, source, sum string) error {
	m := map[string]any{
		"tool":    tool,
		"version": version,
		"source":  source,
		"platforms": map[string]any{
			osKey: map[string]string{"archive": archive, "sha256": sum},
		},
	}
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "manifest.json"), append(b, '\n'), 0o640)
}

func (s *Server) updateHistoryPath() string {
	return filepath.Join(s.RepoRoot, "devkit-update-history.json")
}

func (s *Server) appendUpdateHistory(entry UpdateHistoryEntry) {
	path := s.updateHistoryPath()
	var entries []UpdateHistoryEntry
	if data, err := os.ReadFile(path); err == nil {
		json.Unmarshal(data, &entries) //nolint:errcheck
	}
	entries = append([]UpdateHistoryEntry{entry}, entries...) // newest first
	if data, err := json.MarshalIndent(entries, "", "  "); err == nil {
		os.WriteFile(path, append(data, '\n'), 0o600) //nolint:errcheck
	}
}

func (s *Server) handleUpdateHistory(w http.ResponseWriter, r *http.Request) {
	toolFilter := r.URL.Query().Get("tool")
	var entries []UpdateHistoryEntry
	if data, err := os.ReadFile(s.updateHistoryPath()); err == nil {
		json.Unmarshal(data, &entries) //nolint:errcheck
	}
	if toolFilter != "" {
		var filtered []UpdateHistoryEntry
		for _, e := range entries {
			if e.ToolID == toolFilter {
				filtered = append(filtered, e)
			}
		}
		entries = filtered
	}
	if entries == nil {
		entries = []UpdateHistoryEntry{}
	}
	// Render each timestamp in Pacific time for display; this normalises older
	// entries written before the format was standardised.
	for i := range entries {
		entries[i].PerformedAtDisplay = timefmt.Normalize(entries[i].PerformedAt)
	}
	jsonOK(w, map[string]any{"entries": entries})
}

// ── Version management ────────────────────────────────────────────────────

type ToolVersion struct {
	Version string   `json:"version"`
	SizeMB  float64  `json:"size_mb"`
	Current bool     `json:"current"`
	Files   []string `json:"files"`
}

// safeVersion accepts only the characters that appear in real version strings.
// Besides keeping the value to a single path segment (no separators or parent
// references) so it cannot traverse outside its tool directory, it must reject
// shell metacharacters: the version is written verbatim into a tool's setup.sh
// as VERSION="..." and that script is later executed with install privilege.
func safeVersion(v string) bool {
	if v == "" || len(v) > 64 || v == "." || v == ".." || strings.Contains(v, "..") {
		return false
	}
	for _, c := range v {
		switch {
		case c >= '0' && c <= '9',
			c >= 'a' && c <= 'z',
			c >= 'A' && c <= 'Z',
			c == '.', c == '-', c == '_', c == '+':
			// allowed
		default:
			return false
		}
	}
	return true
}

func (s *Server) handleToolVersions(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}
	baseDir := filepath.Join(s.PrebuiltDir, devToolsDir, t.ID)
	dirEntries, err := os.ReadDir(baseDir)
	if err != nil {
		jsonOK(w, map[string]any{"versions": []any{}})
		return
	}
	var versions []ToolVersion
	for _, e := range dirEntries {
		if !e.IsDir() {
			continue
		}
		verDir := filepath.Join(baseDir, e.Name())
		var totalBytes int64
		var files []string
		filepath.Walk(verDir, func(p string, fi os.FileInfo, werr error) error { //nolint:errcheck
			if werr != nil || fi.IsDir() {
				return nil
			}
			totalBytes += fi.Size()
			files = append(files, fi.Name())
			return nil
		})
		sizeMB := float64(int(float64(totalBytes)/1024/1024*10)) / 10
		versions = append(versions, ToolVersion{
			Version: e.Name(),
			SizeMB:  sizeMB,
			Current: e.Name() == t.Version,
			Files:   files,
		})
	}
	sort.Slice(versions, func(i, j int) bool {
		return versions[i].Version > versions[j].Version
	})
	if versions == nil {
		versions = []ToolVersion{}
	}
	jsonOK(w, map[string]any{"versions": versions})
}

func (s *Server) handleDeleteVersion(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ver := chi.URLParam(r, "ver")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}
	if !safeVersion(ver) {
		jsonErr(w, "invalid version", 400)
		return
	}
	if ver == t.Version {
		jsonErr(w, "cannot delete the current version — switch to another version first", 400)
		return
	}
	verDir := filepath.Join(s.PrebuiltDir, devToolsDir, t.ID, ver)
	// Safety: path must stay inside prebuilt. Compare against the base plus a
	// separator so a sibling like "<prebuilt>-x" cannot satisfy the prefix.
	base := filepath.Clean(s.PrebuiltDir) + string(os.PathSeparator)
	if !strings.HasPrefix(filepath.Clean(verDir)+string(os.PathSeparator), base) {
		jsonErr(w, "invalid version path", 400)
		return
	}
	if _, err := os.Stat(verDir); os.IsNotExist(err) {
		jsonErr(w, "version not found", 404)
		return
	}
	if err := os.RemoveAll(verDir); err != nil {
		jsonErr(w, "delete failed: "+err.Error(), 500)
		return
	}
	jsonOK(w, map[string]any{"ok": true})
}

func (s *Server) handleUseVersion(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ver := chi.URLParam(r, "ver")
	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, errToolNotFound, 404)
		return
	}
	if !safeVersion(ver) {
		jsonErr(w, "invalid version", 400)
		return
	}
	verDir := filepath.Join(s.PrebuiltDir, devToolsDir, t.ID, ver)
	if _, err := os.Stat(verDir); os.IsNotExist(err) {
		jsonErr(w, "version not found in prebuilt", 404)
		return
	}
	devkitPath := findDevkitJSON(s.RepoRoot, t.ID)
	if devkitPath == "" {
		jsonErr(w, "devkit.json not found", 404)
		return
	}
	oldVer := t.Version
	if err := updateDevkitVersion(devkitPath, ver); err != nil {
		jsonErr(w, "could not update devkit.json: "+err.Error(), 500)
		return
	}
	setupPath := filepath.Join(filepath.Dir(devkitPath), "setup.sh")
	updateSetupVersion(setupPath, oldVer, ver) //nolint:errcheck
	if loaded, err := tools.Load(s.RepoRoot); err == nil {
		s.mu.Lock()
		s.allTools = loaded
		s.mu.Unlock()
		_updateCache.mu.Lock()
		_updateCache.checkedAt = time.Time{}
		_updateCache.mu.Unlock()
	}
	jsonOK(w, map[string]any{"ok": true, "version": ver})
}

func findDevkitJSON(repoRoot, toolID string) string {
	patterns := []string{
		filepath.Join(repoRoot, "tools", devToolsDir, toolID, devkitJSONFile),
		filepath.Join(repoRoot, "tools", "build-tools", toolID, devkitJSONFile),
		filepath.Join(repoRoot, "tools", "languages", toolID, devkitJSONFile),
	}
	for _, p := range patterns {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func updateDevkitVersion(path, version string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		return err
	}
	m["version"] = version
	out, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(out, '\n'), 0o600)
}

func updateSetupVersion(path, oldVer, newVer string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err // setup.sh may not exist
	}
	content := string(data)
	// Replace VERSION="old" with VERSION="new"
	updated := strings.ReplaceAll(content,
		fmt.Sprintf(`VERSION="%s"`, oldVer),
		fmt.Sprintf(`VERSION="%s"`, newVer))
	if updated == content {
		return fmt.Errorf("VERSION=%q not found in setup.sh", oldVer)
	}
	return os.WriteFile(path, []byte(updated), 0o600)
}
