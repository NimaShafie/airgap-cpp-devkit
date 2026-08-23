# Changelog

All notable changes to airgap-cpp-devkit are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [1.3.68] — 2026-08-22

### Changed

- Updated the Go toolchain to 1.26.6 and rebuilt the `devkit-server` binaries.
- gRPC prebuilt installs now require a recorded per-part SHA-256 in the manifest and
  verify every part before the archive is reassembled and extracted. A missing
  manifest, missing python3, or absent checksum now aborts the install rather than
  proceeding.

### Internal

- Narrowed the secrets-scan allowlist to the specific synthetic constant used by the
  API unit tests, so a real credential added to that test file is still detected.


## [1.3.67] — 2026-08-02

### Added

#### Operator-supplied TLS certificate
- **`devkit-ui` accepts `--tls-cert` / `--tls-key`.** When both are given (together
  with `--tls`), the server uses that certificate instead of the auto-generated
  self-signed one — the supported way to run team mode behind a real CA-issued
  certificate. Supplying only one of the pair is rejected at startup.

### Fixed

#### Server input and packaging hardening
- **Tool version strings are validated against a strict allow-list.** `safeVersion`
  now accepts only the characters that occur in real versions (`[A-Za-z0-9._+-]`,
  max 64 chars, no `..`). The value is written into a tool's `setup.sh` and used to
  build filesystem paths, so keeping it to a known-safe character set is enforced in
  one place, with regression tests.
- **Embedded JSON escapes the U+2028 / U+2029 line separators.** The `toJSON`
  template helper now rewrites these to their `\u` form so JSON injected into a
  `<script>` block always stays inside its string literal on older JS engines.
- **`stage-binaries.sh` refuses to package a stale server binary.** After staging it
  reads the binary's embedded toolchain and `golang.org/x/text` versions via
  `go version -m` and fails the build if either is older than `server/go.mod`
  declares, so a published wheel can never lag the patched source.

#### Offline lcov genhtml HTML reports (F3)
- **`genhtml`'s HTML-report step now works fully offline.** genhtml/lcovutil load
  `DateTime`, `Date::Parse` and `Devel::StackTrace` unconditionally; none ship with
  a base Perl, so on an air-gapped host genhtml aborted at load and only
  line-coverage capture was available. `perl-vendor-lcov.zip` now bundles small
  pure-Perl compatibility modules (`DateTime.pm`, `Date/Parse.pm`,
  `Devel/StackTrace.pm`) implementing exactly the API lcov uses
  (`from_epoch`/`now`/`new`, `delta_days->in_units('days')`, `str2time`,
  `StackTrace->new->as_string`). No XS, no CPAN deps — identical on glibc and musl,
  no per-platform build.
- **Fixed a latent `Capture::Tiny` mispackaging.** The vendored module shipped as a
  flat `Tiny.pm`, so `use Capture::Tiny` could never resolve it (masked because
  genhtml died at `use DateTime` first). It is now correctly placed at
  `Capture/Tiny.pm`. The lcov manifest `perl-vendor` sha256 is updated to match.
- **`_verify_genhtml` now reports every missing Perl module at once.** Perl aborts
  at the first unresolved `use`, so the old check surfaced one module per install
  attempt. It now enumerates and probes the whole genhtml dependency set and lists
  them all in a single run.

### Added

#### Two-family Linux model — musl/Alpine support
- **Linux support is now expressed as two libc families** selected automatically from the host libc (glibc vs musl), so new distros require no new code.
- **glibc family** — one build against the glibc 2.28 floor (RHEL 8 / UBI 8) covers all glibc distros at or above it: RHEL/Rocky 8/9/10, Debian 10+, Ubuntu 20.04+, openSUSE/SLES 15+, Arch, Fedora. Native rhel9/rhel10 LLVM variants remain preferred when the host matches.
- **musl family (new)** — static musl builds added for Alpine 3.21+: LLVM is built static-libstdc++ on Alpine; sqlite3 is a fully-static musl binary; python uses the python-build-standalone musl tarball (python 3.14.6).
- **sqlite3** now ships a static per-libc binary (glibc-floor dynamic + fully-static musl). RHEL/Rocky falls back to the distro-native RPM per major (el8/el9/el10) as before.
- **New helpers** in `tools/lib/devkit-install.sh`: `devkit_libc`, `devkit_distro_id`, `devkit_linux_family`, `devkit_linux_tag_fallbacks`.
- **CI** (`linux-integration.yml`) extended to a five-distro matrix: RHEL/Rocky 8/9/10 (UBI), Debian 12 (apt), Alpine 3.21 (apk/musl). push/PR runs rhel-9 + debian-12; the weekly schedule runs all five. New Dockerfiles: `ci/Dockerfile.debian-test`, `ci/Dockerfile.alpine-test`. `build-llvm-linux.yml` gained an Alpine/musl leg.

### Changed

#### Linux support — RHEL/Rocky 9 & 10 added; baseline moved to 9
- **Support matrix is now RHEL / Rocky 8, 9 and 10** (previously RHEL 8 only), with
  **9 as the documented baseline**. glibc floors: 8 → 2.28, 9 → 2.34, 10 → 2.39.
