package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"embed"
	"encoding/pem"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"math/big"
	"net"
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
		toolsDir  = flag.String("tools", "", "path to tools/ directory (default: <repo>/tools)")
		prebuilt  = flag.String("prebuilt", "", "path to prebuilt/ directory (default: <repo>/prebuilt)")
		port      = flag.Int("port", 8080, "HTTP listen port")
		host      = flag.String("host", "127.0.0.1", "HTTP bind address")
		noBrowser = flag.Bool("no-browser", false, "don't open browser on startup")
		tlsFlag   = flag.Bool("tls", false, "enable HTTPS with an auto-generated self-signed certificate")
		skipSetup = flag.Bool("skip-setup", false, "mark setup complete so API is immediately usable (headless/CI installs)")
		showVer   = flag.Bool("version", false, "print the server version and exit")
	)
	flag.Parse()

	// --version is the first thing an operator or packaging script reaches for;
	// answer it before doing any startup work.
	if *showVer {
		fmt.Printf("airgap-devkit-server %s\n", api.AppVersion)
		return
	}

	currentOS := detectOS()
	repoRoot := resolvePaths(toolsDir, prebuilt)

	cfg := config.Load(repoRoot)
	if *skipSetup {
		cfg.SetupComplete = true
	}
	applyConfigDefaults(cfg, port, host)

	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("embed FS error: %v", err)
	}

	srv, err := api.New(repoRoot, *prebuilt, currentOS, cfg, sub)
	if err != nil {
		log.Fatalf("server init error: %v", err)
	}

	scheme := "http"
	if *tlsFlag {
		scheme = "https"
	}

	addr := fmt.Sprintf("%s:%d", *host, *port)
	baseURL := fmt.Sprintf("%s://%s:%d", scheme, *host, *port)
	browserURL := fmt.Sprintf("%s/auth/bootstrap?devkit_token=%s&next=/", baseURL, srv.Token())

	printBanner(baseURL, currentOS, srv.Token())

	mux := http.NewServeMux()
	mux.Handle("/static/", http.FileServer(http.FS(sub)))
	mux.Handle("/", srv.Routes())

	httpSrv := &http.Server{
		Addr:        addr,
		Handler:     mux,
		ReadTimeout: 30 * time.Second,
		IdleTimeout: 120 * time.Second,
		// WriteTimeout intentionally omitted — SSE streaming endpoints need
		// long-lived connections and would be broken by a hard write deadline.
	}

	if !*noBrowser {
		go openBrowser(browserURL)
	}

	log.Printf("Listening on %s://%s", scheme, addr)
	listenAndServe(httpSrv, repoRoot, *tlsFlag)
}

// resolvePaths derives repoRoot from the executable location and fills in the
// default tools/ and prebuilt/ directories when they were not set on the CLI.
func resolvePaths(toolsDir, prebuilt *string) string {
	exePath, _ := os.Executable()
	repoRoot, _ := filepath.Abs(filepath.Join(filepath.Dir(exePath), "..", ".."))
	if *toolsDir == "" {
		*toolsDir = filepath.Join(repoRoot, "tools")
	} else {
		repoRoot, _ = filepath.Abs(filepath.Join(*toolsDir, ".."))
	}
	if *prebuilt == "" {
		*prebuilt = filepath.Join(repoRoot, "prebuilt")
	}
	return repoRoot
}

// applyConfigDefaults applies the persisted host/port from cfg unless the user
// set them explicitly on the command line.
func applyConfigDefaults(cfg config.Config, port *int, host *string) {
	portExplicit, hostExplicit := false, false
	flag.Visit(func(f *flag.Flag) {
		switch f.Name {
		case "port":
			portExplicit = true
		case "host":
			hostExplicit = true
		}
	})
	if !portExplicit && cfg.Port != 0 {
		*port = cfg.Port
	}
	if !hostExplicit && cfg.Hostname != "" {
		*host = cfg.Hostname
	}
}

// printBanner writes the startup banner and auth token to stdout.
func printBanner(baseURL, currentOS, token string) {
	fmt.Printf("╔══════════════════════════════════════════╗\n")
	fmt.Printf("║  AirGap DevKit  v%-24s║\n", api.AppVersion)
	fmt.Printf("╠══════════════════════════════════════════╣\n")
	fmt.Printf("║  UI  →  %-33s║\n", baseURL)
	fmt.Printf("║  OS  →  %-33s║\n", currentOS)
	fmt.Printf("╚══════════════════════════════════════════╝\n")
	fmt.Printf("  Auth token: %s\n", token)
	fmt.Printf("  (saved to .devkit-token for API/CI use)\n\n")
}

// listenAndServe starts httpSrv over TLS or plain HTTP and blocks until exit.
func listenAndServe(httpSrv *http.Server, repoRoot string, useTLS bool) {
	if !useTLS {
		log.Fatal(httpSrv.ListenAndServe())
		return
	}
	certFile, keyFile, tlsErr := ensureTLSCert(repoRoot)
	if tlsErr != nil {
		log.Fatalf("TLS cert error: %v", tlsErr)
	}
	log.Fatal(httpSrv.ListenAndServeTLS(certFile, keyFile))
}

func ensureTLSCert(repoRoot string) (certFile, keyFile string, err error) {
	certFile = filepath.Join(repoRoot, "devkit-tls.crt")
	keyFile = filepath.Join(repoRoot, "devkit-tls.key")
	if _, e := os.Stat(certFile); e == nil {
		return certFile, keyFile, nil
	}

	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return "", "", err
	}

	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "devkit-local"},
		NotBefore:    time.Now().Add(-time.Minute),
		NotAfter:     time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{"localhost"},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
	}

	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return "", "", err
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return "", "", err
	}

	cf, err := os.OpenFile(certFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return "", "", err
	}
	encErr := pem.Encode(cf, &pem.Block{Type: "CERTIFICATE", Bytes: certDER})
	closeErr := cf.Close()
	if encErr != nil {
		return "", "", encErr
	}
	if closeErr != nil {
		return "", "", closeErr
	}

	kf, err := os.OpenFile(keyFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return "", "", err
	}
	encErr = pem.Encode(kf, &pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
	closeErr = kf.Close()
	if encErr != nil {
		return "", "", encErr
	}
	if closeErr != nil {
		return "", "", closeErr
	}

	log.Printf("TLS: generated self-signed certificate at %s", certFile)
	return certFile, keyFile, nil
}

func detectOS() string {
	if runtime.GOOS == "windows" {
		return "windows"
	}
	if ms := os.Getenv("MSYSTEM"); ms != "" {
		return "windows"
	}
	return "linux"
}

func openBrowser(url string) {
	time.Sleep(800 * time.Millisecond)

	switch runtime.GOOS {
	case "windows":
		_ = exec.Command("cmd", "/c", "start", "", url).Start()
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
