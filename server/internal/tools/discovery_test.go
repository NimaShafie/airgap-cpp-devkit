package tools

import (
	"os"
	"path/filepath"
	"testing"
)

const (
	checkBase = "base --version"
	checkNix  = "nix --version"
)

func TestResolvedCheckCmd(t *testing.T) {
	tool := Tool{
		CheckCmd:        checkBase,
		CheckCmdWindows: "win --version",
		CheckCmdLinux:   checkNix,
	}
	if got := tool.ResolvedCheckCmd("windows"); got != "win --version" {
		t.Errorf("windows check = %q", got)
	}
	if got := tool.ResolvedCheckCmd("linux"); got != checkNix {
		t.Errorf("linux check = %q", got)
	}
	if got := tool.ResolvedCheckCmd("darwin"); got != checkNix {
		t.Errorf("darwin check = %q", got)
	}
	// A platform with no override falls back to the base command.
	if got := (Tool{CheckCmd: checkBase}).ResolvedCheckCmd("plan9"); got != checkBase {
		t.Errorf("fallback check = %q", got)
	}
}

func writeDevkitJSON(t *testing.T, dir, content string) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "devkit.json")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadToolFromFileDefaults(t *testing.T) {
	repo := t.TempDir()
	toolDir := filepath.Join(repo, "tools", "cmake")
	path := writeDevkitJSON(t, toolDir, `{"id":"cmake","name":"CMake","version":"3.29","setup":"setup.sh"}`)

	tool, ok := loadToolFromFile(repo, path, "builtin", map[string]bool{})
	if !ok {
		t.Fatal("valid devkit.json was rejected")
	}
	if tool.Platform != "both" || tool.Category != "Developer Tools" || tool.ReceiptName != "cmake" {
		t.Fatalf("defaults not applied: %+v", tool)
	}
	if tool.Source != "builtin" {
		t.Errorf("source = %q", tool.Source)
	}
	// Setup is rewritten relative to the repo root.
	if tool.Setup != "tools/cmake/setup.sh" {
		t.Errorf("setup path = %q", tool.Setup)
	}
}

// A manifest whose setup field climbs out of the repo root must be rejected,
// so the escaping path can never reach exec.Command in RunInstall.
func TestLoadToolFromFileRejectsSetupEscape(t *testing.T) {
	repo := t.TempDir()
	toolDir := filepath.Join(repo, "user-packages", "evil")
	path := writeDevkitJSON(t, toolDir,
		`{"id":"evil","name":"Evil","version":"1.0","setup":"../../../../../../tmp/evil.sh"}`)

	if _, ok := loadToolFromFile(repo, path, "user", map[string]bool{}); ok {
		t.Fatal("manifest with a setup path escaping the repo root was accepted")
	}
}

func TestLoadToolFromFileRejections(t *testing.T) {
	repo := t.TempDir()

	// Missing file.
	if _, ok := loadToolFromFile(repo, filepath.Join(repo, "nope.json"), "s", map[string]bool{}); ok {
		t.Error("missing file should be rejected")
	}

	// Invalid JSON.
	bad := writeDevkitJSON(t, filepath.Join(repo, "bad"), "{not json")
	if _, ok := loadToolFromFile(repo, bad, "s", map[string]bool{}); ok {
		t.Error("invalid JSON should be rejected")
	}

	// Missing id.
	noID := writeDevkitJSON(t, filepath.Join(repo, "noid"), `{"name":"x"}`)
	if _, ok := loadToolFromFile(repo, noID, "s", map[string]bool{}); ok {
		t.Error("missing id should be rejected")
	}

	// Hidden tool.
	hidden := writeDevkitJSON(t, filepath.Join(repo, "hid"), `{"id":"h","hidden":true}`)
	if _, ok := loadToolFromFile(repo, hidden, "s", map[string]bool{}); ok {
		t.Error("hidden tool should be skipped")
	}

	// Duplicate id (already seen).
	dup := writeDevkitJSON(t, filepath.Join(repo, "dup"), `{"id":"dup","name":"D"}`)
	seen := map[string]bool{"dup": true}
	if _, ok := loadToolFromFile(repo, dup, "s", seen); ok {
		t.Error("duplicate id should be skipped")
	}
}
