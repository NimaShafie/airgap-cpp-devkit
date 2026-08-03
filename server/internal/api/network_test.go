package api

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

const (
	ghRepo = "owner/repo"
	verNew = "3.29.0"
	verOld = "3.28.0"
)

// fakeRT is an http.RoundTripper returning a canned response for any request,
// so fetchGitHubLatest can be exercised without reaching GitHub.
type fakeRT struct {
	status int
	body   string
}

func (f fakeRT) RoundTrip(*http.Request) (*http.Response, error) {
	return &http.Response{
		StatusCode: f.status,
		Body:       io.NopCloser(strings.NewReader(f.body)),
		Header:     make(http.Header),
	}, nil
}

func TestFetchGitHubLatest(t *testing.T) {
	body := `{"tag_name":"v1.2.3","assets":[
		{"name":"tool-windows-64-bit.exe","browser_download_url":"https://x/win"},
		{"name":"tool-linux","browser_download_url":"https://x/linux"}]}`
	client := &http.Client{Transport: fakeRT{status: 200, body: body}}

	tag, version, dlURL, asset, err := fetchGitHubLatest(client, ghRepo, "linux", "v")
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if tag != "v1.2.3" || version != "1.2.3" || dlURL != "https://x/linux" || asset != "tool-linux" {
		t.Fatalf("parsed wrong: tag=%q ver=%q url=%q asset=%q", tag, version, dlURL, asset)
	}

	// Non-200 → error.
	bad := &http.Client{Transport: fakeRT{status: 404, body: ""}}
	if _, _, _, _, err := fetchGitHubLatest(bad, ghRepo, "linux", "v"); err == nil {
		t.Error("404 should error")
	}

	// No matching asset → error.
	noMatch := &http.Client{Transport: fakeRT{status: 200, body: `{"tag_name":"v1","assets":[]}`}}
	if _, _, _, _, err := fetchGitHubLatest(noMatch, ghRepo, "linux", "v"); err == nil {
		t.Error("missing asset should error")
	}
}

func TestSafeVersion(t *testing.T) {
	for _, v := range []string{"1.2.3", "2026-07-06", "v4"} {
		if !safeVersion(v) {
			t.Errorf("safeVersion(%q) = false, want true", v)
		}
	}
	// Reject path traversal and any shell metacharacter: the version is written
	// verbatim into a privileged setup.sh as VERSION="...".
	for _, v := range []string{
		"", ".", "..", "a/b", `a\b`, "1..2",
		`1.0"; id`, "1.0$(id)", "1.0`id`", "1.0;id", "1.0|id",
		"1.0 2.0", "1.0\n2.0", `1.0"`, "1.0&whoami",
	} {
		if safeVersion(v) {
			t.Errorf("safeVersion(%q) = true, want false", v)
		}
	}
}

func TestResolveAssetMatch(t *testing.T) {
	s := apiTestServer(t) // OS = linux
	if got := s.resolveAssetMatch(tools.Tool{}); got != "linux" {
		t.Errorf("default linux asset = %q", got)
	}
	if got := s.resolveAssetMatch(tools.Tool{AssetMatch: "custom.tar.gz"}); got != "custom.tar.gz" {
		t.Errorf("explicit asset match = %q", got)
	}
}

func TestHandleToolVersions(t *testing.T) {
	s := apiTestServer(t)
	pb := t.TempDir()
	s.PrebuiltDir = pb
	verDir := filepath.Join(pb, devToolsDir, toolCMakeID, verNew)
	if err := os.MkdirAll(verDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(verDir, "cmake.tar.gz"), []byte("data"), 0o600); err != nil {
		t.Fatal(err)
	}
	h := s.Routes()

	rec := authReq(t, h, http.MethodGet, pathToolPre+toolCMakeID+"/versions", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("versions: want 200, got %d", rec.Code)
	}
	var resp struct {
		Versions []struct {
			Version string `json:"version"`
		} `json:"versions"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Versions) != 1 || resp.Versions[0].Version != verNew {
		t.Fatalf("versions wrong: %+v", resp.Versions)
	}
}

func TestUpdateHistory(t *testing.T) {
	s := apiTestServer(t)
	s.appendUpdateHistory(UpdateHistoryEntry{
		ToolID: toolCMakeID, ToolName: "CMake",
		FromVersion: verOld, ToVersion: verNew,
		PerformedAt: "2026-07-06 05:40 UTC",
	})
	h := s.Routes()

	rec := authReq(t, h, http.MethodGet, "/api/update-history", nil)
	var resp struct {
		Entries []struct {
			ToolID string `json:"tool_id"`
		} `json:"entries"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Entries) != 1 || resp.Entries[0].ToolID != toolCMakeID {
		t.Fatalf("history not recorded: %+v", resp.Entries)
	}

	// A non-matching filter yields no entries.
	rec = authReq(t, h, http.MethodGet, "/api/update-history?tool=other", nil)
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode filtered: %v", err)
	}
	if len(resp.Entries) != 0 {
		t.Fatalf("filter should exclude: %+v", resp.Entries)
	}
}

func TestUpdateDevkitVersion(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, devkitJSONFile)
	if err := os.WriteFile(path, []byte(`{"id":"cmake","version":"3.28.0"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := updateDevkitVersion(path, verNew); err != nil {
		t.Fatalf("update: %v", err)
	}
	var m map[string]any
	data, _ := os.ReadFile(path)
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	if m["version"] != verNew {
		t.Fatalf("version not updated: %v", m["version"])
	}
	// Missing file → error.
	if err := updateDevkitVersion(filepath.Join(dir, "nope.json"), "1"); err == nil {
		t.Error("missing file should error")
	}
}

func TestUpdateSetupVersion(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "setup.sh")
	if err := os.WriteFile(path, []byte("#!/bin/bash\nVERSION=\"3.28.0\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := updateSetupVersion(path, verOld, verNew); err != nil {
		t.Fatalf("update setup: %v", err)
	}
	data, _ := os.ReadFile(path)
	if !strings.Contains(string(data), `VERSION="3.29.0"`) {
		t.Fatalf("setup version not updated: %s", data)
	}
	// Old version absent → error.
	if err := updateSetupVersion(path, "9.9.9", "1.0.0"); err == nil {
		t.Error("absent version should error")
	}
}

func TestFindDevkitJSON(t *testing.T) {
	repo := t.TempDir()
	toolDir := filepath.Join(repo, "tools", "languages", "python")
	if err := os.MkdirAll(toolDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(toolDir, devkitJSONFile), []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := findDevkitJSON(repo, "python"); got == "" {
		t.Error("expected to find devkit.json under tools/languages")
	}
	if got := findDevkitJSON(repo, "missing"); got != "" {
		t.Errorf("unexpected find: %q", got)
	}
}
