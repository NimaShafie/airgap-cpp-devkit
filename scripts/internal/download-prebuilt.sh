#!/usr/bin/env bash
# scripts/internal/download-prebuilt.sh
# Downloads, repackages, and stages all prebuilt binaries.
# Run from the repo root on an internet-connected machine.
#
# Every archive is staged in the platform-native, no-admin-extractable format:
#   Windows → .zip   (Explorer "Extract All" / PowerShell Expand-Archive)
#   Linux   → .tar.gz (base tar — no xz/7-Zip dependency)
# Installers (.exe) and packages (.rpm) are staged as-is. We never stage
# .tar.xz or .7z. Files >50MB are split into .part-aa/.part-ab/... .
#
# Usage:
#   bash scripts/internal/download-prebuilt.sh [--small] [--large]
#   --small   Only small/medium tools (cmake, notepadpp, conan, servy)
#   --large   Only large tools (llvm, dotnet, vscode) — can take 30+ min
#   (no flags) runs all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREBUILT_DIR="$REPO_ROOT/prebuilt"
TMP_DIR=$(mktemp -d)
export TMP_DIR
export PART_SIZE="50m"

# Shared helpers: dl, sha256, split_parts, devkit_repack, devkit_platform_ext, log/ok/fail.
source "$SCRIPT_DIR/lib/devkit-prebuilt.sh"

GENMANIFEST="$SCRIPT_DIR/lib/generate-manifest.py"

RUN_SMALL=true
RUN_LARGE=true
for arg in "$@"; do
  case "$arg" in
    --small) RUN_LARGE=false ;;
    --large) RUN_SMALL=false ;;
  esac
done

trap 'echo "Cleaning up tmp..."; rm -rf "$TMP_DIR"' EXIT

# Split a staged file into 50MB parts if it exceeds the threshold; otherwise
# leave it whole. generate-manifest.py handles both whole files and part sets.
maybe_split() {
    local file="$1"
    local sz; sz=$(wc -c < "$file")
    if (( sz > 50 * 1024 * 1024 )); then
        split_parts "$file" "$(dirname "$file")" "$(basename "$file")"
    else
        ok "Staged: $(basename "$file") ($(( sz / 1024 / 1024 )) MB)"
    fi
}

# Write a manifest by scanning a staged directory (archive names + sha256 + parts).
gen_manifest() {
    local dir="$1" tool="$2" version="$3" repo="${4:-}" tag="${5:-}"
    python3 "$GENMANIFEST" "$dir" "$tool" "$version" "$repo" "$tag"
}