- **Per-distro binary variants.** `tools/lib/devkit-install.sh` gained
  `devkit_rhel_major` / `devkit_rhel_tag` / `devkit_rhel_tag_fallbacks`, which map the
  host glibc to the closest EL variant and fall back toward the universal
  glibc-2.28 (rhel8) floor. `toolchains/llvm/setup.sh` now selects an
  `LLVM-<ver>-Linux-X64-rhel{8,9,10}` archive with fallback; `dev-tools/sqlite/setup.sh`
  resolves the distro-native system RPM per major (el8/el9/el10).
- **CI renamed and made a matrix.** `rhel8-test.yml` → `linux-integration.yml`
  (UBI 9 on push/PR, UBI 8 + 9 + 10 on the weekly schedule; base image parameterized).
  `Dockerfile.rhel8-test` → `Dockerfile.linux-test` (`ARG UBI_IMAGE`, default UBI 9).
  `build-llvm-rhel8.yml` → `build-llvm-linux.yml` (builds rhel8/rhel9/rhel10 variants
  in a matrix). Entrypoint renamed to `ci/linux-test-entrypoint.sh`.
- **conan-airgap** gained a `linux-gcc-rhel10-x64` profile (GCC 14 / glibc 2.39);
  example defaults moved to `linux-gcc-rhel9-x64`.

#### gRPC — updated 1.81.1 → 1.83.0, added Debug + Linux packages
- Bumped **gRPC 1.81.1 → 1.83.0** (upstream tag `v1.83.0`). Re-imported the
  maintainer prebuilt packages into the `prebuilt/` submodule as split parts with
  a fresh SHA256 manifest.
- **Windows now ships both Release and Debug** per MSVC toolset (v142/v143/v145).
  Previously only Release shipped. Select the configuration in devkit-ui or via
  `setup.sh --config release|debug`.
- **New Linux target.** gRPC now ships a RHEL/Rocky 8/9/10 (x86_64) package built with
  `gcc-toolset-13` and a statically linked C++ runtime, so it installs offline on
  RHEL/Rocky 8, 9, and 10 with no gcc-toolset runtime present. Install with
  `setup.sh --platform linux`, or the "Linux x86_64 (RHEL/Rocky 8/9/10)" variant in
  devkit-ui. gRPC is now enabled on the Linux path of the `full` install profile.
- `setup.sh` gained `--config` and `--platform` flags and a Linux install branch;
  each package installs into its own sibling prefix
  (`grpc-1.83.0-msvc<NNN>-<config>` / `grpc-1.83.0-linux`) so toolsets, configs,
  and platforms coexist. `import-grpc-prebuilt.sh` gained `--configs` and Linux
  import. The example project pulls in the updated client/server (optional TLS via
  `GRPC_TLS_ROOT_CERT`) and Release/Debug CMake presets for v142/v143/v145.

#### SBOM generator — list every artifact at the newest version
- `generate-sbom.sh` now keeps **all** prebuilt manifests a tool ships at its
  newest version (e.g. gRPC's Windows and Linux platform manifests), instead of
  collapsing to a single one. Older versions still collapse as before.

#### Bundled tool version bumps
- **CMake 4.3.3 → 4.4.2** — adds a from-source musl variant (static libstdc++/libgcc,
  links only `ld-musl`); Windows + glibc from upstream.
- **SQLite 3.53.3 → 3.53.4** — from-source static `sqlite3` CLI for both libc families
  (glibc + musl); Windows tools zip refreshed; RHEL/Rocky el8/el9/el10 RPMs unchanged.
- **GDB 17.1 → 17.2**, **PuTTY 0.83 → 0.84**, **SourceTree 3.4.30 → 3.4.31**.
- **FileZilla 3.70.4 → 3.70.6** — clean (non-sponsored) win64 installer + upstream
  `.tar.xz` Linux tarball.
- **llvm-mingw 20260407 → 20260616**; **Git for Windows 2.55.0 → 2.55.0.windows.3**
  (wincred fix).
- SBOM regenerated; every affected `manifest.json` carries a fresh SHA-256.

---

## [1.3.66] — 2026-07-29

Fourth-round re-validation follow-up. One P0 regression fixed, plus a resource
leak and an incomplete uninstall surfaced by the same pass.

### Fixed
- **Team server (`serve.sh`) refused to start on any non-root firewalld host.**
  The advisory firewall probe ran two commands whose non-zero exit aborted the
  whole script under `set -euo pipefail`: `firewall-cmd --state` (252 stopped /
  253 polkit-denied) and the closed-port query (`rc 1`). Both now capture status
  with `|| st=$?` so the check stays advisory and the server always launches.
- **`uninstall.sh --all` left `env.sh` and its `~/.bashrc` source line orphaned.**
  `env.sh` became a glob over `<prefix>/*/bin` with no per-tool lines to strip, so
  the old content-parsing cleanup never emptied it and never removed the shell
  wiring. Cleanup is now receipt-driven: once no `INSTALL_RECEIPT.txt` remains
  under a prefix, `env.sh` and its `~/.bashrc` line are removed; a partial
  uninstall keeps them (the glob self-adjusts).
- **VS Code extension install leaked ~120 MB of `/tmp` per run.** A bare
  `trap … EXIT` in `vscode-extensions/setup.sh` replaced the library's temp-root
  cleanup instead of adding to it. `tools/lib/devkit-install.sh` now exposes a
  composable `devkit_add_exit_trap`; the library and every setup.sh register
  through it so all handlers run.

---

## [1.3.65] — 2026-07-28

Third-round hardening from a read-only re-validation pass. Two P0 blockers.

### Fixed
- **Every Windows tool install failed** under `set -euo pipefail`: the installer
  helpers (`devkit_install_exe`/`_silent`/`_nsis_s`/`_msi`) ended in a
  `[[ … ]] && { … }` that made the function return 1 on success, so the receipt
  was never written and the caller saw exit 1. Now `if/then` — success returns 0.
- **LLVM integrity check was fail-open.** A tampered part made the resolver exit 1
  (indistinguishable from "absent"), so the installer fell through to the next
  distro tag and exited 0. Integrity failures now exit **2** and abort; only a
  genuinely absent artifact (exit 1) falls through. Applied across all resolvers.
- **Resolver errors were misreported.** A checksum mismatch printed "Archive not
  found"; `devkit_resolve_archive_strict` now distinguishes the two.
- **`sourcetree`/`putty` version pins didn't match staged content** (3.4.31→3.4.30,
  0.84→0.83), failing with no message; and the `INSTALLER=$(devkit_find_file …)`
  guard was dead under `set -e`. Both fixed (also 7zip/notepadpp/git/servy/filezilla).
