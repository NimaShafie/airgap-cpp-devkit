# airgap-cpp-devkit

**Author: Nima Shafie**

Air-gapped C++ developer toolkit for network-restricted environments. All tools
work offline. All dependencies are vendored in-repo or in the `prebuilt/` submodule.

**v0.2.0-alpha.1** — DevKit Manager is now a single pre-compiled Go binary.
No Python, no pip, no runtime dependencies required to run the UI.

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
bash launch.sh
```

The script selects the correct pre-compiled binary for your platform, starts the
server, and opens **`http://127.0.0.1:9090`** in your browser automatically.

> Keep the terminal open while you use the DevKit Manager — it is the server.
> Press **Ctrl+C** to stop.

The port is read from `devkit.config.json` (default `9090`). Pass `--port` to
override it for a single session.

### Step 3 — Install tools

1. Pick a **profile** for a one-click batch install:
   - **Minimal** — core tools only (clang, cmake, python, style-formatter)
   - **C++ Developer** — full C++ stack (clang, cmake, python, conan, VS Code extensions, sqlite, 7zip)
   - **DevOps** — infrastructure tools (cmake, python, conan, sqlite, 7zip)
   - **Full** — every available tool
2. Or click **Install** next to any individual tool.
3. Custom profiles can be created and saved from the Settings panel.

> **No binary?** Run `bash launch.sh --rebuild` to compile the server binary from
> the vendored Go source (requires Go 1.21+). Then rerun `bash launch.sh`.
>
> **No UI needed?** Use the CLI directly: `bash install-cli.sh`
> For headless/CI installs: `bash install-cli.sh --yes --profile cpp-dev`

---

## launch.sh Flags

```bash
bash launch.sh                      # launch UI and open browser
bash launch.sh --port 9090          # custom port (one session only)
bash launch.sh --host 0.0.0.0       # bind to all interfaces (LAN / remote access)
bash launch.sh --no-browser         # start server, don't open browser
bash launch.sh --cli                # skip UI, run install-cli.sh directly
bash launch.sh --rebuild            # rebuild binary from source, then launch
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
  "default_profile": "minimal"
}
```

Team identity (`team_name`, `org_name`, `devkit_name`, `theme_color`) can also be
pushed live via `POST /api/config` or through CI/CD pipelines without restarting.

---

## DevKit Manager Features

The manager is a self-contained Go binary with an embedded web UI. Features:

| Feature | Description |
|---------|-------------|
| **Tool dashboard** | Install/uninstall status per tool; one-click install and rebuild |
| **Profile installs** | Batch install via built-in or custom profiles |
| **Custom profiles** | Create, save, and delete named profiles (`profiles.json`) |
| **Team config** | Export (`GET /api/export`) and import (`POST /api/import`) full config snapshots |
| **Package upload** | Push `.zip` bundle archives to the server (`POST /packages/upload`) |
| **Install prefix** | View, override, or reset the install path without editing files |
| **Dashboard layout** | Reorder tool categories; changes persisted in `layout.json` |
| **Tool meta overrides** | Override display name, description, or icon per tool |
| **Version management** | Keep multiple installed versions per tool; switch active version |
| **Live install log** | SSE-streamed output per tool; log history browser |
| **Health checks** | `GET /api/health/tools` — verifies all installed tool binaries respond |
| **Network status** | `GET /api/network` — latency probe to detect accidental internet access |
| **Update checker** | `GET /api/updates` — compares pinned manifest versions against latest releases |

### API Endpoints (selected)

```
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
GET  /health                         — server liveness check
```

---

## CI/CD Integration

Pipeline files ship in the repo root and are configured via `.ci/`.

| File | Platform |
|------|----------|
| `Jenkinsfile` | Jenkins |
| `.gitlab-ci.yml` | GitLab CI/CD |
| `.ci/atlassian/jira-update.sh` | Jira issue updater |
| `.ci/atlassian/confluence-update.sh` | Confluence page writer |

Both pipelines implement the same logical stages:

```
Validate → Configure → Install → Server Operations → Smoke Tests → Atlassian
```

| Stage | What it does |
|-------|-------------|
| **Validate** | Checks all `devkit.json` and `manifest.json` files for syntax and required fields |
| **Configure** | Patches `devkit.config.json` with pipeline parameters (team, profile, port) |
| **Install** | Runs `install-cli.sh --yes --profile <PROFILE>` on Linux and/or Windows agents |
| **Server Operations** | Starts the server; pushes team identity; handles package upload, config import/export |
| **Smoke Tests** | Runs `tests/run-tests.sh` to verify all installed tools respond |
| **Atlassian** | Posts build result to a Jira issue and overwrites a Confluence status page |

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

See [`.ci/README.md`](.ci/README.md) for full setup instructions and
[`.ci/atlassian/README.md`](.ci/atlassian/README.md) for Atlassian configuration.

---

## Deployment Scenarios