# ─────────────────────────────────────────────────────────────────────────────
# SMALL / MEDIUM DOWNLOADS
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$RUN_SMALL" == true ]]; then

  # ── CMake 4.3.2 ─────────────────────────────────────────────────────────────
  log "CMake 4.3.2"
  CMAKE_DIR="$PREBUILT_DIR/build-tools/cmake/4.3.2"
  mkdir -p "$CMAKE_DIR"

  dl "https://github.com/Kitware/CMake/releases/download/v4.3.2/cmake-4.3.2-windows-x86_64.zip" \
     "$TMP_DIR/cmake-win.zip"
  devkit_repack "$TMP_DIR/cmake-win.zip" "$CMAKE_DIR/cmake-4.3.2-windows-x86_64.zip" strip1
  maybe_split "$CMAKE_DIR/cmake-4.3.2-windows-x86_64.zip"

  dl "https://github.com/Kitware/CMake/releases/download/v4.3.2/cmake-4.3.2-linux-x86_64.tar.gz" \
     "$TMP_DIR/cmake-lin.tar.gz"
  devkit_transcode_targz "$TMP_DIR/cmake-lin.tar.gz" "$CMAKE_DIR/cmake-4.3.2-linux-x86_64.tar.gz"
  maybe_split "$CMAKE_DIR/cmake-4.3.2-linux-x86_64.tar.gz"

  gen_manifest "$CMAKE_DIR" cmake 4.3.2 Kitware/CMake v4.3.2
  ok "CMake 4.3.2 complete."

  # ── Notepad++ 8.9.4 (portable .zip + installer .exe — already native) ───────
  log "Notepad++ 8.9.4"
  NPP_DIR="$PREBUILT_DIR/dev-tools/notepadpp/8.9.4"
  mkdir -p "$NPP_DIR"

  dl "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.4/npp.8.9.4.portable.x64.zip" \
     "$NPP_DIR/npp.8.9.4.portable.x64.zip"
  dl "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.4/npp.8.9.4.Installer.x64.exe" \
     "$NPP_DIR/npp.8.9.4.Installer.x64.exe"

  PORTABLE_SHA=$(sha256 "$NPP_DIR/npp.8.9.4.portable.x64.zip")
  INST_SHA=$(sha256     "$NPP_DIR/npp.8.9.4.Installer.x64.exe")
  cat > "$NPP_DIR/manifest.json" << MEOF
{
  "tool": "notepadpp",
  "version": "8.9.4",
  "source": "https://notepad-plus-plus.org/downloads/v8.9.4/",
  "platforms": {
    "windows": {
      "installer": "npp.8.9.4.Installer.x64.exe",
      "installer_sha256": "$INST_SHA",
      "portable": "npp.8.9.4.portable.x64.zip",
      "portable_sha256": "$PORTABLE_SHA",
      "reassemble": "unzip -o npp.8.9.4.portable.x64.zip"
    }
  },
  "compression": "zip",
  "notes": "setup.sh uses the portable zip by default (no admin required)."
}
MEOF
  ok "Notepad++ 8.9.4 complete."

  # ── Conan 2.28.0 ────────────────────────────────────────────────────────────
  log "Conan 2.28.0"
  CONAN_DIR="$PREBUILT_DIR/dev-tools/conan/2.28.0"
  mkdir -p "$CONAN_DIR"

  dl "https://github.com/conan-io/conan/releases/download/2.28.0/conan-2.28.0-windows-x86_64.zip" \
     "$TMP_DIR/conan-win.zip"
  devkit_repack "$TMP_DIR/conan-win.zip" "$CONAN_DIR/conan-2.28.0-windows-x86_64.zip" strip1
  maybe_split "$CONAN_DIR/conan-2.28.0-windows-x86_64.zip"

  dl "https://github.com/conan-io/conan/releases/download/2.28.0/conan-2.28.0-linux-x86_64.tgz" \
     "$TMP_DIR/conan-lin.tgz"
  devkit_transcode_targz "$TMP_DIR/conan-lin.tgz" "$CONAN_DIR/conan-2.28.0-linux-x86_64.tar.gz"
  maybe_split "$CONAN_DIR/conan-2.28.0-linux-x86_64.tar.gz"

  gen_manifest "$CONAN_DIR" conan 2.28.0 conan-io/conan 2.28.0
  ok "Conan 2.28.0 complete."

  # ── Servy 8.3 (upstream .7z → Windows .zip) ─────────────────────────────────
  log "Servy 8.3"
  SERVY_DIR="$PREBUILT_DIR/dev-tools/servy/8.3"
  mkdir -p "$SERVY_DIR"

  dl "https://github.com/aelassas/servy/releases/download/v8.3/servy-8.3-x64-portable.7z" \
     "$TMP_DIR/servy-8.3-x64-portable.7z"
  devkit_repack "$TMP_DIR/servy-8.3-x64-portable.7z" "$SERVY_DIR/servy-8.3-windows-x64.zip" flat
  maybe_split "$SERVY_DIR/servy-8.3-windows-x64.zip"

  gen_manifest "$SERVY_DIR" servy 8.3 aelassas/servy v8.3
  ok "Servy 8.3 complete."

  # ── osslsigncode 2.13 (Windows .zip as-is; Linux source .tar.gz built on host) ─
  log "osslsigncode 2.13"
  OSSL_DIR="$PREBUILT_DIR/dev-tools/osslsigncode/2.13"
  mkdir -p "$OSSL_DIR"

  dl "https://github.com/mtrojnar/osslsigncode/releases/download/2.13/osslsigncode-2.13-windows-x64-mingw.zip" \
     "$OSSL_DIR/osslsigncode-2.13-windows-x64-mingw.zip"

  OSSL_SOURCES="$REPO_ROOT/tools/dev-tools/osslsigncode/sources"
  mkdir -p "$OSSL_SOURCES"
  dl "https://github.com/mtrojnar/osslsigncode/archive/refs/tags/2.13.tar.gz" \
     "$OSSL_SOURCES/osslsigncode-2.13.tar.gz"

  WIN_SHA=$(sha256 "$OSSL_DIR/osslsigncode-2.13-windows-x64-mingw.zip")
  LIN_SHA=$(sha256 "$OSSL_SOURCES/osslsigncode-2.13.tar.gz")
  cat > "$OSSL_DIR/manifest.json" << MEOF
{
  "tool": "osslsigncode",
  "version": "2.13",
  "source": "https://github.com/mtrojnar/osslsigncode/releases/tag/2.13",
  "platforms": {
    "windows": {
      "archive": "osslsigncode-2.13-windows-x64-mingw.zip",
      "sha256": "$WIN_SHA",
      "reassemble": "unzip -o osslsigncode-2.13-windows-x64-mingw.zip"
    },
    "linux-x64": {
      "source_archive": "tools/dev-tools/osslsigncode/sources/osslsigncode-2.13.tar.gz",
      "sha256": "$LIN_SHA",
      "build": "cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build && cmake --install build",
      "notes": "Requires: gcc cmake openssl-devel libcurl-devel zlib-devel pkg-config"
    }
  },
  "compression": "zip"
}
MEOF
  ok "osslsigncode 2.13 complete."

