#!/usr/bin/env bash
# Default container entrypoint for the RHEL / Rocky integration test image.
# Installs the selected profile, then runs the full smoke-test suite.
# Override DEVKIT_PROFILE (env) to test a different profile.
set -euo pipefail

echo '==> airgap-devkit RHEL / Rocky integration test'
echo "    Profile: ${DEVKIT_PROFILE}"
echo "    Distro : $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
echo "    glibc  : $(ldd --version | head -1)"
echo ''
bash scripts/internal/install-cli.sh --yes --profile "${DEVKIT_PROFILE}"
echo ''
bash tests/run-tests.sh --verbose