- **Declared-but-unstaged Windows installers.** A global `*.exe` gitignore silently
  dropped `7z2602-x64.exe` and the Notepad++ installer from the submodule.
  `prebuilt/.gitignore` now re-includes binaries; the installers are staged; a new
  `scripts/internal/check-prebuilt-manifests.sh` (wired into CI) fails if any
  manifest-declared artifact isn't tracked.
- **Linux server binary committed non-executable** (100644) — every run chmod-ed it
  and dirtied the submodule. Committed 100755; `build-server.sh` sets the bit; the
  redundant runtime `chmod +x` in `launch.sh`/`smoke.sh` removed.
- **Assembled split archives leaked to `/tmp`** (a regression from the round-2
  temp-assembly hardening) — hundreds of MB per install. Now cleaned via a
  per-process temp root removed on exit and dropped early after extraction.
- **`install-cli --prefix` was ignored by conan/sqlite/zlib** — they escaped to the
  invoking user's `$HOME`. `_run_setup` now passes `--prefix`.
- **`uninstall.sh` orphaned conan/sqlite/zlib/style-formatter** (and hence `env.sh`
  + the `~/.bashrc` line). Discovery is now receipt-driven, so it can't drift.
- **VS Code style-formatter mutated the devkit's own checkout** (wrote `.clang-format`
  + a pre-commit hook). It now detects the devkit repo and skips (writes a receipt).
- **`serve.sh` firewall check silently no-op'd for non-root** — `firewall-cmd`
  returns 253 (polkit "not authorized"), which the old gate treated as "no
  firewall". It now distinguishes not-running (252) from not-authorized (253) and
  prints an explicit indeterminate note in the latter case.
- **Bundle status never reported installed extension versions** — added
  `--show-versions` and populated `installed_version`.
- **Platform-mismatched artifacts were resolved instead of refused** — a manifest
  with a `platforms` map but no entry for the requested platform now errors.

---

## [1.3.64] — 2026-07-28

Second-round hardening from a deeper validation pass. Includes a **critical**
integrity fix.

### Security
- **Integrity gate could be bypassed for split archives.** The verifier hashed
  the split parts but the installer could hand the extractor a *different*,
  unverified whole file — a cached in-place assembly or a planted file at the
  assembled path. Resolution now **always assembles from the verified parts into
  a temp file** and never trusts a co-located whole file, so the bytes extracted
  are exactly the bytes verified (`devkit_assemble_parts`, `devkit_resolve_archive`,
  `devkit_resolve_named` in `tools/lib/devkit-install.sh`). Affected every
  split-archive tool (llvm, cmake, python, vscode).
- **VS Code extension bundle was installed with no integrity check at all.** Added
  a `manifest.json` (whole-file `sha256` + split `part_sha256`) and a fail-closed
  gate in `vscode-extensions/setup.sh`.

### Fixed
- **VS Code artifact selection was locale-dependent.** `devkit_find_file` picked
  the platform artifact by `head -1` when no filename carried the platform
  keyword, so `LC_ALL=C` vs `en_US` could install a Windows `.exe` on Linux.
  Selection is now manifest-driven (`platforms.<plat>.archive` or `.installer`)
  and deterministic; an ambiguous directory errors instead of guessing. Applies
  to every `devkit_find_file` tool (vscode, 7zip, filezilla, notepadpp,
  sourcetree, putty, git, servy, osslsigncode).
- **Shipped server binaries were stale** (embedded 1.3.61 while source was newer)
  and built from a dirty tree. Binaries rebuilt; `ci/smoke.sh` now asserts the
  binary's `--version` equals the source `AppVersion`, and uses a non-Cockpit port.
- **CLI `cpp-dev` advertised "vscode" but installed neither editor nor extensions**
  on a clean host. The CLI now installs the VS Code editor before the extension
  bundle and puts `code` on PATH for it.
- **VS Code extension bundle reported installed with zero extensions present.**
  Dropped the misleading `code --version` check; the bundle attests success only
  when at least one extension installed (per-package status remains the source of truth).
