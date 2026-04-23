package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

// PackageStatus extends PackageItem with live install state.
type PackageStatus struct {
	tools.PackageItem
	Installed        bool   `json:"installed"`
	InstalledVersion string `json:"installed_version"`
}

// ── GET /api/tool/{id}/packages/status ──────────────────────────────────────

func (s *Server) handleBundlePackageStatus(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, ok := s.findTool(id)
	if !ok || len(t.Packages) == 0 {
		jsonErr(w, "tool not found or has no package list", 404)
		return
	}

	var statuses []PackageStatus

	switch t.BundleType {
	case "pip":
		installed := pipInstalledMap(s.currentPrefix())
		for _, p := range t.Packages {
			ps := PackageStatus{PackageItem: p}
			if iv, ok := installed[strings.ToLower(p.Name)]; ok {
				ps.Installed = true
				ps.InstalledVersion = iv
			}
			statuses = append(statuses, ps)
		}
	case "vscode":
		installed := vsCodeInstalledSet()
		for _, p := range t.Packages {
			ps := PackageStatus{PackageItem: p}
			if p.ID != "" {
				ps.Installed = installed[strings.ToLower(p.ID)]
			}
			statuses = append(statuses, ps)
		}
	default:
		jsonErr(w, "tool has no bundle_type defined", 400)
		return
	}

	jsonOK(w, map[string]any{"packages": statuses})
}

// ── GET /install-pkg/{id}/{pkg} (SSE) ───────────────────────────────────────

func (s *Server) handleInstallPackage(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	pkgName := chi.URLParam(r, "pkg")

	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, "tool not found", 404)
		return
	}

	// Find the package in the manifest
	var target *tools.PackageItem
	for i := range t.Packages {
		if strings.EqualFold(t.Packages[i].Name, pkgName) ||
			strings.EqualFold(t.Packages[i].ID, pkgName) {
			target = &t.Packages[i]
			break
		}
	}
	if target == nil {
		jsonErr(w, "package not found in manifest", 404)
		return
	}

	sse, ok2 := newSSE(w)
	if !ok2 {
		http.Error(w, "streaming not supported", 500)
		return
	}

	switch t.BundleType {
	case "pip":
		pipInstallOne(sse, target, s.currentPrefix(), s.PrebuiltDir)
	case "vscode":
		vscodeInstallOne(sse, target, s.PrebuiltDir)
	default:
		sse.Send("ERROR: unknown bundle_type")
		sse.Done("failed")
	}
}

// ── GET /remove-pkg/{id}/{pkg} (SSE) ────────────────────────────────────────

func (s *Server) handleRemovePackage(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	pkgName := chi.URLParam(r, "pkg")

	t, ok := s.findTool(id)
	if !ok {
		jsonErr(w, "tool not found", 404)
		return
	}

	var target *tools.PackageItem
	for i := range t.Packages {
		if strings.EqualFold(t.Packages[i].Name, pkgName) ||
			strings.EqualFold(t.Packages[i].ID, pkgName) {
			target = &t.Packages[i]
			break
		}
	}
	if target == nil {
		jsonErr(w, "package not found in manifest", 404)
		return
	}

	sse, ok2 := newSSE(w)
	if !ok2 {
		http.Error(w, "streaming not supported", 500)
		return
	}

	switch t.BundleType {
	case "pip":
		pipRemoveOne(sse, target, s.currentPrefix())
	case "vscode":
		vscodeRemoveOne(sse, target)
	default:
		sse.Send("ERROR: unknown bundle_type")
		sse.Done("failed")
	}
}

// ── pip helpers ──────────────────────────────────────────────────────────────

