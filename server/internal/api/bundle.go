package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/nimzshafie/airgap-devkit/server/internal/tools"
)

// PEP 508 distribution names and version specifiers must not begin with a dash,
// so a manifest value cannot be smuggled in as a pip option.
var (
	rePkgName    = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)
	rePkgVersion = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9.+!_-]*$`)
)

// execCommand is a seam over exec.Command so the pip/VS Code shell-outs can be
// exercised in tests without a real Python or `code` binary.
var execCommand = exec.Command

func validPkgSpec(name, version string) bool {
	if !rePkgName.MatchString(name) {
		return false
	}
	if version != "" && !strings.EqualFold(version, "various") && !rePkgVersion.MatchString(version) {
		return false
	}
	return true
}

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
		installed := vsCodeInstalledVersions()
		for _, p := range t.Packages {
			ps := PackageStatus{PackageItem: p}
			if p.ID != "" {
				if ver, ok := installed[strings.ToLower(p.ID)]; ok {
					ps.Installed = true
					ps.InstalledVersion = ver
				}
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
	out, err := execCommand(py, "-m", "pip", "list", "--format=json").Output()
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
	if !validPkgSpec(p.Name, p.Version) {
		sse.Send("✗ ERROR: invalid package name or version")
		sse.Done("failed")
		return
	}
	spec := p.Name
	if p.Version != "" && !strings.EqualFold(p.Version, "various") {
		spec = p.Name + "==" + p.Version
	}

	// Try vendored wheels first; fall back to regular pip install. The "--"
	// terminates option parsing so spec is always treated as a package.
	vendorDir := filepath.Join(prebuiltDir, "pip-vendor")
	var cmd *exec.Cmd
	if _, err := os.Stat(vendorDir); err == nil {
		sse.Send(fmt.Sprintf("==> Installing %s from local vendor...", spec))
		cmd = execCommand(py, "-m", "pip", "install",
			"--find-links="+vendorDir, "--no-index", "--quiet", "--", spec)
	} else {
		sse.Send(fmt.Sprintf("==> Installing %s ...", spec))
		cmd = execCommand(py, "-m", "pip", "install", "--quiet", "--", spec)
	}

	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send(errLinePrefix + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("✓ %s installed", p.Name))
	sse.Done("success")
}

func pipRemoveOne(sse *sseWriter, p *tools.PackageItem, prefix string) {
	py := pipPython(prefix)
	if !rePkgName.MatchString(p.Name) {
		sse.Send("✗ ERROR: invalid package name")
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("==> Removing %s ...", p.Name))
	cmd := execCommand(py, "-m", "pip", "uninstall", "-y", "--", p.Name)
	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send(errLinePrefix + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("✓ %s removed", p.Name))
	sse.Done("success")
}

// ── VS Code helpers ──────────────────────────────────────────────────────────

// vsCodeInstalledVersions returns a map of lowercase extension ID → installed
// version. --show-versions makes `code` print "publisher.name@version"; without
// it the version was unavailable and bundle status always reported "". An entry
// with no resolvable version maps to "".
func vsCodeInstalledVersions() map[string]string {
	out, err := execCommand("code", "--list-extensions", "--show-versions").Output()
	if err != nil {
		return map[string]string{}
	}
	m := map[string]string{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		id, ver := line, ""
		// Split on the LAST '@' — the version suffix. Extension IDs never contain
		// '@', so this is unambiguous.
		if idx := strings.LastIndex(line, "@"); idx != -1 {
			id, ver = line[:idx], line[idx+1:]
		}
		m[strings.ToLower(id)] = ver
	}
	return m
}

// resolveVsixPath locates a local .vsix for the package: first by the explicit
// File field, then by matching the extension ID (publisher.name → name-*.vsix)
// against files in dir. Returns "" when no local file is found.
func resolveVsixPath(dir string, p *tools.PackageItem) string {
	if p.File != "" {
		candidate := filepath.Join(dir, p.File)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	if p.ID == "" {
		return ""
	}
	parts := strings.Split(p.ID, ".")
	if len(parts) < 2 {
		return ""
	}
	namePrefix := strings.ToLower(parts[1]) + "-"
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		name := strings.ToLower(e.Name())
		if strings.HasPrefix(name, namePrefix) && strings.HasSuffix(name, ".vsix") {
			return filepath.Join(dir, e.Name())
		}
	}
	return ""
}

func vscodeInstallOne(sse *sseWriter, p *tools.PackageItem, prebuiltDir string) {
	sse.Send(fmt.Sprintf("==> Installing extension: %s", p.Name))

	// Prefer local .vsix file if present
	vsixDir := filepath.Join(prebuiltDir, devToolsDir, "vscode-extensions")
	vsixPath := resolveVsixPath(vsixDir, p)

	var cmd *exec.Cmd
	switch {
	case vsixPath != "":
		sse.Send("    Source: " + vsixPath)
		cmd = execCommand("code", "--install-extension", vsixPath, "--force")
	case p.ID != "":
		sse.Send("    Note: .vsix not found locally — using extension ID (requires internet)")
		cmd = execCommand("code", "--install-extension", p.ID, "--force")
	default:
		sse.Send(errLinePrefix + "no vsix file or extension ID available")
		sse.Done("failed")
		return
	}

	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send(errLinePrefix + err.Error())
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
	cmd := execCommand("code", "--uninstall-extension", p.ID)
	out, err := cmd.CombinedOutput()
	if len(out) > 0 {
		sse.Send(strings.TrimSpace(string(out)))
	}
	if err != nil {
		sse.Send(errLinePrefix + err.Error())
		sse.Done("failed")
		return
	}
	sse.Send(fmt.Sprintf("✓ %s uninstalled", p.Name))
	sse.Done("success")
}
