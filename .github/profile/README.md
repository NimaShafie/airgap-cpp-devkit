# airgap-devkit

**Install, manage, and distribute developer tools in network-restricted environments. Runs entirely offline. Zero CDN dependencies. Built in Go.**

[![CI](https://github.com/airgap-devkit/devkit/actions/workflows/smoke-test.yml/badge.svg)](https://github.com/airgap-devkit/devkit/actions/workflows/smoke-test.yml)
[![Latest Release](https://img.shields.io/github/v/release/airgap-devkit/devkit?label=release)](https://github.com/airgap-devkit/devkit/releases/latest)
[![PyPI](https://img.shields.io/pypi/v/airgap-devkit?label=pypi)](https://pypi.org/project/airgap-devkit/)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](https://github.com/airgap-devkit/devkit/blob/main/LICENSE)

---

## What is airgap-devkit?

airgap-devkit is a self-contained developer toolkit manager for network-restricted and air-gapped environments. It ships as a single Go binary with an embedded HTMX web UI — no Python runtime, no Node, no CDN calls.

Bring it into a disconnected environment via `git clone` or `pip install`, and your team gets a local browser dashboard to browse, install, and uninstall developer tools. All tool archives are vendored in-repo or in the `prebuilt/` submodule. Nothing is fetched at install time.

| Capability | Details |
|---|---|
| **Tools** | Clang/LLVM · GCC · CMake · Python · .NET SDK · Conan · gRPC · GDB · lcov · VS Code · FileZilla · PuTTY · Notepad++ · SourceTree |
| **Interfaces** | Browser web UI / CLI installer / pip package |
| **Profiles** | `minimal` / `cpp-dev` / `devops` / `full` |
| **Output** | Install receipts · per-tool version tracking · SBOM (SPDX) |
| **CI/CD** | Jenkins and GitLab pipelines ship in-repo; headless installs via `--yes --profile` |
| **Platforms** | Windows 11 (Git Bash / MINGW64) · RHEL/Rocky 8, 9, 10 (Bash 4.x; baseline 9) |
| **Team config** | Fork `teams/` for custom branding, profiles, and tool selection |

---

## Why airgap-devkit?

- **Truly offline.** All tool archives are vendored in `prebuilt/`. No internet access required at install time or runtime.
- **No runtime dependency.** Single static Go binary. No Python, no Node, no JVM required on the target machine.
- **Web UI included.** Browser dashboard to browse, install, and uninstall every tool — no CLI required for day-to-day use.
- **pip-installable.** On connected machines, `pip install airgap-devkit` gets the binary and launches in seconds.
- **CI-native.** Jenkins and GitLab pipeline configs ship in the repo; structured exit codes for scripted installs.
- **Team-configurable.** Fork `teams/` to build a custom tool image with your own branding, profiles, and tool selections.
- **AGPL-licensed.** Free to use, study, and modify. Commercial licensing available for enterprise deployments.

---

## Quick start

**Via pip** (connected machine):

```bash
pip install airgap-devkit
airgap-devkit
```

**Via git** (air-gapped / no pip):

```bash
git clone https://github.com/airgap-devkit/devkit
cd devkit
git submodule update --init --recursive
bash launch.sh
```

Both open the **DevKit Manager** in your browser at `http://127.0.0.1:9090`. The git path works fully offline with zero runtime dependencies.

**Headless / CI install:**

```bash
bash install-cli.sh --yes --profile cpp-dev
```

---

## Repositories

| Repo | Description |
|---|---|
| [airgap-devkit/devkit](https://github.com/airgap-devkit/devkit) | Main — Go binary + HTMX web UI + CLI installer + pip package |
| [airgap-devkit/tools](https://github.com/airgap-devkit/tools) | Default tool manifests and install scripts |
| [airgap-devkit/teams](https://github.com/airgap-devkit/teams) | Forkable template for custom team tool images |
| [airgap-devkit/prebuilt](https://github.com/airgap-devkit/prebuilt) | Prebuilt binary archives |

---

## Links

- [Releases](https://github.com/airgap-devkit/devkit/releases)
- [Changelog](https://github.com/airgap-devkit/devkit/blob/main/CHANGELOG.md)
- [README / Documentation](https://github.com/airgap-devkit/devkit#readme)
- [PyPI package](https://pypi.org/project/airgap-devkit/)
- [Security policy](https://github.com/airgap-devkit/devkit/security)
- [License: AGPL-3.0-or-later](https://github.com/airgap-devkit/devkit/blob/main/LICENSE)
- Commercial licensing: nimzshafie@gmail.com
