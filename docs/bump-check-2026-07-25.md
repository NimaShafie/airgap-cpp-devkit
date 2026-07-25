# Tool Bump Check — 2026-07-25

Author: Nima Shafie

Snapshot of every tool module's pinned version vs. the latest upstream release,
produced during the gRPC 1.83.0 pull-in. **Only gRPC was updated in this pass**
(new prebuilt binaries were available locally). Every other tool ships a pinned
prebuilt binary with a SHA256 — bumping one requires vendoring a freshly built
prebuilt artifact, which cannot be done in the air-gapped repo without the binary
in hand. This report is the actionable to-do list for what to re-vendor next.

Latest-upstream values were fetched live from each tool's `check_url` (or its
canonical upstream) on 2026-07-25. Treat them as point-in-time.

---

## Outdated — still outstanding (candidates to re-vendor)

| Tool | Pinned | Latest upstream | Gap | Source |
|------|--------|-----------------|-----|--------|
| **cmake** | 4.3.3 | **4.4.0** | minor | cmake.org/download |
| **vscode** | 1.127.0 | **1.130** | minor | code.visualstudio.com/updates |
| **gdb** | 17.1 | **17.2** | minor | sourceware.org/gdb |
| **sqlite** | 3.53.3 | **3.53.4** | patch | sqlite.org/download |

## Already bumped in the working tree (in-progress, not by this pass)

As of this snapshot the `tools/` and `prebuilt/` submodules already carry commits
(`tools 07fa23b`, `prebuilt 20ffb0e`) bumping these to the latest upstream — a
separate, concurrent effort. No action needed from the gRPC pass:

| Tool | Now at | Latest upstream | Status |
|------|--------|-----------------|--------|
| conan | 2.31.1 | 2.31.1 | current *(conan-airgap kit bundles it)* |
| notepadpp | 8.9.7 | 8.9.7 | current |
| osslsigncode | 2.14 | 2.14 | current |
| servy | 8.7 | — | bumped (niche; upstream not web-verified) |

## Current — no action

| Tool | Pinned | Latest upstream |
|------|--------|-----------------|
| grpc | **1.83.0** | 1.83.0 *(updated this pass)* |
| python | 3.14.6 | 3.14.6 |
| llvm | 22.1.8 | 22.1.8 |
| clang-style-formatter | 22.1.8 | 22.1.8 *(tracks llvm)* |
| ninja | 1.13.2 | 1.13.2 |
| gcc (winlibs) | 16.1.0 | 16.1.0 |
| lcov | 2.5 | 2.5 |
| zlib | 1.3.2 | 1.3.2 |
| 7zip | 26.02 | 26.02 |
| git | 2.55.0 | 2.55.0(3) |
| putty | 0.84 | 0.84 |
| sourcetree | 3.4.31 | 3.4.31 |

## Needs a manual check

| Tool | Pinned | Note |
|------|--------|------|
| **dotnet** | 10.0.301 | Upstream page reports runtime `10.0.10`; the SDK uses feature-band numbering (`10.0.1xx/2xx/3xx`). Pinned value is an SDK band — confirm the newest SDK band manually before deciding. |
| **filezilla** | 3.70.4 | `filezilla-project.org` and the wiki changelog both return HTTP 403 to automated fetches — could not verify the latest client version. Check manually. |
| **servy** | 8.6 | Niche third-party tool with no reliable public release feed queried here. |
| matlab | N/A | Verification-only shim (no bundled binary to bump). |
| git-bundle | N/A | Meta/bundle tool — no upstream version. |
| vscode-extensions | various | Bundle of extensions — versioned individually, out of scope here. |
| conan-airgap | 1.0.0 | Internal wrapper kit (versioned independently); tracks the bundled Conan (see above). |

---

## Internal inconsistencies worth fixing (not upstream bumps)

Found while surveying — the tool's `devkit.json` version and its `prebuilt/`
manifest version disagree, so the pinned prebuilt is older than the advertised
version:

| Tool | `devkit.json` | `prebuilt/` manifest dir |
|------|---------------|--------------------------|
| **putty** | 0.84 | `prebuilt/dev-tools/putty/0.83/` |
| **sourcetree** | 3.4.31 | `prebuilt/dev-tools/sourcetree/3.4.30/` |

These aren't upstream-outdated (both match latest), but the shipped binary lags
the manifest — either re-vendor the matching prebuilt or correct the `devkit.json`
version.

---

## Method

- Pinned versions read from each `tools/*/devkit.json` `version` field.
- Latest fetched from `check_url` where present, else the canonical upstream
  (GitHub releases / project download page).
- No `devkit.json`, manifest, or binary was modified for any tool other than gRPC.