- **Windows `/DIR` was passed unquoted** to the VS Code installer — a profile path
  with a space would word-split. Now quoted.
- **Non-root VS Code RPM install** now requires `rpm2cpio`/`cpio` explicitly and
  scrubs a partial prefix on a failed extraction (distinguishes a rejected payload
  from a missing tool).
- **`~/.bashrc` env.sh line is now guarded** (`[[ -f … ]] && source …`) so a
  deleted prefix can't break every future shell.
- **Uninstaller** now removes the VS Code editor (`<prefix>/vscode`), previously orphaned.

---

## [1.3.63] — 2026-07-27

Cross-environment validation hardening (LAN / air-gapped / no-admin, RHEL 8/9/10,
Alpine/musl). Fixes from a full matrix test run.

### Fixed
- **Re-install over an existing prefix now succeeds.** `devkit_install_archive`
  replaced each top-level payload entry instead of failing when `mv` hits a
  non-empty destination directory.
- **`launch.sh` no longer reads as "started" when the port is taken.** A new
  owner-independent listener check (a standard user can't see a root-owned socket
  such as Cockpit on `:9090`) fails fast with a `--port` remediation before the
  server prints a start-up banner it can't honour.
- **`run-tests.sh` fails when nothing is installed** (zero passes) instead of
  exiting 0 — a total install failure is no longer indistinguishable from success.
- **Installer preflight** names missing host tools (`xz`/`unzip`/`tar`) up front
  instead of failing mid-extract; `cmake`/`lcov` setups no longer require
  `findutils`.
- **`env.sh` is idempotent** — re-sourcing (it is wired into `~/.bashrc`) no
  longer stacks duplicate `PATH`/`PERL5LIB` entries.
- **style-formatter** writes its receipt under the devkit prefix
  (`clang-style-formatter/`) rather than into the user's own repo root.
- **lcov install is honest about `genhtml`** — it verifies `genhtml` can run and
  names the missing Perl modules instead of reporting a clean success.
- **`serve.sh`** warns when firewalld/ufw is likely blocking the advertised port.

### Added
- **`devkit-server --version`** prints the version and exits.
- **`/api/tools`** entries carry a `source` field (`devkit` vs `system`) so a
  host with a pre-existing toolchain no longer makes the dashboard conflate
  devkit-managed tools with ambient ones.

### Changed
- **`/health`** discloses the server version only to an authenticated caller;
  an unauthenticated probe (e.g. a LAN peer in team-server mode) gets liveness only.
- **Docs**: corrected the API auth example (query-string token is accepted only
  by `/auth/bootstrap`), added `--noproxy '*'` to loopback probes for
  corporate-proxy environments, and documented `bash` as a hard prerequisite on
  Alpine/musl hosts.

---

## [1.3.62] — 2026-07-06

### Changed

#### lcov — updated 2.4 → 2.5 and de-duplicated
- Bumped **lcov 2.4 → 2.5** (`linux-test-project/lcov` v2.5). The prebuilt now
  ships the repacked 2.5 source tree, the upstream `noarch` RPM, and the
  carried-forward vendored Perl dependency (`Capture::Tiny`).
- lcov 2.5 restructured its docs to Sphinx and made `make install` depend on a
  doc rebuild. The vendored source tree is patched so `install` no longer
  invokes Sphinx and installs the prebuilt man pages shipped under
  `docs/_build/man/` — preserving the fully offline install on RHEL 8.

### Fixed

#### Removed duplicate lcov tool definition
- lcov was defined twice (`tools/build-tools/lcov/` **and**
  `tools/toolchains/lcov/`), which produced a duplicate row in the update
  report and caused `apply-tool-update.sh` to target the wrong directory. The
  redundant `build-tools/lcov/` copy is removed; `toolchains/lcov/` is now the
  single source of truth. Installer, status, uninstall, README, and TOOLS docs
  all point at it.

---

## [1.3.61] — 2026-07-06

### Added

#### Integrity & air-gap transfer tooling
- **Conan ↔ gRPC ABI-matched profiles.** `conan-airgap/config/profiles/`
  `windows-msvc-v14{2,3,5}-grpc` use the static CRT (`/MT`) so Conan deps link
  cleanly against the matching prebuilt gRPC toolset package.
- **Whole-tree integrity gate.** `scripts/internal/checksum-verify.sh`, backed by
  the stdlib-only `scripts/internal/lib/checksum_generator.py` engine, produces a
  uniform whole-tree SHA-256 manifest + drift gate (exit 3). Additive —
  does not replace the prebuilt manifests or SBOM checksum flow.
- **Self-verifying air-gap transfer.** `scripts/internal/airgap-transfer.sh` bundles
  the super-repo + submodules with a `SHA256SUMS` manifest and a dependency-free
  `verify.sh` (exit 3 on drift).

### Changed

#### gRPC — replaced source build with prebuilt distribution (1.80.0 → 1.81.1)
- The gRPC tool now ships the complete, relocatable **prebuilt gRPC 1.81.1** SDK
  (bin + include + lib + cmake + `activate.ps1` + `grpc-toolchain.cmake`) from a
  maintainer build. This replaces the previous source-only package and its
  unreliable ~40-minute source-build path.
