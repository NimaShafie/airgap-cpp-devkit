package tools

import (
	"runtime"
	"strings"
	"testing"
)

// RunInstall must refuse a Tool whose resolved setup path lands outside the
// repo, even if such a Tool were somehow constructed past discovery's guard.
func TestRunInstallRefusesEscapingSetup(t *testing.T) {
	repo := t.TempDir()
	var out strings.Builder
	tool := Tool{Name: "Evil", Setup: "../../../../tmp/evil.sh"}
	rc := RunInstall("bash", repo, tool, nil, nil, &out)
	if rc == 0 {
		t.Fatal("RunInstall executed a setup script resolving outside the repo")
	}
	if !strings.Contains(out.String(), "refusing to run setup script outside the repository") {
		t.Fatalf("expected refusal message, got: %q", out.String())
	}
}

func TestToBashPath(t *testing.T) {
	// Paths without a drive letter are returned unchanged on every platform.
	for _, p := range []string{"/already/posix", "relative/dir"} {
		if got := ToBashPath(p); got != p {
			t.Errorf("ToBashPath(%q) = %q, want unchanged", p, got)
		}
	}
	// The drive-letter → /c/ rewrite only applies on Windows.
	if runtime.GOOS == "windows" {
		if got := ToBashPath(`C:\Users\x`); got != "/c/Users/x" {
			t.Errorf("ToBashPath drive letter = %q, want /c/Users/x", got)
		}
	}
}

func TestBuildEnv(t *testing.T) {
	tool := Tool{ID: "cmake", ReceiptName: "cmake"}
	env := BuildEnv(tool, "/opt/prefix", "/opt/prebuilt", "linux")

	var sawOS, sawPrefix, sawPrebuilt bool
	for _, e := range env {
		switch {
		case e == "AIRGAP_OS=linux":
			sawOS = true
		case strings.HasPrefix(e, "INSTALL_PREFIX=") && strings.Contains(e, "cmake"):
			sawPrefix = true
		case strings.HasPrefix(e, "PREBUILT_DIR="):
			sawPrebuilt = true
		}
	}
	if !sawOS || !sawPrefix || !sawPrebuilt {
		t.Fatalf("BuildEnv missing entries: os=%v prefix=%v prebuilt=%v", sawOS, sawPrefix, sawPrebuilt)
	}
}

func TestFindBash(t *testing.T) {
	if FindBash() == "" {
		t.Fatal("FindBash returned empty")
	}
}