fi  # RUN_SMALL

# ─────────────────────────────────────────────────────────────────────────────
# LARGE DOWNLOADS (LLVM ~1.2GB, dotnet ~400MB, VS Code ~200MB)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$RUN_LARGE" == true ]]; then

  # ── LLVM/Clang 22.1.4 ───────────────────────────────────────────────────────
  log "LLVM/Clang 22.1.4 — Windows (~700MB, downloading...)"
  LLVM_DIR="$PREBUILT_DIR/toolchains/llvm/22.1.4"
  mkdir -p "$LLVM_DIR"

  dl "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/clang%2Bllvm-22.1.4-x86_64-pc-windows-msvc.tar.xz" \
     "$TMP_DIR/llvm-win.tar.xz"
  devkit_repack "$TMP_DIR/llvm-win.tar.xz" "$LLVM_DIR/clang+llvm-22.1.4-x86_64-pc-windows-msvc.zip" strip1
  maybe_split "$LLVM_DIR/clang+llvm-22.1.4-x86_64-pc-windows-msvc.zip"

  log "LLVM/Clang 22.1.4 — Linux (~500MB, downloading...)"
  dl "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/LLVM-22.1.4-Linux-X64.tar.xz" \
     "$TMP_DIR/llvm-lin.tar.xz"
  devkit_transcode_targz "$TMP_DIR/llvm-lin.tar.xz" "$LLVM_DIR/LLVM-22.1.4-Linux-X64.tar.gz"
  maybe_split "$LLVM_DIR/LLVM-22.1.4-Linux-X64.tar.gz"

  gen_manifest "$LLVM_DIR" llvm 22.1.4 llvm/llvm-project llvmorg-22.1.4
  ok "LLVM/Clang 22.1.4 complete."

  # ── .NET SDK 10.0.203 ───────────────────────────────────────────────────────
  log ".NET SDK 10.0.203 — Windows (~220MB, downloading...)"
  DOTNET_DIR="$PREBUILT_DIR/languages/dotnet/10.0.203"
  mkdir -p "$DOTNET_DIR"

  dl "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.203/dotnet-sdk-10.0.203-win-x64.zip" \
     "$TMP_DIR/dotnet-win.zip"
  devkit_repack "$TMP_DIR/dotnet-win.zip" "$DOTNET_DIR/dotnet-sdk-10.0.203-win-x64.zip" flat
  maybe_split "$DOTNET_DIR/dotnet-sdk-10.0.203-win-x64.zip"

  log ".NET SDK 10.0.203 — Linux (~170MB, downloading...)"
  dl "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.203/dotnet-sdk-10.0.203-linux-x64.tar.gz" \
     "$TMP_DIR/dotnet-lin.tar.gz"
  devkit_transcode_targz "$TMP_DIR/dotnet-lin.tar.gz" "$DOTNET_DIR/dotnet-sdk-10.0.203-linux-x64.tar.gz"
  maybe_split "$DOTNET_DIR/dotnet-sdk-10.0.203-linux-x64.tar.gz"

  gen_manifest "$DOTNET_DIR" dotnet 10.0.203
  ok ".NET SDK 10.0.203 complete."

  # ── VS Code 1.117.0 (installer .exe + .rpm — staged as-is) ───────────────────
  log "VS Code 1.117.0 — Windows installer (~95MB, downloading...)"
  VSCODE_DIR="$PREBUILT_DIR/dev-tools/vscode/1.117.0"
  mkdir -p "$VSCODE_DIR"

  dl "https://update.code.visualstudio.com/1.117.0/win32-x64-user/stable" \
     "$VSCODE_DIR/VSCodeUserSetup-x64-1.117.0.exe"

  log "VS Code 1.117.0 — Linux RPM (~100MB, downloading...)"
  dl "https://update.code.visualstudio.com/1.117.0/linux-rpm-x64/stable" \
     "$VSCODE_DIR/code-1.117.0.el8.x86_64.rpm"

  gen_manifest "$VSCODE_DIR" vscode 1.117.0
  ok "VS Code 1.117.0 complete."

fi  # RUN_LARGE

echo ""
echo "============================================================"
echo " Prebuilt download complete."
echo " Next: bash scripts/internal/generate-sbom.sh"
echo "============================================================"