- **Per-MSVC-toolset packages with a user-facing selector.** Three release
  packages ship — `v142` (Visual Studio 2019), `v143` (Visual Studio 2022,
  default), and `v145` (Visual Studio 2026). devkit-ui shows a Visual Studio
  version selector on the gRPC tool; `install-cli.sh` prompts for it; and
  `setup.sh` takes `--toolset <v142|v143|v145>`. Each toolset installs into its
  own directory (`grpc-1.81.1-msvc<NNN>`) so multiple toolsets coexist.
- Added `tools/frameworks/grpc/Check-Environment.ps1` (detects the installed
  MSVC toolset/CMake and prints the matching package + configure command), a
  tool README, and a vendored `example-project/` copy-and-go starter (echo
  service, cross-IDE `CMakePresets.json`, VS Code / VS 2022 / VS 2026 walkthrough).
- Added `scripts/internal/import-grpc-prebuilt.sh` — the sync that stages the
  maintainer release packages into `prebuilt/` as checksummed split parts with a
  multi-variant `manifest.json`.

### Fixed
- `install-cli.sh` invoked a non-existent `setup_grpc.sh`; it now calls the real
  `setup.sh`. `status.sh` probes the new per-toolset install directories.

---

## [1.3.6] — 2026-07-03

### Changed

#### Tool version bumps
- **Servy** 8.4 → 8.5
- **VS Code** 1.124.2 → 1.127.0
- **SQLite CLI** 3.53.2 → 3.53.3

---

## [1.3.5] — 2026-07-01

### Changed

#### Tool version bumps
- **LLVM/Clang** 22.1.4 → 22.1.8
- **clang-style-formatter** 22.1.4 → 22.1.8
- **CMake** 4.3.2 → 4.3.4
- **Conan** 2.28.0 → 2.30.0
- **GCC (WinLibs)** 15.1.1 → 16.1.0 (GCC 16.1.0, mingw-w64-ucrt 14.0.0-r3; archive format changed tar.xz → zip)
- **Git** 2.54.0 → 2.55.0
- **gRPC** 1.80.0 → 1.81.1
- **Notepad++** 8.9.4 → 8.9.6.4
- **.NET SDK** 10.0.203 → 10.0.301
- **PuTTY** 0.83 → 0.84
- **Python** 3.14.4 → 3.14.6
- **Servy** 8.3 → 8.5
- **7-Zip** 26.01 → 26.02
- **SQLite CLI** 3.53.0 → 3.53.3
- **SourceTree** 3.4.30 → 3.4.31
- **VS Code** 1.117.0 → 1.127.0

### Added

#### Update automation
- `scripts/internal/check-updates.sh` — scans all tools against GitHub releases and upstream sources; outputs a color-coded table or `--json` for CI consumption; exit 1 when updates are available
- `scripts/internal/apply-tool-update.sh` — downloads, repacks, splits, and stages a tool update end-to-end; writes `manifest.json`; updates `devkit.json` version and `setup.sh` VERSION line
- `scripts/internal/lib/devkit-prebuilt.sh` — shared shell helpers (`dl`, `sha256`, `repack_xz_strip1`, `repack_xz_flat`, `split_parts`, `json_field`) sourced by both scripts above
- `scripts/internal/lib/generate-manifest.py` — generates `prebuilt/<category>/<tool>/<version>/manifest.json` from staged files; handles whole archives and split-part files via Python `hashlib`
- `scripts/internal/lib/format-update-report.py` — formats `check-updates.sh --json` output as a GitHub issue Markdown body
- `.github/workflows/check-updates.yml` — weekly automated check (Monday 07:00 UTC) that creates or updates a `tool-updates` GitHub issue when upstream versions are newer
- `github_repo`, `asset_match`, `tag_prefix`, `asset_exclude`, `check_url` fields added to all tool `devkit.json` files to power the update infrastructure
- `download_url_template_windows/linux` fields added to VS Code and .NET SDK `devkit.json` for CDN-hosted tools not distributed via GitHub release assets

#### Go server
- `server/internal/tools/discovery.go` — `Tool` struct gains `TagPrefix` field (`json:"tag_prefix"`) for repos whose release tags don't follow the standard `v`-prefix convention (e.g. LLVM uses `llvmorg-22.1.8`)
- `server/internal/api/network.go` — `fetchGitHubLatest` now reads `TagPrefix` and strips the tool-specific prefix instead of always assuming `v`; fixes LLVM version tracking in the devkit-ui update checker

---

## [1.3.4] — 2026-05-04

### Fixed

#### Air-gap correctness
- `server/internal/api/network.go` — internet probes (`/api/network`, `/api/updates`, update download) are now gated behind `allow_egress` in `devkit.config.json` (defaults `false`); previously the server unconditionally dialled `8.8.8.8:53` and `api.github.com` on every `/api/updates` call, breaking the air-gap contract
- `examples/devkit.config.json` — added `allow_egress: false` field so the template is explicit; `server/internal/config/config.go` gains the matching `AllowEgress` field

#### Tool install failures
- `tools/dev-tools/git/setup.sh` — now exits 0 with a "skipping" message on Linux (was `exit 1`); matches the pattern already used by notepadpp, servy, sourcetree, and grpc

#### Authentication
- `server/main.go` — browser auto-open URL corrected from `?token=` to `?devkit_token=`; the auth handler requires `devkit_token` but the launch URL was using the wrong parameter name, causing every auto-open to return 401

