# Contributing to airgap-cpp-devkit

Thank you for your interest in contributing. This document explains how to participate and what you agree to by doing so.

---

## Contributor License Agreement

This project is licensed under **AGPL v3** and is also offered under a **commercial license** for organizations that cannot accept AGPL obligations. This dual-licensing model is how the project is sustained.

For dual licensing to remain legally valid, the copyright holder must own — or hold a broad enough license over — every line in the codebase, including contributions. That is why a CLA with copyright assignment is required here, rather than the simpler "contributions are received under the same AGPL terms" approach. This is the same pattern used by MariaDB, Qt, and other projects that offer open source + commercial tiers.

By submitting a pull request, issue, or any other contribution to this repository, you agree to the following terms:

1. **Copyright assignment.** You assign to Nima Shafie all right, title, and interest — including all intellectual property rights — in and to your contribution. You retain no ownership over contributions once submitted.

2. **Patent grant.** You grant to Nima Shafie a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable patent license to make, have made, use, offer to sell, sell, import, and otherwise transfer contributions that are covered by any patents you own or control.

3. **Original work.** You represent that each contribution is your original creation and that you have the right to grant the above rights.

4. **No third-party rights.** You confirm that your contribution does not include material that is subject to a third-party license incompatible with the project's license.

5. **No obligation to accept.** The maintainer retains full discretion to accept, reject, or modify any contribution.

Your contribution, once accepted, will be available to all users under the AGPL v3 (see [LICENSE](LICENSE)). Commercial licensees also benefit — this is expected and by design.

---

## How to Contribute

### Reporting bugs

Open an issue using the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) template. Include:
- Platform (Windows 11 / RHEL 8 / RHEL 9 / RHEL 10 / Rocky 8 / Rocky 9 / Rocky 10) and shell (Git Bash / Bash)
- Exact commands run and full terminal output
- Contents of any relevant `INSTALL_RECEIPT.txt` files

### Requesting features

Open an issue using the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) template.

### Submitting changes

1. Fork the repository and create a topic branch from `main`.
2. Make your changes. Follow the conventions below.
3. Syntax-check all shell scripts: `bash -n <script.sh> && echo OK`
4. Run the smoke tests: `bash tests/run-tests.sh --verbose`
5. Open a pull request using the [PR template](.github/pull_request_template.md).

---

## Coding Conventions

- Shell scripts target **MINGW64 (Git Bash)** on Windows and **Bash 4.x** on RHEL/Rocky 8, 9, 10.
- No compiled binaries in the main repo. Binaries belong in the `prebuilt/` submodule.
- Versions and SHA256 checksums must be kept in sync across `manifest.json`, `devkit.json`, and `sbom.spdx.json`.
- Run `bash scripts/internal/generate-sbom.sh` after any tool addition or version bump.
- Prefer editing existing files over creating new ones. No half-finished implementations.

---

## Code of Conduct

All contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
