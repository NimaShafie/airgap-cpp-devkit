package api

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
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
		// fallback: try 1.1.1.1
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
		tag, ver, dlURL, asset, err := fetchGitHubLatest(client, t.GithubRepo, assetMatch)
		if err != nil {
			continue
		}
		updates = append(updates, UpdateInfo{
			ToolID:         t.ID,
			ToolName:       t.Name,
			CurrentVersion: t.Version,
			LatestTag:      tag,
			LatestVersion:  ver,
			Available:      !strings.HasPrefix(tag, "v"+t.Version) && ver != t.Version,
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

func fetchGitHubLatest(client *http.Client, repo, assetMatch string) (tag, version, downloadURL, assetName string, err error) {
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
	// Clean version: strip leading "v", strip ".windows.N" suffix
	version = strings.TrimPrefix(tag, "v")
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
		jsonErr(w, "tool not found", 404)
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

	ns := checkNetwork()
	if !ns.Online {
		sse.Send("ERROR: No internet connection detected.")
		sse.Done("failed")
		return
	}

	sse.Send(fmt.Sprintf("Checking latest release for %s (%s)...", t.Name, t.GithubRepo))
	client := &http.Client{Timeout: 15 * time.Second}

	assetMatch := t.AssetMatch
	if assetMatch == "" {
		if s.OS == "windows" {
			assetMatch = "64-bit.exe"
		} else {
			assetMatch = "linux"
		}
	}

	tag, ver, dlURL, assetName, err := fetchGitHubLatest(client, t.GithubRepo, assetMatch)
	if err != nil {
		sse.Send("ERROR: " + err.Error())
		sse.Done("failed")
		return
	}

	sse.Send(fmt.Sprintf("Current version : %s", t.Version))
	sse.Send(fmt.Sprintf("Latest release  : %s (tag: %s)", ver, tag))

	if strings.HasPrefix(tag, "v"+t.Version) || ver == t.Version {
		sse.Send("Already at latest version — nothing to download.")
		sse.Done("success")
		return
	}

	sse.Send(fmt.Sprintf("Update available: %s → %s", t.Version, ver))
	sse.Send(fmt.Sprintf("Asset           : %s", assetName))
	sse.Send(fmt.Sprintf("URL             : %s", dlURL))

	// Destination under prebuilt/
	destDir := filepath.Join(s.PrebuiltDir, "dev-tools",
		strings.ReplaceAll(id, "/", string(os.PathSeparator)), ver)
	destFile := filepath.Join(destDir, assetName)

	if _, statErr := os.Stat(destFile); statErr == nil {
		sse.Send(fmt.Sprintf("File already cached: %s", destFile))
	} else {
		if err := os.MkdirAll(destDir, 0o755); err != nil {
			sse.Send("ERROR: cannot create directory: " + err.Error())
			sse.Done("failed")
			return
		}

		sse.Send("Downloading...")
		dlClient := &http.Client{Timeout: 20 * time.Minute}
		dlResp, dlErr := dlClient.Get(dlURL)
		if dlErr != nil {
			sse.Send("ERROR: download failed: " + dlErr.Error())
			sse.Done("failed")
			return
		}
		defer dlResp.Body.Close()

		f, fErr := os.Create(destFile)
		if fErr != nil {
			sse.Send("ERROR: cannot write file: " + fErr.Error())
			sse.Done("failed")
			return
		}
		written, cpErr := io.Copy(f, dlResp.Body)
		f.Close()
		if cpErr != nil {
			os.Remove(destFile)
			sse.Send("ERROR: download incomplete: " + cpErr.Error())
			sse.Done("failed")
			return
		}
		sse.Send(fmt.Sprintf("Downloaded %.1f MB → %s", float64(written)/1024/1024, destFile))
	}

	// Update devkit.json version
	devkitPath := findDevkitJSON(s.RepoRoot, id)
	if devkitPath != "" {
		if err := updateDevkitVersion(devkitPath, ver); err != nil {
			sse.Send(fmt.Sprintf("WARNING: could not update devkit.json: %v", err))
		} else {
			sse.Send(fmt.Sprintf("Updated devkit.json version → %s", ver))
		}
		// Update VERSION= in setup.sh next to devkit.json
		setupPath := filepath.Join(filepath.Dir(devkitPath), "setup.sh")
		if err := updateSetupVersion(setupPath, t.Version, ver); err != nil {
			sse.Send(fmt.Sprintf("WARNING: could not update setup.sh: %v", err))
		} else {
			sse.Send(fmt.Sprintf("Updated setup.sh VERSION → %s", ver))
		}
	}

	// Reload tool list
	if loaded, lErr := tools.Load(s.RepoRoot); lErr == nil {
		s.mu.Lock()
		s.allTools = loaded
		s.mu.Unlock()
		// Bust update cache
		_updateCache.mu.Lock()
		_updateCache.checkedAt = time.Time{}
		_updateCache.mu.Unlock()
		sse.Send("Tool registry refreshed.")
	}

	sse.Send(fmt.Sprintf("✓ %s %s ready — click Install to deploy.", t.Name, ver))
	sse.Done("success")
}

func findDevkitJSON(repoRoot, toolID string) string {
	patterns := []string{
		filepath.Join(repoRoot, "tools", "dev-tools", toolID, "devkit.json"),
		filepath.Join(repoRoot, "tools", "build-tools", toolID, "devkit.json"),
		filepath.Join(repoRoot, "tools", "languages", toolID, "devkit.json"),
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
	return os.WriteFile(path, append(out, '\n'), 0o644)
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
	return os.WriteFile(path, []byte(updated), 0o644)
}