// pipPython returns the best Python executable: devkit prefix first, then PATH.
func pipPython(prefix string) string {
	candidates := []string{}
	if runtime.GOOS == "windows" {
		candidates = append(candidates,
			filepath.Join(prefix, "python", "python.exe"),
			"python.exe", "python",
		)
	} else {
		candidates = append(candidates,
			filepath.Join(prefix, "python", "bin", "python3"),
			filepath.Join(prefix, "python", "bin", "python"),
			"python3", "python",
		)
	}
	for _, c := range candidates {
		if p, err := exec.LookPath(c); err == nil {
			return p
		}
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	return "python"
}

// pipInstalledMap returns a map of lowercase package name → installed version,
// using the same Python environment as pipInstallOne so results are consistent.
func pipInstalledMap(prefix string) map[string]string {
	py := pipPython(prefix)
	out, err := exec.Command(py, "-m", "pip", "list", "--format=json").Output()
	if err != nil {
		return map[string]string{}
	}
	var pkgs []struct {
		Name    string `json:"name"`
		Version string `json:"version"`
	}
	if json.Unmarshal(out, &pkgs) != nil {
		return map[string]string{}
	}
	m := make(map[string]string, len(pkgs))
	for _, p := range pkgs {
		m[strings.ToLower(p.Name)] = p.Version
	}
	return m
}

func pipInstallOne(sse *sseWriter, p *tools.PackageItem, prefix, prebuiltDir string) {
	py := pipPython(prefix)
	spec := p.Name
	if p.Version != "" && !strings.EqualFold(p.Version, "various") {
		spec = p.Name + "==" + p.Version
	}

	// Try vendored wheels first; fall back to regular pip install
	vendorDir := filepath.Join(prebuiltDir, "pip-vendor")
	var cmd *exec.Cmd
	if _, err := os.Stat(vendorDir); err == nil {
		sse.Send(fmt.Sprintf("==> Installing %s from local vendor...", spec))
		cmd = exec.Command(py, "-m", "pip", "install", spec,
			"--find-links="+vendorDir, "--no-index", "--quiet")
	} else {
		sse.Send(fmt.Sprintf("==> Installing %s ...", spec))
		cmd = exec.Command(py, "-m", "pip", "install", spec, "--quiet")
	}

	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send("✗ ERROR: " + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("✓ %s installed", p.Name))
	sse.Done("success")
}

func pipRemoveOne(sse *sseWriter, p *tools.PackageItem, prefix string) {
	py := pipPython(prefix)
	sse.Send(fmt.Sprintf("==> Removing %s ...", p.Name))
	cmd := exec.Command(py, "-m", "pip", "uninstall", "-y", p.Name)
	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send("✗ ERROR: " + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("✓ %s removed", p.Name))
	sse.Done("success")
}

// ── VS Code helpers ──────────────────────────────────────────────────────────

// vsCodeInstalledSet returns a set of lowercase extension IDs that are installed.
func vsCodeInstalledSet() map[string]bool {
	out, err := exec.Command("code", "--list-extensions").Output()
	if err != nil {
		return map[string]bool{}
	}
	m := map[string]bool{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		// Strip @version suffix if --show-versions was used
		if idx := strings.Index(line, "@"); idx != -1 {
			line = line[:idx]
		}
		m[strings.ToLower(strings.TrimSpace(line))] = true
	}
	return m
}

func vscodeInstallOne(sse *sseWriter, p *tools.PackageItem, prebuiltDir string) {
	sse.Send(fmt.Sprintf("==> Installing extension: %s", p.Name))

	// Prefer local .vsix file if present
	vsixDir := filepath.Join(prebuiltDir, "dev-tools", "vscode-extensions")
	vsixPath := ""
	if p.File != "" {
		candidate := filepath.Join(vsixDir, p.File)
		if _, err := os.Stat(candidate); err == nil {
			vsixPath = candidate
		}
	}
	// Fallback: search by ID pattern (publisher.name-version.vsix)
	if vsixPath == "" && p.ID != "" {
		prefix := strings.ReplaceAll(strings.ToLower(p.ID), ".", ".") + "-"
		entries, _ := os.ReadDir(vsixDir)
		for _, e := range entries {
			if strings.HasPrefix(strings.ToLower(e.Name()), strings.ToLower(strings.Split(p.ID, ".")[1])+"-") &&
				strings.HasSuffix(e.Name(), ".vsix") {
				vsixPath = filepath.Join(vsixDir, e.Name())
				break
			}
		}
		_ = prefix
	}

	var cmd *exec.Cmd
	if vsixPath != "" {
		sse.Send("    Source: " + vsixPath)
		cmd = exec.Command("code", "--install-extension", vsixPath, "--force")
	} else if p.ID != "" {
		sse.Send("    Note: .vsix not found locally — using extension ID (requires internet)")
		cmd = exec.Command("code", "--install-extension", p.ID, "--force")
	} else {
		sse.Send("✗ ERROR: no vsix file or extension ID available")
		sse.Done("failed")
		return
	}

	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send("✗ ERROR: " + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("✓ %s installed", p.Name))
	sse.Done("success")
}

func vscodeRemoveOne(sse *sseWriter, p *tools.PackageItem) {
	if p.ID == "" {
		sse.Send("✗ ERROR: no extension ID defined — cannot uninstall")
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("==> Uninstalling extension: %s (%s)", p.Name, p.ID))
	cmd := exec.Command("code", "--uninstall-extension", p.ID)
	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send("✗ ERROR: " + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("✓ %s uninstalled", p.Name))
	sse.Done("success")
}
