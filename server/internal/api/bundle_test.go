package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

const (
	bundleID      = "py-bundle"
	vsixFile      = "cpptools-1.2.3.vsix"
	pkgStatusPath = "/packages/status"
)

// fakeExec returns an execCommand replacement that re-invokes the test binary's
// TestHelperProcess, which emits the given stdout and exit code — letting the
// pip/VS Code shell-outs be exercised without real binaries.
func fakeExec(stdout string, exit int) func(string, ...string) *exec.Cmd {
	return func(name string, args ...string) *exec.Cmd {
		cs := append([]string{"-test.run=TestHelperProcess", "--", name}, args...)
		cmd := exec.Command(os.Args[0], cs...)
		cmd.Env = append(os.Environ(),
			"GO_WANT_HELPER_PROCESS=1",
			"HELPER_STDOUT="+stdout,
			"HELPER_EXIT="+strconv.Itoa(exit),
		)
		return cmd
	}
}

func swapExec(f func(string, ...string) *exec.Cmd) func() {
	prev := execCommand
	execCommand = f
	return func() { execCommand = prev }
}

// TestHelperProcess is not a real test: it is the child process spawned by
// fakeExec. It prints HELPER_STDOUT and exits with HELPER_EXIT.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("GO_WANT_HELPER_PROCESS") != "1" {
		return
	}
	fmt.Fprint(os.Stdout, os.Getenv("HELPER_STDOUT"))
	code, _ := strconv.Atoi(os.Getenv("HELPER_EXIT"))
	os.Exit(code)
}

func bundleServer(t *testing.T, bundleType string, pkgs []tools.PackageItem) http.Handler {
	s := apiTestServer(t)
	s.allTools = []tools.Tool{{
		ID: bundleID, Name: "Python Bundle", ReceiptName: bundleID,
		BundleType: bundleType, Packages: pkgs,
	}}
	return s.Routes()
}

func TestPipPython(t *testing.T) {
	if pipPython(t.TempDir()) == "" {
		t.Fatal("pipPython returned empty")
	}
}

func TestResolveVsixPath(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, vsixFile), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}

	// Match by extension ID (publisher.name → name-*.vsix).
	if got := resolveVsixPath(dir, &tools.PackageItem{ID: "ms-vscode.cpptools"}); got == "" {
		t.Error("expected a vsix match by ID prefix")
	}
	// Explicit File wins.
	if got := resolveVsixPath(dir, &tools.PackageItem{File: vsixFile}); !strings.HasSuffix(got, vsixFile) {
		t.Errorf("explicit File not matched: %q", got)
	}
	// No match.
	if got := resolveVsixPath(dir, &tools.PackageItem{ID: "other.nothere"}); got != "" {
		t.Errorf("unexpected match: %q", got)
	}
}

func TestPipInstalledMap(t *testing.T) {
	restore := swapExec(fakeExec(`[{"name":"Black","version":"24.1.0"},{"name":"flake8","version":"7.0.0"}]`, 0))
	m := pipInstalledMap(t.TempDir())
	restore()
	if m["black"] != "24.1.0" || m["flake8"] != "7.0.0" {
		t.Fatalf("pip map wrong: %+v", m)
	}

	// A failing pip call yields an empty map.
	restore = swapExec(fakeExec("", 1))
	defer restore()
	if len(pipInstalledMap(t.TempDir())) != 0 {
		t.Fatal("failed pip list should give empty map")
	}
}

func TestVsCodeInstalledVersions(t *testing.T) {
	defer swapExec(fakeExec("ms-python.python@2026.4.0\nms-vscode.cpptools@1.2.3\n", 0))()
	m := vsCodeInstalledVersions()
	if _, ok := m["ms-python.python"]; !ok {
		t.Fatalf("vscode map missing entry: %+v", m)
	}
	if m["ms-python.python"] != "2026.4.0" || m["ms-vscode.cpptools"] != "1.2.3" {
		t.Fatalf("vscode versions wrong: %+v", m)
	}
}

func TestBundlePackageStatusPip(t *testing.T) {
	defer swapExec(fakeExec(`[{"name":"black","version":"24.1.0"}]`, 0))()
	h := bundleServer(t, "pip", []tools.PackageItem{{Name: "black"}, {Name: "flake8"}})

	rec := authReq(t, h, http.MethodGet, pathToolPre+bundleID+pkgStatusPath, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d", rec.Code)
	}
	var resp struct {
		Packages []struct {
			Name             string `json:"name"`
			Installed        bool   `json:"installed"`
			InstalledVersion string `json:"installed_version"`
		} `json:"packages"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	var black, flake8 bool
	for _, p := range resp.Packages {
		if p.Name == "black" && p.Installed && p.InstalledVersion == "24.1.0" {
			black = true
		}
		if p.Name == "flake8" && !p.Installed {
			flake8 = true
		}
	}
	if !black || !flake8 {
		t.Fatalf("status not reconciled: %+v", resp.Packages)
	}
}

func TestBundlePackageStatusErrors(t *testing.T) {
	// vscode branch still resolves through the fake exec.
	defer swapExec(fakeExec("ms-python.python\n", 0))()
	h := bundleServer(t, "vscode", []tools.PackageItem{{Name: "Python", ID: "ms-python.python"}})
	if rec := authReq(t, h, http.MethodGet, pathToolPre+bundleID+pkgStatusPath, nil); rec.Code != http.StatusOK {
		t.Fatalf("vscode status: want 200, got %d", rec.Code)
	}

	// No bundle_type → 400.
	h = bundleServer(t, "", []tools.PackageItem{{Name: "x"}})
	if rec := authReq(t, h, http.MethodGet, pathToolPre+bundleID+pkgStatusPath, nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("no bundle_type: want 400, got %d", rec.Code)
	}
}

func TestInstallRemovePackage(t *testing.T) {
	defer swapExec(fakeExec("Successfully installed black-24.1.0", 0))()
	h := bundleServer(t, "pip", []tools.PackageItem{{Name: "black"}})

	rec := authReq(t, h, http.MethodGet, "/install-pkg/"+bundleID+"/black", nil)
	if !strings.Contains(rec.Body.String(), "installed") {
		t.Fatalf("install output missing success: %q", rec.Body.String())
	}

	rec = authReq(t, h, http.MethodGet, "/remove-pkg/"+bundleID+"/black", nil)
	if !strings.Contains(rec.Body.String(), "removed") {
		t.Fatalf("remove output missing success: %q", rec.Body.String())
	}

	// Unknown package / tool → 404.
	if rec := authReq(t, h, http.MethodGet, "/install-pkg/"+bundleID+"/nosuch", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("unknown pkg: want 404, got %d", rec.Code)
	}
	if rec := authReq(t, h, http.MethodGet, "/install-pkg/nope/black", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("unknown tool: want 404, got %d", rec.Code)
	}
}
