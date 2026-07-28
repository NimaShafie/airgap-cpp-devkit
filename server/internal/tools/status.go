package tools

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/nimzshafie/airgap-devkit/server/internal/timefmt"
)

// execCommand is a seam over exec.Command so the system-install probe can be
// tested without the real toolchain binaries present.
var execCommand = exec.Command

type Receipt struct {
	Exists      bool   `json:"exists"`
	Status      string `json:"status"`
	Version     string `json:"version"`
	Date        string `json:"date"`
	InstallPath string `json:"install_path"`
}

type ToolStatus struct {
	Tool
	Installed bool `json:"installed"`
	Available bool `json:"available"`
	// Source distinguishes how the tool was found: "devkit" when an
	// INSTALL_RECEIPT.txt under the prefix proves the devkit installed it,
	// "system" when it was only detected on the ambient PATH via check_cmd (not
	// managed by the devkit), and "" when not installed. Without this, a host
	// with a pre-existing toolchain makes /api/tools report tools as installed
	// that the devkit does not actually manage.
	Source          string  `json:"source"`
	Receipt         Receipt `json:"receipt"`
	UpdateAvailable bool    `json:"update_available"`
}

func GetReceipt(prefix, receiptName string) Receipt {
	clean := strings.ReplaceAll(receiptName, "/", string(os.PathSeparator))
	toolDir := filepath.Join(prefix, clean)

	// Prefer new name, fall back to legacy
	for _, name := range []string{"INSTALL_LOG.txt", "INSTALL_RECEIPT.txt"} {
		path := filepath.Join(toolDir, name)
		if r, ok := parseReceipt(path); ok {
			return r
		}
	}
	return Receipt{Status: "not_installed"}
}

func parseReceipt(path string) (Receipt, bool) {
	f, err := os.Open(path)
	if err != nil {
		return Receipt{}, false
	}
	defer f.Close()

	r := Receipt{Exists: true, Status: "not_installed"}
	hasInstalledAt := false

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		var key, val string
		ei := strings.Index(line, "=")
		ci := strings.Index(line, ":")
		if ei != -1 && (ci == -1 || ei < ci) {
			// '=' separator (receipt format: key=value)
			key = strings.ToLower(strings.TrimSpace(line[:ei]))
			val = strings.TrimSpace(line[ei+1:])
		} else if ci != -1 {
			// ':' separator (log format: Key: value)
			key = strings.ToLower(strings.TrimSpace(line[:ci]))
			val = strings.TrimSpace(line[ci+1:])
		} else {
			continue
		}
		key = strings.ReplaceAll(key, "-", "_")
		switch key {
		case "version":
			r.Version = val
		case "status":
			r.Status = val
		case "installed_at":
			r.Date = normaliseDate(val)
			hasInstalledAt = true
		case "date":
			r.Date = normaliseDate(val)
		case "install_path", "install_prefix":
			r.InstallPath = val
		}
	}
	if r.Status == "not_installed" && hasInstalledAt {
		r.Status = "success"
	}
	return r, true
}

func normaliseDate(raw string) string {
	return timefmt.Normalize(raw)
}

// probeSystemInstall runs check_cmd to detect a system-installed tool (no receipt).
// Returns the version string extracted from output, or "" if not found.
func probeSystemInstall(checkCmd, goos string) string {
	if checkCmd == "" {
		return ""
	}
	parts := strings.Fields(checkCmd)
	if len(parts) == 0 {
		return ""
	}
	var cmd *exec.Cmd
	if goos == "windows" {
		cmd = execCommand("cmd", append([]string{"/c"}, parts...)...)
	} else {
		cmd = execCommand(parts[0], parts[1:]...)
	}
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return extractVersion(string(out))
}

// extractVersion returns the first version-like token found in command output
// (e.g. "cmake version 4.2.3" → "4.2.3"), falling back to the truncated first
// non-empty line, or "" when the output is blank.
func extractVersion(out string) string {
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		for _, f := range strings.Fields(line) {
			if len(f) > 0 && f[0] >= '0' && f[0] <= '9' && strings.Contains(f, ".") {
				return f
			}
		}
		// Return truncated first line as fallback
		if len(line) > 60 {
			line = line[:60]
		}
		return line
	}
	return ""
}

func GetStatus(t Tool, prefix, currentOS string) ToolStatus {
	// Render upload timestamps consistently regardless of how they were stored;
	// t is a copy, so only the response is touched, never the on-disk manifest.
	t.UploadedAt = timefmt.Normalize(t.UploadedAt)
	receipt := GetReceipt(prefix, t.ReceiptName)
	installed := receipt.Status == "success"
	available := t.Platform == "both" || t.Platform == currentOS

	source := ""
	if installed {
		source = "devkit"
	}

	// If no receipt, probe system PATH via check_cmd
	if !installed && t.CheckCmd != "" {
		if ver := probeSystemInstall(t.CheckCmd, runtime.GOOS); ver != "" {
			installed = true
			source = "system"
			receipt = Receipt{
				Exists:  true,
				Status:  "success",
				Version: ver,
				Date:    "(system install)",
			}
		}
	}

	updateAvailable := false
	installedVer := strings.TrimSpace(receipt.Version)
	availVer := strings.TrimSpace(t.Version)
	if installed && installedVer != "" && availVer != "" && installedVer != availVer {
		updateAvailable = true
	}

	return ToolStatus{
		Tool:            t,
		Installed:       installed,
		Available:       available,
		Source:          source,
		Receipt:         receipt,
		UpdateAvailable: updateAvailable,
	}
}
