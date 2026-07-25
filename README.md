# airgap-cpp-devkit

**Author: Nima Shafie**

[![CI](https://github.com/airgap-devkit/devkit/actions/workflows/ci.yml/badge.svg)](https://github.com/airgap-devkit/devkit/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20RHEL%208-informational)](docs/DEPLOYMENT.md)
[![Air-gapped](https://img.shields.io/badge/air--gapped-offline--first-success)](docs/DEPLOYMENT.md)
[![Latest Release](https://badgen.net/github/release/airgap-devkit/devkit?label=release&color=blue)](https://github.com/airgap-devkit/devkit/releases/latest)
[![PyPI](https://img.shields.io/pypi/v/airgap-devkit?label=pypi&color=orange)](https://pypi.org/project/airgap-devkit/)

Air-gapped C++ developer toolkit for network-restricted environments. All tools
work offline. All dependencies are vendored in-repo or in the `prebuilt/` submodule.

**v1.3.62** — DevKit Manager is a single pre-compiled Go binary with
built-in session token authentication and optional HTTPS. No Python, no pip,
no runtime dependencies required to run the UI.

---

## Quick Start

### Step 1 — Clone the repo (first time only)

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive
```

### Step 2 — Start the DevKit Manager

**Windows (Git Bash) and Linux:**
```bash
bash scripts/launch.sh
```

The script selects the correct pre-compiled binary for your platform, starts the
server, and opens the browser automatically. On first run a session token is
generated and saved to `.devkit-token`; the browser is authenticated
automatically via a one-time bootstrap redirect.

> Keep the terminal open while you use the DevKit Manager — it is the server.
> Press **Ctrl+C** to stop.

The port is read from `devkit.config.json` (default `9090`). Pass `--port` to
override it for a single session.

### Step 3 — Install tools

1. Pick a **profile** for a one-click batch install:
   - **Minimal** — core tools only (clang, cmake, python, style-formatter)
   - **C++ Developer** — full C++ stack (clang, cmake, python, conan, VS Code extensions, sqlite)
   - **DevOps** — infrastructure tools (cmake, python, conan, sqlite)
   - **Full** — every available tool
2. Or click **Install** next to any individual tool.
3. Custom profiles can be created and saved from the Settings panel.

> **No binary?** Run `bash scripts/launch.sh --rebuild` to compile the server binary from
> the vendored Go source (requires Go 1.21+). Then rerun `bash scripts/launch.sh`.
>
> **No UI needed?** Use the CLI directly: `bash scripts/internal/install-cli.sh`
> For headless/CI installs: `bash scripts/internal/install-cli.sh --yes --profile cpp-dev`

> **Deploying for a team or a locked-down laptop?** See **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)**
> for the two supported models: an admin hosting one shared server for the whole
> team (`bash scripts/serve.sh`), or per-user no-admin local installs
> (`bash scripts/launch.sh`).

---

## scripts/launch.sh Flags

```bash
bash scripts/launch.sh                      # launch UI and open browser
bash scripts/launch.sh --port 9090          # custom port (one session only)
bash scripts/launch.sh --host 0.0.0.0       # bind to all interfaces (LAN / remote access)
bash scripts/launch.sh --no-browser         # start server, don't open browser
bash scripts/launch.sh --tls                # enable HTTPS with a self-signed certificate
bash scripts/launch.sh --cli                # skip UI, run scripts/internal/install-cli.sh directly
bash scripts/launch.sh --rebuild            # rebuild binary from source, then launch
```

---

## Configuration

`devkit.config.json` at the repo root controls the server and UI. It is read at
startup; changes take effect on next launch.

```json
{
  "team_name":       "My Team",
  "org_name":        "",
  "devkit_name":     "AirGap DevKit",
  "theme_color":     "#2563eb",
  "dashboard_title": "Tool Dashboard",
  "hostname":        "127.0.0.1",
  "port":            9090,
  "default_profile": "minimal",
  "setup_complete":  true,
  "allow_egress":    false
}
```

`allow_egress: false` (default) keeps the server fully air-gapped — `/api/network` always returns `online: false` and `/api/updates` returns an empty list without probing the internet. Set to `true` only on machines with intentional internet access to enable the update checker and network latency probe.

Team identity (`team_name`, `org_name`, `devkit_name`, `theme_color`) can also be
pushed live via `POST /api/config` or through CI/CD pipelines without restarting.

---

## DevKit Manager Features

The manager is a self-contained Go binary with an embedded web UI. Features:

| Feature | Description |
|---------|-------------|
| **Token authentication** | Every request requires a session token (header, cookie, or query param). Token is auto-generated on first run and saved to `.devkit-token`. |
| **HTTPS / TLS** | Pass `--tls` to serve over HTTPS with an auto-generated self-signed certificate (`devkit-tls.crt` / `devkit-tls.key`). |
| **Tool dashboard** | Install/uninstall status per tool; one-click install and rebuild |
| **Profile installs** | Batch install via built-in or custom profiles |
| **Custom profiles** | Create, save, and delete named profiles (`profiles.json`) |
| **Team config** | Export (`GET /api/export`) and import (`POST /api/import`) full config snapshots |
| **Package upload** | Push `.zip` bundle archives to the server (`POST /packages/upload`); 256 MB total / 64 MB per-file limit enforced |
| **Install prefix** | View, override, or reset the install path without editing files |
| **Dashboard layout** | Reorder tool categories; changes persisted in `layout.json` |
| **Tool meta overrides** | Override display name, description, or icon per tool |
| **Version management** | Keep multiple installed versions per tool; switch active version |
| **Live install log** | SSE-streamed output per tool; log history browser |
| **Health checks** | `GET /api/health/tools` — verifies all installed tool binaries respond |
| **Network status** | `GET /api/network` — returns `online: false` unless `allow_egress: true` is set in `devkit.config.json` |
| **Update checker** | `GET /api/updates` — compares pinned manifest versions against GitHub releases; requires `allow_egress: true` |

### Authentication

All API requests (except `GET /health` and static assets) require the session
token. Pass it via any of:

```bash
# Header (recommended for scripts/CI)
curl -H "X-DevKit-Token: <token>" http://127.0.0.1:9090/api/tools

# Cookie (set automatically by the browser after the bootstrap redirect)

# Query param (used internally by the bootstrap redirect)
curl "http://127.0.0.1:9090/api/tools?devkit_token=<token>"
```

The token is printed to the terminal on startup and saved to `.devkit-token`
in the repo root (readable by the current user only).

### API Endpoints (selected)

```
GET  /health                         — server liveness check (no token required)
GET  /auth/bootstrap                 — exchange URL token for session cookie, redirect to UI

# Tool install/uninstall actions — respond with SSE (text/event-stream) live output
GET  /install/<id>                   — install a tool (streams progress)
GET  /uninstall/<id>                 — uninstall a tool (streams progress)
GET  /check/<id>                     — run the tool's check_cmd (streams output)
GET  /versions/<id>                  — show installed version info
GET  /logs/<id>                      — stream the last install log
GET  /install-pkg/<id>               — install a package bundle (streams progress)
GET  /remove-pkg/<id>                — remove a package bundle (streams progress)
GET  /install-profile/<name>         — install all tools in a profile (streams progress)
GET  /download-update/<id>           — download a tool update

# Metadata and configuration
GET  /api/tools                      — full tool list with install status
GET  /api/tool/{id}                  — single tool detail
GET  /api/health/tools               — binary health check for all installed tools
GET  /api/network                    — network connectivity probe
GET  /api/updates                    — pending version updates
GET  /api/export                     — export team config as JSON
POST /api/import                     — import team config
POST /api/config                     — update team identity live
GET  /api/profiles                   — list profiles
POST /api/profiles                   — create/update a profile
DELETE /api/profiles/{id}            — delete a profile
POST /packages/upload                — upload a .zip package bundle
GET  /api/prefix                     — current install prefix
POST /api/prefix                     — override install prefix
DELETE /api/prefix                   — reset to auto-detected prefix
GET  /api/layout                     — current dashboard layout
POST /api/layout                     — save layout
DELETE /api/layout                   — reset to defaults
```

> **First-run setup:** the server redirects `/api/*` to `/setup` when `devkit.config.json` exists but has `"setup_complete": false`. The repo ships a default `devkit.config.json` with `"setup_complete": true` so new installs skip the wizard. For headless/CI use, verify that `setup_complete` is `true` in your config file before hitting the API.

---

## CI/CD Integration

Pipeline files ship in the repo root and delegate to `ci/`.

| File | Platform |
|------|----------|
| `Jenkinsfile` | Jenkins |
| `.gitlab-ci.yml` | GitLab CI/CD |
| `ci/atlassian/jira-update.sh` | Jira issue updater |
| `ci/atlassian/confluence-update.sh` | Confluence page writer |

Both pipelines implement the same logical stages:

```
Validate → Configure → Install → Server Operations → Smoke Tests → Atlassian
```

| Stage | What it does |
|-------|-------------|
| **Validate** | Checks all `devkit.json` and `manifest.json` files for syntax and required fields |
| **Configure** | Patches `devkit.config.json` with pipeline parameters (team, profile, port) |
| **Install** | Runs `scripts/internal/install-cli.sh --yes --profile <PROFILE>` on Linux and/or Windows agents |
| **Server Operations** | Starts the server; reads token from `.devkit-token`; pushes team identity; handles package upload, config import/export |
| **Smoke Tests** | Runs `tests/run-tests.sh` to verify all installed tools respond |
| **Atlassian** | Posts build result to a Jira issue and overwrites a Confluence status page |

> **CI note:** All DevKit Manager API calls from pipelines must include the
> `X-DevKit-Token` header. The token is available at `.devkit-token` after
> the server has started.

### Key Pipeline Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PROFILE` | `minimal` | `minimal`, `cpp-dev`, `devops`, `full` |
| `TARGET_OS` | `linux` | `linux`, `windows`, or `both` |
| `TEAM_NAME` | `My Team` | Written to devkit.config.json |
| `UPLOAD_PACKAGE` | `false` | Upload a `.zip` bundle to the running server |
| `EXPORT_TEAM_CONFIG` | `false` | Archive the current team config as a build artifact |
| `IMPORT_TEAM_CONFIG` | _(blank)_ | Raw JSON to POST to `/api/import` |
| `SAVE_PROFILE_JSON` | _(blank)_ | JSON to create/update a custom install profile |
| `ATLASSIAN_UPDATE` | `false` | Push build result to Jira + Confluence |

### Triggering via API

**Jenkins:**
```bash
curl -X POST "https://jenkins.example.com/job/airgap-devkit/buildWithParameters" \
  --user "user:api-token" \
  --data "PROFILE=cpp-dev&TEAM_NAME=Backend+Team&ATLASSIAN_UPDATE=true&JIRA_ISSUE_KEY=DEVKIT-42"
```

**GitLab:**
```bash
curl -X POST "https://gitlab.example.com/api/v4/projects/PROJECT_ID/trigger/pipeline" \
  --form "token=TRIGGER_TOKEN" --form "ref=main" \
  --form "variables[PROFILE]=cpp-dev" --form "variables[TEAM_NAME]=Backend Team"
```

See [`ci/README.md`](ci/README.md) for full setup instructions and
[`ci/atlassian/README.md`](ci/atlassian/README.md) for Atlassian configuration.

---

## Deployment Scenarios

### Base case — Pre-built binaries allowed

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive
bash scripts/launch.sh          # opens DevKit Manager
# or: bash scripts/internal/install-cli.sh --yes --profile cpp-dev
```

### Worst case — Binaries not permitted, source only

Skip the submodule. Both the DevKit Manager and `scripts/internal/install-cli.sh` detect that
`prebuilt/` is absent and fall back to building all tools from vendored source.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
# Do NOT run: git submodule update --init --recursive
bash scripts/launch.sh          # opens DevKit Manager
# or: bash scripts/internal/install-cli.sh
```

> **Server binary** — if `prebuilt/bin/` is absent, run
> `bash scripts/launch.sh --rebuild` once to compile the Go server from `server/`.

---

## Install Modes

Admin/root detection is automatic. System-wide is attempted first; per-user is used
if the current process cannot write to the system path.

| Mode | Windows | Linux |
|------|---------|-------|
| Admin (system-wide) | `C:\Program Files\airgap-cpp-devkit\<tool>\` | `/opt/airgap-cpp-devkit/<tool>/` |
| User (per-user) | `%LOCALAPPDATA%\airgap-cpp-devkit\<tool>\` | `~/.local/share/airgap-cpp-devkit/<tool>/` |

Each tool writes `INSTALL_RECEIPT.txt` on success. `<prefix>/env.sh` wires PATH
into `~/.bashrc`. To install system-wide on Windows, open Git Bash as Administrator.

The active prefix can be viewed or overridden from the DevKit Manager Settings panel,
or via the API (`GET /api/prefix`, `POST /api/prefix`).

---

## Tools

| Directory | Purpose | Required? |
|-----------|---------|-----------|
| [`tools/toolchains/llvm/style-formatter/`](tools/toolchains/llvm/style-formatter/README.md) | LLVM C++ style enforcement via Git pre-commit hook | Yes |
| [`tools/toolchains/clang/source-build/`](tools/toolchains/clang/source-build/README.md) | clang-format + clang-tidy from LLVM 22.1.3; prebuilt or source build | No |
| [`tools/build-tools/cmake/`](tools/build-tools/cmake/README.md) | CMake 4.3.1 — prebuilt or source build; RHEL 8 + Windows | No |
| [`tools/dev-tools/git-bundle/`](tools/dev-tools/git-bundle/README.md) | Transfers Git repos with nested submodules across air-gapped boundaries | Yes |
| [`tools/toolchains/lcov/`](tools/toolchains/lcov/) | Code coverage via lcov 2.5 + gcov; vendored Perl deps included | No |
| [`tools/languages/python/`](tools/languages/python/README.md) | Portable Python 3.14.4 — Windows embeddable + Linux standalone | No |
| [`tools/languages/dotnet/`](tools/languages/dotnet/README.md) | Portable .NET 10 SDK 10.0.202 — Windows + Linux, no installer | No |
| [`tools/dev-tools/vscode-extensions/`](tools/dev-tools/vscode-extensions/README.md) | Offline VS Code extensions: C/C++, C++ TestMate, Python | No |
| [`tools/toolchains/gcc/windows/`](tools/toolchains/gcc/windows/README.md) | GCC 15.2.0 + MinGW-w64 13.0.0 UCRT for Windows | No |
| [`tools/dev-tools/servy/`](tools/dev-tools/servy/README.md) | Servy 8.7 — Windows service manager (no-op on Linux) | No |
| [`tools/dev-tools/conan/`](tools/dev-tools/conan/README.md) | Conan 2.27.1 — C/C++ package manager, no Python required | No |
| [`tools/frameworks/grpc/`](tools/frameworks/grpc/README.md) | gRPC v1.83.0 — Windows prebuilt per MSVC toolset (VS 2019/2022/2026, Release or Debug) + Linux RHEL 8/9 (x86_64) | No |
| [`tools/lib/zlib/`](tools/lib/zlib/) | zlib 1.3.2 — gzip/DEFLATE compression library; vendored source, CMake build; Windows + Linux | No |
| [`tools/dev-tools/filezilla/`](tools/dev-tools/filezilla/README.md) | FileZilla 3.70.4 — FTP/SFTP client; Windows + Linux | No |
| [`tools/dev-tools/gdb/`](tools/dev-tools/gdb/README.md) | GDB 17.1 — Linux source build (~25 min) | No |
| [`tools/dev-tools/notepadpp/`](tools/dev-tools/notepadpp/README.md) | Notepad++ 8.9.7 — Windows only; portable zip or NSIS installer | No |
| [`tools/dev-tools/putty/`](tools/dev-tools/putty/README.md) | PuTTY 0.83 — Windows MSI + Linux source build | No |
| [`tools/dev-tools/sourcetree/`](tools/dev-tools/sourcetree/README.md) | SourceTree 3.4.30 — Git GUI client; Windows only | No |

---

## Prerequisites

| Platform | DevKit Manager | CLI installer |
|----------|----------------|--------------|
| Windows 11 | Git Bash (MINGW64) | Git Bash (MINGW64) |
| RHEL 8 | Bash 4.x | Bash 4.x |

The DevKit Manager binary (`prebuilt/bin/`) has no runtime dependencies.
Python is not required to run the UI. It is bundled as an optional installable
tool in `tools/languages/python/`.

To **rebuild** the server binary from source: Go 1.21+ is required.

---

## Development Setup

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive

# Launch DevKit Manager (uses prebuilt binary)
bash scripts/launch.sh

# Or rebuild the binary from source first
bash scripts/launch.sh --rebuild
```

### Useful commands

```bash
bash -n <script.sh> && echo "OK"                        # syntax-check before running
bash scripts/launch.sh --no-browser                     # dev mode, logs in terminal
bash scripts/launch.sh --tls --no-browser               # HTTPS mode

# Health check (no token required)
curl -s http://127.0.0.1:9090/health

# API calls — pass token via header
TOKEN=$(cat .devkit-token)
curl -s -H "X-DevKit-Token: $TOKEN" http://127.0.0.1:9090/api/tools

bash tests/run-tests.sh --verbose
bash scripts/internal/install-cli.sh --yes --profile cpp-dev
bash scripts/internal/generate-sbom.sh
bash scripts/internal/status.sh                                   # print install status of all tools
bash scripts/internal/pkg.sh list                                 # list all bundled tools and versions
bash scripts/internal/pkg.sh set-version cmake 3.31.0
```

---

## Deploying to Production Repositories

> **Optional.** Only needed if you want to enforce LLVM C++ style in another
> repository using this devkit as a submodule.

The formatter lives as a submodule in each production repo. Developers only
ever run `bash setup.sh`.

### Step 1 — Add the submodule (once per repo)

```bash
cd your-cpp-project/

git submodule add \
    <airgap-cpp-devkit-repo-url> \
    tools/style-formatter

git submodule update --init --recursive
```

### Step 2 — Copy setup.sh into the repo root

```bash
cp tools/toolchains/llvm/style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 — Append .gitignore entries

```bash
cat tools/toolchains/llvm/style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### Step 4 — Commit and push

```bash
git add .gitmodules tools/style-formatter setup.sh .gitignore
git commit -m "chore: add LLVM C++ style enforcement"
git push
```

### What developers do after this (once per machine)

```bash
git clone <your-cpp-project-url>
cd your-cpp-project
bash setup.sh
```

Done. Every subsequent `git commit` enforces LLVM style.

---

## Design Principles

| Principle | How it is met |
|-----------|--------------|
| Air-gapped | All dependencies vendored in-repo or in `prebuilt/` submodule |
| Binary-restricted environments | Skip `prebuilt/`; build all tools from vendored source |
| No runtime dependencies | DevKit Manager is a single static Go binary |
| Admin + user install | Admin detection at runtime; system-wide or per-user paths |
| Install transparency | Install receipt + timestamped log file written on every bootstrap |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Integrity verification | SHA256 pinned in `manifest.json` for all vendored archives |
| Team/CI ready | Jenkins + GitLab pipelines; Jira + Confluence integration |

---

## Repository Structure

```
airgap-cpp-devkit/
+-- README.md                              <- you are here
+-- CHANGELOG.md
+-- CONTRIBUTING.md
+-- CODE_OF_CONDUCT.md
+-- SECURITY.md
+-- SUPPORT.md
+-- LICENSE
+-- sbom.spdx.json                         <- root aggregate SBOM (SPDX 2.3)
+-- layout.json                            <- dashboard category/tool ordering
+-- Jenkinsfile                            <- Jenkins declarative pipeline (thin)
+-- .gitlab-ci.yml                         <- GitLab CI/CD pipeline (thin)
+-- .gitmodules                            <- submodule pointers (prebuilt, tools)
|
+-- ci/                                    <- CI/CD scripts and platform configs
|   +-- build.sh                           <- build the Go server binary
|   +-- test.sh                            <- run manifest validation suite
|   +-- lint.sh                            <- syntax-check all shell scripts
|   +-- release.sh                         <- thin wrapper around scripts/internal/release.sh
|   +-- smoke.sh                           <- server health check (used by ci.yml)
|   +-- Dockerfile.rhel8-test              <- RHEL 8 / UBI 8.10 integration test image
|   +-- atlassian/
|   |   +-- jira-update.sh                 <- post build result to Jira issue
|   |   +-- confluence-update.sh           <- overwrite Confluence status page
|   |   +-- atlassian.config.json          <- config template (no secrets committed)
|   +-- jenkins/                           <- Jenkins setup docs
|   +-- gitlab/                            <- GitLab setup docs
|
+-- .github/
|   +-- workflows/
|   |   +-- ci.yml                         <- thin; calls ci/lint.sh, ci/test.sh, ci/smoke.sh
|   |   +-- smoke-test.yml                 <- weekly + manual install regression
|   |   +-- rhel8-test.yml                 <- RHEL 8 integration test
|   |   +-- build-llvm-rhel8.yml           <- builds Clang/LLVM for RHEL 8
|   +-- ISSUE_TEMPLATE/
|   +-- PULL_REQUEST_TEMPLATE.md
|   +-- CODEOWNERS
|   +-- dependabot.yml
|
+-- docs/
|   +-- assets/                            <- screenshots and diagrams
|   +-- TOOLS.md                           <- single-page tool inventory
|   +-- manual-install.md                  <- manual install guide
|
+-- examples/                              <- runnable config examples
|
+-- scripts/
|   +-- launch.sh                          <- PRIMARY entry point (starts Go server)
|   +-- internal/                          <- helper scripts (not run directly)
|   |   +-- install-cli.sh                <- CLI installer / headless installs
|   |   +-- uninstall.sh                  <- removes all installed tools
|   |   +-- release.sh                    <- version bump + build + PyPI upload
|   |   +-- generate-sbom.sh              <- regenerates all SBOM timestamps
|   |   +-- status.sh                     <- prints install status of all tools
|   |   +-- pkg.sh                        <- package management helper
|   |   +-- manual-install.sh             <- fallback installer (no UI)
|   |   +-- build-server.sh               <- builds Go binary from source
|   |   +-- install-mode.sh               <- shared admin/user detection library
|   |   +-- setup-prebuilt-submodule.sh   <- initialize prebuilt submodule
|   |   +-- download-prebuilt.sh          <- downloads/stages prebuilt binaries
|   |   +-- sign-binaries.sh              <- Authenticode + GPG binary signing
|   |   +-- verify-signatures.sh          <- verifies binary signatures
|   |   +-- virustotal-scan.sh            <- VirusTotal API v3 scan
|   |   +-- fetch-vscode-extensions.py    <- mirrors .vsix files for offline use
|
+-- tests/
|   +-- run-tests.sh                       <- post-install smoke tests
|   +-- validate-manifests.sh              <- validates devkit.json/manifest.json syntax
|   +-- check-installed-tools.sh           <- tests check_cmd for installed tools
|
+-- server/                                <- Go server source (DevKit Manager)
|   +-- main.go
|   +-- go.mod / go.sum
|   +-- internal/
|   |   +-- api/                           <- HTTP handlers, routes, SSE, bundling
|   |   |   +-- auth.go                    <- session token middleware
|   |   |   +-- version.go                 <- AppVersion constant
|   |   +-- config/                        <- devkit.config.json loader
|   |   +-- tools/                         <- tool discovery and status
|   +-- web/                               <- embedded web UI (templates, assets)
|
+-- packages/
|   +-- python/                            <- PyPI packaging wrapper
|   |   +-- pyproject.toml
|   |   +-- src/airgap_devkit/
|   +-- pip-packages/                      <- vendored pip wheels
|
+-- prebuilt/                              <- SUBMODULE (separate repo, optional)
|   +-- bin/                               <- devkit-server binaries (Linux + Windows)
|   +-- languages/python/                  <- Python 3.14.4
|   +-- toolchains/                        <- Clang, GCC, LLVM binaries
|
+-- tools/                                 <- SUBMODULE (airgap-devkit/tools)
    +-- build-tools/cmake/
    +-- dev-tools/
    +-- frameworks/grpc/
    +-- languages/
    +-- toolchains/
```

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the CLA, coding conventions, and PR checklist. Security vulnerabilities go to [SECURITY.md](SECURITY.md) — not to public issues.

---

## License

AGPL-3.0-or-later — see [LICENSE](LICENSE). A commercial license is available for use cases that can't accept AGPL terms; contact nimzshafie@gmail.com.

OS/distribution logos under [`server/web/static/img/`](server/web/static/img/) are from [Simple Icons](https://github.com/simple-icons/simple-icons) (CC0-1.0); see [docs/THIRD-PARTY-NOTICES.md](docs/THIRD-PARTY-NOTICES.md) for attributions.