### Documentation
- `README.md` — Configuration section updated: `setup_complete` and `allow_egress` now shown in the example block with explanation; Network status and Update checker feature rows clarified to reflect the egress gate; First-run setup note corrected (was describing the wrong condition)

---

## [1.3.3] — 2026-05-03

### Fixed

#### Air-gap / install
- `scripts/build-server.sh` — removed unconditional `go mod tidy` + `go mod download`; build now uses `-mod=vendor` when `server/vendor/` is present; exits with a clear error when `GOPROXY=off` and the vendor dir is absent instead of silently reaching out to the network
- `scripts/install-cli.sh` step 1 — no longer calls `git submodule update` when `prebuilt/` is already populated; in a true air-gap (no network) it warns and continues rather than hard-failing the entire install

#### Server API
- `server/internal/api/auth.go` — `GET /auth/bootstrap` now reads `?devkit_token=` (was `?token=`), matching the token middleware and README; using the documented query parameter now correctly sets the session cookie
- `server/internal/api/handlers.go` — `prefixOverridePath` moved to `~/.config/airgap-cpp-devkit/prefix` (via `os.UserConfigDir()`); previously pointed at the nonexistent `manager/src/…` path, causing `POST /api/prefix` to always return 500
- `packages/pip-packages/devkit.json` — corrected `setup` path from `languages/python/setup.sh` (resolved to a nonexistent sibling) to `../../tools/languages/python/setup.sh`; `GET /install/pip-packages` no longer returns "No such file or directory"

#### Tool install failures
- `tools/dev-tools/vscode-extensions/setup.sh` — `VSIX_DIR` now tries `prebuilt/dev-tools/vscode-extensions/` first, then falls back to `prebuilt/dev-tools/vscode/extensions/` and `prebuilt/dev-tools/vscode/`; was hard-coded to the missing `vscode-extensions/` path
- `tools/toolchains/ninja/setup.sh` — tar member changed from `ninja` to `./ninja` to match archive entry format; extraction no longer fails with "Not found in archive"
- `tools/toolchains/gcc/setup.sh` — non-root Linux install now uses `rpm2cpio | cpio -idmv` to extract RPM payloads into `$PREFIX`; previously hard-exited with "Root required" for non-root users despite README claiming user-prefix mode is supported

#### Server setup gate (H7)
- `server/internal/config/config.go` — on a fresh install with no `devkit.config.json`, `SetupComplete` now defaults to `true`; every `GET /api/*` no longer silently 302-redirects to `/setup` before the user has a chance to complete the wizard

