#!/usr/bin/env bash
# templates/build-eclipse.sh — generate an Eclipse CDT project wired to the
# air-gapped Conan dependencies, then optionally build it.
#
# It drives CMake's "Eclipse CDT4" project generator through Conan's
# tools.cmake.cmaketoolchain:generator conf, so the preset Conan writes produces
# .project / .cproject files you import into Eclipse CDT
# (File > Import > General > Existing Projects into Workspace).
#
# Usage: bash build-eclipse.sh [PROFILE] [ECLIPSE_GENERATOR]
#   PROFILE            kit profile (default: linux-gcc-rhel9-x64)
#   ECLIPSE_GENERATOR  CMake extra-generator string. Default "Eclipse CDT4 -
#                      Ninja" works on both Windows and Linux (the devkit ships
#                      Ninja) and avoids the make/sh pitfalls of the Makefiles
#                      backends. Alternatives: "Eclipse CDT4 - Unix Makefiles"
#                      (Linux/RHEL), "Eclipse CDT4 - MinGW Makefiles" (Windows).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-linux-gcc-rhel9-x64}"
ECLIPSE_GENERATOR="${2:-Eclipse CDT4 - Ninja}"

CONAN="$(command -v conan)"

# 1. Generate Conan files AND make the resulting CMake preset use the Eclipse
#    generator. -DCMAKE_ECLIPSE_GENERATE_SOURCE_PROJECT=TRUE puts the sources in
#    the Eclipse project tree so they are browsable/indexable in the IDE.
"$CONAN" install "$HERE" \
    --profile:host="$PROFILE" --profile:build="$PROFILE" \
    --build=never \
    -c tools.cmake.cmaketoolchain:generator="$ECLIPSE_GENERATOR" \
    -c tools.cmake.cmaketoolchain:extra_variables='{"CMAKE_ECLIPSE_GENERATE_SOURCE_PROJECT": "TRUE"}'

# 2. Configure via the Conan preset — this emits .project / .cproject for Eclipse.
cmake --preset conan-release -S "$HERE"

PROJ_DIR="$(dirname "$(find "$HERE" -name '.cproject' -print -quit 2>/dev/null || true)")"
echo ""
echo "==> Eclipse CDT project generated."
if [[ -n "$PROJ_DIR" && "$PROJ_DIR" != "." ]]; then
    echo "    Import into Eclipse: File > Import > Existing Projects into Workspace"
    echo "    Project root: ${PROJ_DIR}"
else
    echo "    Look for .project/.cproject under ${HERE}/build/ and import that folder."
fi
echo "    Build inside Eclipse, or: cmake --build --preset conan-release"
