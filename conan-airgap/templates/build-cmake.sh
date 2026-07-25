#!/usr/bin/env bash
# templates/build-cmake.sh — build this template with Conan + CMake presets,
# fully offline, on an air-gapped host.
#
# Usage: bash build-cmake.sh [PROFILE]
#   PROFILE  name of a kit profile (default: linux-gcc-rhel9-x64)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-linux-gcc-rhel9-x64}"

CONAN="$(command -v conan)"

# 1. Generate the CMake toolchain + dependency files and CMakeUserPresets.json
#    from the local cache. --build=never guarantees nothing is fetched/built
#    from a network; a missing binary fails loudly instead of reaching out.
"$CONAN" install "$HERE" \
    --profile:host="$PROFILE" --profile:build="$PROFILE" \
    --build=never

# 2. Conan wrote CMakeUserPresets.json → configure + build via the preset.
cmake --preset conan-release -S "$HERE"
cmake --build --preset conan-release

echo "==> Built. Run the 'app' binary under $HERE/build/."