### Base case — Pre-built binaries allowed

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive
bash launch.sh          # opens DevKit Manager
# or: bash install-cli.sh --yes --profile cpp-dev
```

### Worst case — Binaries not permitted, source only

Skip the submodule. Both the DevKit Manager and `install-cli.sh` detect that
`prebuilt/` is absent and fall back to building all tools from vendored source.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
# Do NOT run: git submodule update --init --recursive
bash launch.sh          # opens DevKit Manager
# or: bash install-cli.sh
```

> **Server binary** — if `prebuilt/bin/` is absent, run
> `bash launch.sh --rebuild` once to compile the Go server from `server/`.

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
| [`tools/toolchains/clang/style-formatter/`](tools/toolchains/clang/style-formatter/README.md) | LLVM C++ style enforcement via Git pre-commit hook | Yes |
| [`tools/toolchains/clang/source-build/`](tools/toolchains/clang/source-build/README.md) | clang-format + clang-tidy from LLVM 22.1.3; prebuilt or source build | No |
| [`tools/build-tools/cmake/`](tools/build-tools/cmake/README.md) | CMake 4.3.1 — prebuilt or source build; RHEL 8 + Windows | No |
| [`tools/dev-tools/git-bundle/`](tools/dev-tools/git-bundle/README.md) | Transfers Git repos with nested submodules across air-gapped boundaries | Yes |
| [`tools/build-tools/lcov/`](tools/build-tools/lcov/README.md) | Code coverage via lcov 2.4 + gcov; vendored Perl deps included | No |
| [`tools/languages/python/`](tools/languages/python/README.md) | Portable Python 3.14.4 — Windows embeddable + Linux standalone | No |
| [`tools/languages/dotnet/`](tools/languages/dotnet/README.md) | Portable .NET 10 SDK 10.0.202 — Windows + Linux, no installer | No |
| [`tools/dev-tools/vscode-extensions/`](tools/dev-tools/vscode-extensions/README.md) | Offline VS Code extensions: C/C++, C++ TestMate, Python | No |
| [`tools/toolchains/gcc/windows/`](tools/toolchains/gcc/windows/README.md) | GCC 15.2.0 + MinGW-w64 13.0.0 UCRT for Windows | No |
| [`tools/dev-tools/7zip/`](tools/dev-tools/7zip/README.md) | 7-Zip 26.00 — admin + user install, Windows + Linux | No |
| [`tools/dev-tools/servy/`](tools/dev-tools/servy/README.md) | Servy 7.9 — Windows service manager (no-op on Linux) | No |
| [`tools/dev-tools/conan/`](tools/dev-tools/conan/README.md) | Conan 2.27.1 — C/C++ package manager, no Python required | No |
| [`tools/frameworks/grpc/`](tools/frameworks/grpc/README.md) | gRPC v1.80.0 for Windows — prebuilt or source build (~40 min) | No |
| [`tools/dev-tools/filezilla/`](tools/dev-tools/filezilla/README.md) | FileZilla 3.70.4 — FTP/SFTP client; Windows + Linux | No |
| [`tools/dev-tools/gdb/`](tools/dev-tools/gdb/README.md) | GDB 17.1 — Linux source build (~25 min) | No |
| [`tools/dev-tools/notepadpp/`](tools/dev-tools/notepadpp/README.md) | Notepad++ 8.9.3 — Windows only; portable zip or NSIS installer | No |
| [`tools/dev-tools/putty/`](tools/dev-tools/putty/README.md) | PuTTY 0.83 — Windows MSI + Linux source build | No |
| [`tools/dev-tools/sourcetree/`](tools/dev-tools/sourcetree/README.md) | SourceTree 3.4.30 — Git GUI client; Windows only | No |

---

## Prerequisites

| Platform | DevKit Manager | CLI installer |
|----------|----------------|--------------|
| Windows 11 | Git Bash (MINGW64) | Git Bash (MINGW64) |
| RHEL 8 | Bash 4.x | Bash 4.x |

The DevKit Manager binary (`prebuilt/bin/`) has no runtime dependencies.
Python is no longer required to run the UI. It is still needed to install
`tools/dev-tools/devkit-ui/` (the legacy FastAPI UI, if used), and is bundled
as an optional tool in `tools/languages/python/`.

To **rebuild** the server binary from source: Go 1.21+ is required.

---

## Development Setup

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive

# Launch DevKit Manager (uses prebuilt binary)
bash launch.sh

# Or rebuild the binary from source first
bash launch.sh --rebuild
```

### Useful commands

```bash
bash -n <script.sh> && echo "OK"          # syntax-check before running
bash launch.sh --no-browser               # dev mode, logs in terminal
curl -s http://127.0.0.1:9090/health
curl -s http://127.0.0.1:9090/api/tools
bash tests/run-tests.sh --verbose
bash install-cli.sh --yes --profile cpp-dev
bash scripts/generate-sbom.sh
bash scripts/status.sh                    # print install status of all tools
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
cp tools/style-formatter/toolchains/clang/style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 — Append .gitignore entries