#### Launch script
- `scripts/launch.sh` — default port corrected `8080 → 9090` to match README and `devkit.config.json` documentation
- `scripts/launch.sh` — `_free_port()` now uses `ss -ltnp`/`lsof` on Linux instead of `netstat -ano` (which parses Windows column layout and misidentifies Linux's Timer column as a PID)
- `scripts/launch.sh` — `--yes`, `--profile`, `--prefix`, `--admin`, `--rebuild` flags are now forwarded to `install-cli.sh` when the server binary is missing and the script falls back to CLI install; previously all CLI flags were silently dropped
- `scripts/status.sh` — stale `tools/toolchains/clang/style-formatter/` paths updated to `tools/toolchains/llvm/style-formatter/`
- `scripts/install-cli.sh` — header comment updated: removed stale Python 3.8+ requirement, corrected port reference to 9090, replaced `clang` path with `llvm`

---

## [1.3.2] — 2026-05-01

### Added
- `scripts/sign-binaries.sh` — Authenticode (Windows, via `osslsigncode` or `signtool`) and GPG detached-signature (Linux) support
- `scripts/verify-signatures.sh` — verify Authenticode and GPG signatures on prebuilt binaries
- `scripts/virustotal-scan.sh` — VirusTotal API v3 scan with JSON report output; supports files >32 MB via large-file upload URL
- `ci/sign.sh` — thin CI entry-point that calls `scripts/sign-binaries.sh`
- `.github/workflows/sign-and-scan.yml` — manual `workflow_dispatch` workflow to sign binaries and/or run VirusTotal scan in CI
- `osslsigncode 2.13` entry in `scripts/download-prebuilt.sh` (Windows zip + Linux source archive)

### Changed
- `scripts/release.sh` — integrated signing (`--skip-sign`) and VirusTotal scan (`--skip-vt`) steps; both are run by default when env vars are present
- `.github/workflows/build-llvm-rhel8.yml` — `actions/upload-artifact` v4.6.0 → v7.0.1; `actions/download-artifact` v4 → v8.0.1 (pinned SHA)
- `.github/workflows/smoke-test.yml` — `actions/upload-artifact` v4.6.0 → v7.0.1 (pinned SHA)
- `.gitignore` — added `.claudeignore`
- Server binaries rebuilt against current Go toolchain

---

## [1.3.1] — 2026-05-01

### Fixed
- `scripts/launch.sh`, `scripts/uninstall.sh`, `tests/check-installed-tools.sh` — removed unused variables flagged by ShellCheck (SC2034)
- `scripts/pkg.sh` — fixed printf format/argument mismatch (SC2183) by splitting composite argument into two separate args
- `tests/run-tests.sh`, `tests/check-installed-tools.sh` — added ShellCheck source directive for non-constant `source` paths (SC1090)
- `tests/validate-manifests.sh` — removed redundant quotes around regex RHS in `[[ =~ ]]` (SC2076)

### Changed
- Go deps: `go-chi/chi` v5.2.2 → v5.2.5, `golang.org/x/text` v0.22.0 → v0.36.0; server binaries rebuilt
- Python build deps: `setuptools>=75`, `wheel>=0.45`

---

## [1.3.0] — 2026-05-01

### Changed
- **Repository layout** — aligned to project standard: `ci/` (renamed from `.ci/`), `scripts/launch.sh`, `scripts/install-cli.sh`, `scripts/uninstall.sh` (moved from root), `docs/TOOLS.md` (moved from root), `ci/Dockerfile.rhel8-test` (moved from root)
- **CI workflows** — `ci.yml` thinned to call `ci/lint.sh`, `ci/test.sh`, and `ci/smoke.sh`; server health-check logic extracted to `ci/smoke.sh`
- All Jenkinsfile, `.gitlab-ci.yml`, `smoke-test.yml`, and `rhel8-test.yml` references updated for new script paths
- `scripts/launch.sh` and `scripts/install-cli.sh` internal path resolution updated for new location in `scripts/`

### Added
- `ci/build.sh`, `ci/test.sh`, `ci/lint.sh`, `ci/release.sh`, `ci/smoke.sh` — canonical CI entry-point scripts
- `.github/CODEOWNERS` — primary maintainer assigned for all files and CI paths
- `.github/dependabot.yml` — weekly dependency updates for Go modules, pip, and GitHub Actions
- `docs/assets/` — home for project screenshots and diagrams
- `examples/` — placeholder for runnable configuration examples
- `packages/python/src/airgap_devkit/py.typed` — PEP 561 typed package marker
- `packages/python/.python-version` — pinned Python version for the packaging environment
- `.pre-commit-config.yaml` — ruff lint/format and standard pre-commit hooks

---

## [1.2.1] — 2026-05-01

### Fixed
- `Dockerfile.rhel8-test` — RHEL 8 CI `$(ldd --version | head -1)` command substitution was evaluated by the outer `/bin/sh` and the result embedded unquoted, causing bash to choke on the parentheses in `ldd (GNU libc) 2.28` with a syntax error; wrapped the substitution in escaped double quotes so the parentheses are safely quoted when bash receives the string
- `.github/workflows/` — updated `actions/checkout` from v4.2.2 (Node.js 20, deprecated) to v4.3.1 (Node.js 24) across all three workflow files

---

## [1.2.0] — 2026-05-01

### Added
- **Manual install fallback** — when the devkit-ui cannot complete an installation, a "Show manual install commands" button appears in the terminal drawer; clicking it opens a modal with tabbed Windows / Linux steps, pre-filled copy-ready shell commands, and split-archive reassembly instructions generated from `GET /api/tool/{id}/manual-install`
- `GET /api/tool/{id}/manual-install` API endpoint — returns platform-specific env block, install command, custom prefix example, split-archive reassembly commands, and per-platform notes
- `scanPrebuiltParts` — server-side scanner that finds `.part-*` files in `prebuilt/` and builds `cat | tar` reassembly commands for each split archive
- `scripts/manual-install.sh` — CLI fallback installer; `--list` enumerates tools, `--tool <id>` installs, `--prefix` sets a custom path, `--verify-only` confirms split parts are present
- `docs/manual-install.md` — step-by-step manual install guide for Windows (Git Bash) and Linux, with tool-specific examples, manual split-archive reassembly commands, receipt creation, PATH wiring, and troubleshooting table
- `.github/workflows/rhel8-test.yml` — CI workflow that builds `Dockerfile.rhel8-test` and runs the full install + smoke-test suite inside UBI 8.10 (RHEL 8 / glibc 2.28); triggers on install-related path changes, weekly Monday schedule, and `workflow_dispatch`

### Fixed
- `install-cli.sh` — added `--admin` flag (selects system-wide install prefix); `Jenkinsfile` and `.gitlab-ci.yml` both pass `--admin` when `ADMIN_INSTALL=true` but the flag was previously unrecognised, crashing the install step
- `Jenkinsfile` and `.gitlab-ci.yml` server-ops stage — all API calls now include `X-DevKit-Token` header; `auth.go` requires the token for every route except `/health`, `/auth/bootstrap`, and `/static/`, so every `curl` to `/api/config`, `/api/health/tools`, etc. was returning 401
- `.gitlab-ci.yml` — replace fragile `/proc/*/cmdline` PID scan in `after_script` with a `.server.pid` file (`after_script` runs in a fresh shell and cannot access variables set in the main script)

---

## [1.1.0] — 2026-04-30

### Added
- **First-run setup wizard** — `/setup` page with animated gradient UI; server redirects all requests there until setup is complete (`setup_complete` flag in `devkit.config.json`)
- **Team Config Repository sync** — configure a git repo URL in Settings; devkit auto-syncs team config on every launch and provides a manual sync button with last-sync status indicator
- `server/internal/team/` package — `CloneOrPull`, `LoadConfig`, `LastCommit` helpers for team config git sync
- `setupCheck` middleware — enforces setup wizard flow on first launch before any dashboard access
- `validateRepoURL` — server-side validation for team config repo URL input
- `sanitizeDisplayName` — sanitization for display name fields
- `GET /api/team/status` and `POST /api/team/sync` API endpoints for team config sync
- Dashboard installed/all filter — clickable stat chip to toggle between all tools and installed-only view
- `escHtml` and `escJs` helper functions in dashboard JS to prevent XSS in dynamic content
- GitHub update version badges in the dashboard update checker UI
- `scripts/release.sh` — atomic version bump, Go binary build, Python wheel build, and optional PyPI upload
- `scripts/download-prebuilt.sh` — download prebuilt binaries from GitHub releases
- `packages/python/` — PyPI package source (`pyproject.toml`, `__main__.py`, `__init__.py`, stage-binaries script)
- `dist/` to `.gitignore` — wheel build artifacts are no longer tracked
- `.github/profile/README.md` — GitHub org profile landing page

### Changed
- `devkit.config.json` schema: added `team_config_repo` (string) and `setup_complete` (bool) fields
- `/api/config` accepts `team_config_repo`; triggers background sync when the repo URL changes
- Removed `7zip` from the built-in `cpp-dev` and `devops` profile tool lists
- `.gitignore`: fixed `.pyirc` typo → `.pypirc`; added `dist/` build artifact exclusion
- `README.md`: updated version reference to v1.1.0

---

## [1.0.1-rc.2] — 2026-04-26

### Changed
- `.gitignore` — added `.devkit-token` and TLS certificate exclusions
- Updated `prebuilt/` submodule to v1.0.1-rc.2 binaries

---

## [1.0.0-rc.1] — 2026-04-25

### Added
- `CONTRIBUTING.md` — dual-licensing CLA with copyright assignment and patent grant
- `CHANGELOG.md` — Keep a Changelog format with full backfilled history
- `SECURITY.md` — private disclosure policy, SLA table, scope definition, security design notes
- `CODE_OF_CONDUCT.md` — professional conduct standards and enforcement contact
- `.github/ISSUE_TEMPLATE/bug_report.md` — structured bug report template
- `.github/ISSUE_TEMPLATE/feature_request.md` — feature request template with air-gap compatibility checklist
- `.github/ISSUE_TEMPLATE/config.yml` — issue chooser with security advisory, discussions, and commercial licensing links
- `.github/pull_request_template.md` — PR checklist enforcing binary policy, SBOM, syntax checks
- `.github/FUNDING.yml` — GitHub sponsor button placeholder
- `SUPPORT.md` — help channels: issues, discussions, security email, commercial contact
- AGPL v3 license badge and CI badge in README
- Contributing and License sections in README with dual-licensing note

### Changed
- **Version bumped to v1.0.0-rc.1** — first release candidate
- `LICENSE` — relicensed from custom Source-Available License v1.0 to GNU Affero General Public License v3.0
- `SECURITY.md` — corrected TLS note: `--tls` auto-generates a self-signed certificate
- `.editorconfig` — added Go (tabs), JSON (2-space), and Makefile (tabs) sections

---

## [0.2.0-alpha.2] — 2025-04-19

### Added
- Session token authentication — one-time bootstrap redirect on first launch; token saved to `.devkit-token`
- Optional HTTPS support — pass `--tls-cert` and `--tls-key` to `launch.sh`
- Response header hardening (`X-Content-Type-Options`, `X-Frame-Options`, `Cache-Control`)
- VS Code integration tool entry

### Changed
- DevKit Manager is now a single pre-compiled Go binary; no Python, pip, or runtime dependencies required
- `launch.sh` selects the correct binary for the current platform automatically

---

## [0.2.0-alpha.1] — 2025-04-13

### Added
- CI/CD pipeline (GitHub Actions): build + smoke-test matrix across Windows and RHEL
- Atlassian integration placeholders
- Layout configuration support in `devkit.config.json`
- **My Team** button relocated to top bar for quicker access

### Changed
- Top bar height adjusted for denser layout
- Profile cards and settings panel layout polish

---

## [0.1.0] — 2025-03

### Added
- Initial air-gapped C++ developer toolkit
- FastAPI + HTMX devkit-ui with SSE live install output
- Tool auto-discovery from `devkit.json` per tool directory
- Install receipt tracking (`INSTALL_RECEIPT.txt`)
- Air-gap wheel vendoring under `tools/dev-tools/devkit-ui/vendor/`
- Multi-profile support: `cpp-dev`, `devops`, `minimal`, `full`
- Team config export/import (`GET /api/export`, `POST /api/import`)
- Update checker comparing installed version vs current `devkit.json`
- SBOM generation (`scripts/generate-sbom.sh` → `sbom.spdx.json`)
- Windows 11 (Git Bash) and RHEL 8 (Bash 4.x) support

---

[Unreleased]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.3.3...HEAD
[1.3.3]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.0.1-rc.2...v1.1.0
[1.0.1-rc.2]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.0.0-rc.1...v1.0.1-rc.2
[1.0.0-rc.1]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v0.2.0-alpha.2...v1.0.0-rc.1
[0.2.0-alpha.2]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v0.2.0-alpha.1...v0.2.0-alpha.2
[0.2.0-alpha.1]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v0.1.0...v0.2.0-alpha.1
[0.1.0]: https://github.com/NimaShafie/airgap-cpp-devkit/releases/tag/v0.1.0
