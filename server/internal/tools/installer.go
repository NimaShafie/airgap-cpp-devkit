package tools

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func FindBash() string {
	if runtime.GOOS != "windows" {
		return "bash"
	}
	// Skip WSL bash (System32); prefer Git for Windows bash
	pathEnv := os.Getenv("PATH")
	for _, dir := range strings.Split(pathEnv, ";") {
		dir = strings.TrimSpace(dir)
		if strings.Contains(strings.ToLower(dir), "system32") {
			continue
		}
		for _, name := range []string{"bash.exe", "bash"} {
			cand := filepath.Join(dir, name)
			if fi, err := os.Stat(cand); err == nil && !fi.IsDir() {
				return cand
			}
		}
	}
	for _, loc := range []string{
		`C:\Program Files\Git\bin\bash.exe`,
		`C:\Program Files\Git\usr\bin\bash.exe`,
	} {
		if fi, err := os.Stat(loc); err == nil && !fi.IsDir() {
			return loc
		}
	}
	return "bash"
}

func ToBashPath(p string) string {
	if runtime.GOOS != "windows" {
		return p
	}
	s := strings.ReplaceAll(p, `\`, "/")
	if len(s) >= 2 && s[1] == ':' {
		s = "/" + strings.ToLower(string(s[0])) + s[2:]
	}
	return s
}

func BuildEnv(t Tool, prefix, prebuiltDir, currentOS string) []string {
	toolPrefix := filepath.Join(prefix, strings.ReplaceAll(t.ReceiptName, "/", string(os.PathSeparator)))
	// setup.sh runs under bash (MINGW64 on Windows) — pass POSIX paths so tar/mkdir don't
	// misinterpret the drive letter (e.g. C:) as a network hostname.
	bashPrefix := ToBashPath(toolPrefix)
	bashPrebuilt := ToBashPath(prebuiltDir)
	env := os.Environ()
	env = append(env,
		"AIRGAP_OS="+currentOS,
		"INSTALL_PREFIX="+bashPrefix,
		"INSTALL_PREFIX_OVERRIDE="+bashPrefix,
		"PREBUILT_DIR="+bashPrebuilt,
	)
	return env
}

func RunInstall(bash, repoRoot string, t Tool, args []string, env []string, w io.Writer) int {
	setupPath := filepath.Join(repoRoot, filepath.FromSlash(t.Setup))
	// Defense in depth: discovery already refuses manifests whose setup escapes
	// the repo, but never hand bash a script resolving outside the tree even if a
	// malformed Tool reached this far.
	if rel, err := filepath.Rel(repoRoot, setupPath); err != nil || !withinRoot(rel) {
		fmt.Fprintf(w, "ERROR: refusing to run setup script outside the repository: %s\n", t.Setup)
		return 1
	}
	cmdArgs := append([]string{setupPath}, args...)
	cmd := exec.Command(bash, cmdArgs...)
	cmd.Dir = repoRoot
	cmd.Env = env
	cmd.Stdout = w
	cmd.Stderr = w

	fmt.Fprintf(w, "Installing %s %s...\n", t.Name, t.Version)
	if err := cmd.Run(); err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			return exit.ExitCode()
		}
		fmt.Fprintf(w, "data: ERROR: %v\n\n", err)
		return 1
	}
	return 0
}