```bash
cat tools/style-formatter/toolchains/clang/style-formatter/docs/gitignore-snippet.txt >> .gitignore
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
+-- TOOLS.md                               <- single-page tool inventory
+-- sbom.spdx.json                         <- root aggregate SBOM (SPDX 2.3)
+-- devkit.config.json                     <- server/UI configuration (team, port, theme)
+-- layout.json                            <- dashboard category/tool ordering
+-- launch.sh                              <- PRIMARY entry point (starts Go server)
+-- install-cli.sh                         <- CLI installer / fallback (Bash only)
+-- uninstall.sh                           <- removes all installed tools
+-- Jenkinsfile                            <- Jenkins declarative pipeline
+-- .gitlab-ci.yml                         <- GitLab CI/CD pipeline
+-- .gitmodules                            <- submodule pointers (prebuilt, tools)
|
+-- server/                                <- Go server source (DevKit Manager)
|   +-- main.go
|   +-- go.mod / go.sum
|   +-- internal/
|   |   +-- api/                           <- HTTP handlers, routes, SSE, bundling
|   |   +-- config/                        <- devkit.config.json loader
|   |   +-- tools/                         <- tool discovery and status
|   +-- web/                               <- embedded web UI (templates, assets)
|
+-- .ci/                                   <- CI/CD configuration and scripts
|   +-- README.md
|   +-- config.json                        <- shared CI defaults (profiles, Atlassian, etc.)
|   +-- jenkins/                           <- Jenkins setup docs
|   +-- gitlab/                            <- GitLab setup docs
|   +-- atlassian/
|       +-- jira-update.sh                 <- post build result to Jira issue
|       +-- confluence-update.sh           <- overwrite Confluence status page
|       +-- atlassian.config.json          <- config template (no secrets committed)
|
+-- scripts/
|   +-- install-mode.sh                    <- shared admin/user detection library
|   +-- setup-prebuilt-submodule.sh        <- initialize prebuilt submodule
|   +-- generate-sbom.sh                   <- regenerates all SBOM timestamps
|   +-- fetch-vscode-extensions.py         <- mirrors .vsix files for offline use
|   +-- status.sh                          <- prints install status of all tools
|
+-- tests/
|   +-- run-tests.sh                       <- post-install smoke tests
|
+-- packages/
|   +-- pip-packages/                      <- vendored pip wheels
|
+-- user-packages/                         <- user-managed packages (not tracked by git)
|
+-- prebuilt/                              <- SUBMODULE (separate repo, optional)
|   +-- bin/                               <- devkit-server binaries (Linux + Windows)
|   +-- build-tools/cmake/                 <- CMake 4.3.1
|   +-- dev-tools/7zip/                    <- 7-Zip 26.00
|   +-- dev-tools/conan/                   <- Conan 2.27.1
|   +-- dev-tools/filezilla/               <- FileZilla 3.70.4
|   +-- dev-tools/notepadpp/               <- Notepad++ 8.9.3
|   +-- dev-tools/putty/                   <- PuTTY 0.83
|   +-- dev-tools/servy/                   <- Servy 7.9
|   +-- dev-tools/sourcetree/              <- SourceTree 3.4.30
|   +-- frameworks/grpc/windows/1.80.0/    <- gRPC prebuilt
|   +-- languages/dotnet/10.0.202/         <- .NET 10 SDK
|   +-- languages/python/                  <- Python 3.14.4
|   +-- toolchains/clang/mingw/            <- llvm-mingw 20260407
|   +-- toolchains/clang/rhel8/            <- Clang 20.1.8 RHEL 8 RPMs
|   +-- toolchains/clang/source-build/     <- clang-format, clang-tidy, Ninja binaries
|   +-- toolchains/gcc/linux/              <- gcc-toolset-15 RHEL 8 RPMs
|   +-- toolchains/gcc/windows/            <- WinLibs GCC 15.2.0
|
+-- tools/                                 <- SUBMODULE (airgap-devkit/tools)
    +-- build-tools/cmake/
    +-- build-tools/lcov/
    +-- dev-tools/7zip/
    +-- dev-tools/conan/
    +-- dev-tools/filezilla/
    +-- dev-tools/gdb/
    +-- dev-tools/git-bundle/
    +-- dev-tools/notepadpp/
    +-- dev-tools/putty/
    +-- dev-tools/servy/
    +-- dev-tools/sourcetree/
    +-- dev-tools/vscode-extensions/
    +-- frameworks/grpc/
    +-- languages/dotnet/
    +-- languages/python/
    +-- toolchains/clang/source-build/
    +-- toolchains/clang/style-formatter/
    +-- toolchains/gcc/linux/
    +-- toolchains/gcc/windows/
```
