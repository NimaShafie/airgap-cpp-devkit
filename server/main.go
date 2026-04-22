package main

import (
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"

	"github.com/nimzshafie/airgap-devkit/server/internal/api"
	"github.com/nimzshafie/airgap-devkit/server/internal/config"
)

//go:embed web
var webFS embed.FS

func main() {
	var (
		toolsDir   = flag.String("tools", "", "path to tools/ directory (default: <repo>/tools)")
		prebuilt   = flag.String("prebuilt", "", "path to prebuilt/ directory (default: <repo>/prebuilt)")
		port       = flag.Int("port", 8080, "HTTP listen port")
		host       = flag.String("host", "127.0.0.1", "HTTP bind address")
		noBrowser  = flag.Bool("no-browser", false, "don't open browser on startup")
	)
	flag.Parse()

	// Resolve repo root from --tools path (strip trailing /tools).
	// Binary lives at prebuilt/bin/ so we derive root from --tools if given.
	currentOS := detectOS()

	// Default tool/prebuilt dirs relative to binary location (prebuilt/bin/)
	exePath, _ := os.Executable()
	exeDir := filepath.Dir(exePath)
	repoRoot := filepath.Join(exeDir, "..", "..")
	repoRoot, _ = filepath.Abs(repoRoot)

	if *toolsDir == "" {
		*toolsDir = filepath.Join(repoRoot, "tools")
	} else {
		// Derive repo root from --tools path
		repoRoot, _ = filepath.Abs(filepath.Join(*toolsDir, ".."))
	}
	if *prebuilt == "" {
		*prebuilt = filepath.Join(repoRoot, "prebuilt")
	}

	cfg := config.Load(repoRoot)

	if cfg.Port != 8080 && *port == 8080 {
		*port = cfg.Port
	}
	if cfg.Hostname != "127.0.0.1" && *host == "127.0.0.1" {
		*host = cfg.Hostname
	}

	// webFS is embedded at build time; the root is "web/".
	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("embed FS error: %v", err)
	}

	srv, err := api.New(repoRoot, *prebuilt, currentOS, cfg, sub)
	if err != nil {
		log.Fatalf("server init error: %v", err)
	}

	addr := fmt.Sprintf("%s:%d", *host, *port)
	url := fmt.Sprintf("http://%s:%d", *host, *port)

	fmt.Printf("╔══════════════════════════════════════════╗\n")
	fmt.Printf("║  AirGap DevKit  v%-24s║\n", api.AppVersion)
	fmt.Printf("╠══════════════════════════════════════════╣\n")
	fmt.Printf("║  UI  →  %-33s║\n", url)
	fmt.Printf("║  OS  →  %-33s║\n", currentOS)
	fmt.Printf("╚══════════════════════════════════════════╝\n")

	mux := http.NewServeMux()
	mux.Handle("/static/", http.FileServer(http.FS(sub)))
	mux.Handle("/", srv.Routes())

	if !*noBrowser {
		go openBrowser(url)
	}

	log.Printf("Listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

func detectOS() string {
	if runtime.GOOS == "windows" {
		return "windows"
	}
	// Also catch MINGW/MSYS environments via env
	if ms := os.Getenv("MSYSTEM"); ms != "" {
		return "windows"
	}
	return "linux"
}

func openBrowser(url string) {
	// Wait for the HTTP server to be ready before opening.
	time.Sleep(800 * time.Millisecond)

	switch runtime.GOOS {
	case "windows":
		// Try powershell first (works from MINGW64/Git Bash context),
		// fall back to cmd /c start.
		if err := exec.Command("powershell.exe", "-NoProfile", "-Command",
			"Start-Process", "'"+url+"'").Start(); err != nil {
			_ = exec.Command("cmd", "/c", "start", url).Start()
		}
	case "darwin":
		_ = exec.Command("open", url).Start()
	default:
		for _, opener := range []string{"xdg-open", "gnome-open", "x-www-browser"} {
			if _, err := exec.LookPath(opener); err == nil {
				_ = exec.Command(opener, url).Start()
				return
			}
		}
	}
}

