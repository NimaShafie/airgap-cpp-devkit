# build-tools/lcov

### Author: Nima Shafie

> **Optional** -- code coverage reporting for C++ projects on RHEL 8 / Linux.
>
> Provides `lcov` 2.4 and `genhtml` with all required Perl dependencies
> vendored as pre-built tarballs. No internet access, no CPAN, no EPEL required.

---

## When to Use This

Use `build-tools/lcov` when you need HTML coverage reports for a C++ project
compiled with GCC's coverage flags (`-fprofile-arcs -ftest-coverage`).

| Scenario | Notes |
|----------|-------|
| Coverage reports on RHEL 8 / Linux | Supported -- this tool |
| Coverage reports on Windows | Not supported by this tool |
| Already have lcov 2.x system-wide | You can skip this |

---

## Usage

### Step 1 -- Bootstrap (once per machine)

```bash
bash build-tools/lcov/setup.sh
```

Extracts `lcov-2.4.tar.gz` and `perl-libs.tar.gz` from `vendor/` into a
local prefix under `build-tools/lcov/local/`. Verifies SHA256 of both
tarballs against `manifest.json` before extracting. No internet access.
No admin rights required.

### Step 2 -- Activate in shell

```bash
source build-tools/lcov/scripts/env-setup.sh
```

Sets `PATH` and `PERL5LIB` so `lcov` and `genhtml` are available in the
current shell session. Add this to your project's developer setup script
if you want it available automatically.

### Step 3 -- Compile with coverage flags

```bash
g++ -fprofile-arcs -ftest-coverage -o my_program my_program.cpp
./my_program
```

### Step 4 -- Generate the report

```bash
# Capture coverage data
lcov --capture --directory . --output-file coverage.info

# Strip system headers (optional but recommended)
lcov --remove coverage.info '/usr/*' --output-file coverage.info

# Generate HTML report
genhtml coverage.info --output-directory coverage-report/

# Open the report
xdg-open coverage-report/index.html
```

---

## Prerequisites

The following system packages are required and are available in the RHEL 8
base AppStream repo -- no EPEL or external repo needed:

```bash
sudo dnf install perl-Time-HiRes perl-JSON
```

Everything else (`Capture::Tiny`, `DateTime`, `DateTime::TimeZone`) is
vendored in `vendor/perl-libs.tar.gz` and installed locally by `setup.sh`.

---

## Integrity Verification

SHA256 hashes for both tarballs are pinned in `manifest.json`.
`setup.sh` verifies them before extracting. To verify manually:

```bash
bash build-tools/lcov/scripts/verify.sh
```

---

## Offline Transfer

Both tarballs are committed directly to the repository:

| File | Size | Purpose |
|------|------|---------|
| `vendor/lcov-2.4.tar.gz` | ~1.1 MB | lcov + genhtml |
| `vendor/perl-libs.tar.gz` | ~4.6 MB | Capture::Tiny, DateTime, DateTime::TimeZone |

No split parts are needed -- both files are under the 100 MB git hosting limit.

To update the vendored tarballs on a machine with internet access:

```bash
bash build-tools/lcov/scripts/download.sh
```

Then update the SHA256 hashes in `manifest.json` and commit.

---

## File Reference

| Path | Purpose |
|------|---------|
| `setup.sh` | **Start here** -- verify + extract, no admin rights |
| `manifest.json` | SHA256 pins for vendored tarballs |
| `vendor/lcov-2.4.tar.gz` | Vendored lcov 2.4 source + binaries (committed) |
| `vendor/perl-libs.tar.gz` | Vendored Perl dependencies (committed) |
| `scripts/download.sh` | **[Maintainer]** Download tarballs on internet machine |
| `scripts/verify.sh` | Offline SHA256 check |
| `scripts/env-setup.sh` | `source` this to activate lcov in current shell |

---

## Design Notes

- Installs entirely under `build-tools/lcov/local/` -- no system paths touched
- `env-setup.sh` prepends to `PATH` and sets `PERL5LIB`; both are scoped to
  the current shell and do not persist after the session ends
- System Perl is used as the interpreter; only the missing module dependencies
  are vendored, not Perl itself
- Tested on RHEL 8 x86_64 with system Perl 5.26