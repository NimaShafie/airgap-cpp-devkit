#!/usr/bin/env python3
"""
tests/verify_test.py

Verifies that bundle.py and export.py correctly captured and restored the
full-test-repo fixture created by create_test_repo.py.

What is checked
──────────────────────────────────────────────────────────────────────────────
BUNDLE CHECKS (against *_import/ folder):
  1. All expected .bundle files exist (including branch-specific submodules)
  2. SHA256 values in bundle_verification.txt match the actual bundle files
  3. Every bundle passes `git bundle verify`

EXPORT CHECKS (against *_export/full-test-repo/):
  4. Super repo     — 4 branches, 4 tags, 0 remotes
  5. user-service   — 4 branches, 3 tags, 0 remotes
  6. payment-service — 4 branches, 3 tags, 0 remotes
  7. database-lib   — 3 branches, 2 tags, 0 remotes
  8. cache-lib      — 3 branches, 2 tags, 0 remotes
  9. logger-lib     — 3 branches, 2 tags, 0 remotes
 10. Branch-specific bundles exist (notification-service, feature-flags-lib)
 11. Correct submodule set on main  (user-service + payment-service present)
 12. No remotes in any exported repo (air-gap compliance)
 13. Default branch is checked out in each exported repo
──────────────────────────────────────────────────────────────────────────────

Usage:
    python tests/verify_test.py

Exits with code 0 when all checks pass, 1 otherwise.

Requirements:
    Python 3.11+,  Git 2.x
"""

import hashlib
import os
import platform as _platform
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path


# ═══════════════════════════════════════════════════════════════════════════════
#  COLOUR OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

def _supports_color() -> bool:
    if _platform.system() == "Windows":
        try:
            import ctypes
            kernel = ctypes.windll.kernel32        # type: ignore[attr-defined]
            kernel.SetConsoleMode(kernel.GetStdHandle(-11), 7)
            return True
        except Exception:
            return False
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()

_COLOR  = _supports_color()
_GREEN  = "\033[32m" if _COLOR else ""
_YELLOW = "\033[33m" if _COLOR else ""
_RED    = "\033[31m" if _COLOR else ""
_CYAN   = "\033[36m" if _COLOR else ""
_RESET  = "\033[0m"  if _COLOR else ""

def ok(msg: str)        -> None: print(f"{_GREEN}[OK]{_RESET}   {msg}")
def warn(msg: str)      -> None: print(f"{_YELLOW}[WARN]{_RESET} {msg}")
def print_err(msg: str) -> None: print(f"{_RED}[ERR]{_RESET}  {msg}")
def print_info(msg: str)-> None: print(f"{_CYAN}[INFO]{_RESET} {msg}")


# ═══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def git(*args, cwd: Path | None = None) -> tuple[str, int]:
    """Run git; return (stdout, returncode)."""
    result = subprocess.run(
        ["git"] + list(args),
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )
    return result.stdout.strip(), result.returncode


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def local_branches(repo: Path) -> list[str]:
    out, _ = git("for-each-ref", "--format=%(refname:short)", "refs/heads", cwd=repo)
    # Exclude any spurious local branch literally named "origin"
    return [b for b in out.splitlines() if b and b != "origin"]


def tags(repo: Path) -> list[str]:
    out, _ = git("tag", cwd=repo)
    return [t for t in out.splitlines() if t]


def remotes(repo: Path) -> list[str]:
    out, _ = git("remote", cwd=repo)
    return [r for r in out.splitlines() if r]


def current_branch(repo: Path) -> str:
    out, _ = git("rev-parse", "--abbrev-ref", "HEAD", cwd=repo)
    return out


def is_git_repo(path: Path) -> bool:
    """Return True only if *path* exists AND is an operable git repository."""
    if not path.exists():
        return False
    _, rc = git("rev-parse", "--is-inside-work-tree", cwd=path)
    return rc == 0


def gitlink_paths(repo: Path, branch: str) -> list[str]:
    """Return submodule paths (mode 160000) for *branch* in *repo*."""
    out, rc = git("ls-tree", "-r", "--full-name", branch, cwd=repo)
    if rc != 0:
        return []
    return [line.split(None, 3)[3]
            for line in out.splitlines()
            if len(line.split(None, 3)) == 4 and line.split()[0] == "160000"]


# ═══════════════════════════════════════════════════════════════════════════════
#  RESULT TRACKING
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class Results:
    passed: list[str] = field(default_factory=list)
    failed: list[str] = field(default_factory=list)
    log_fn: object    = field(default=None, repr=False)

    def _log(self, msg: str) -> None:
        if self.log_fn:
            self.log_fn(msg)

    def ok(self, msg: str) -> None:
        self.passed.append(msg)
        print(f"  {_GREEN}[PASS]{_RESET} {msg}")
        self._log(f"  [PASS] {msg}")

    def fail(self, msg: str) -> None:
        self.failed.append(msg)
        print(f"  {_RED}[FAIL]{_RESET} {msg}")
        self._log(f"  [FAIL] {msg}")

    def check(self, condition: bool, pass_msg: str, fail_msg: str) -> None:
        if condition:
            self.ok(pass_msg)
        else:
            self.fail(fail_msg)


# ═══════════════════════════════════════════════════════════════════════════════
#  BUNDLE CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

# All bundle paths relative to the import directory root.
# Includes branch-specific submodules that should be captured by bundle.py.
EXPECTED_BUNDLES: list[str] = [
    # super repo
    "full-test-repo.bundle",
    # main-branch submodules
    "services/user-service.bundle",
    "services/payment-service.bundle",
    "services/user-service/lib/database.bundle",
    "services/user-service/lib/database/utils/logger.bundle",
    "services/payment-service/lib/cache.bundle",
    # develop-branch-only submodules (must be captured by cross-branch scan)
    "services/notification-service.bundle",
    "services/user-service/lib/feature-flags.bundle",
]


def check_bundles(import_dir: Path, results: Results) -> None:
    log = results._log
    print()
    print("─" * 62)
    print(" Bundle checks")
    print("─" * 62)
    log("")
    log("─" * 65)
    log("Bundle checks")
    log("─" * 65)

    # 1. All expected bundle files exist
    for rel in EXPECTED_BUNDLES:
        bp = import_dir / rel
        results.check(
            bp.exists(),
            f"Bundle exists : {rel}",
            f"Bundle MISSING: {rel}",
        )

    # 2. SHA256 values match
    verify_file = import_dir / "bundle_verification.txt"
    if not verify_file.exists():
        results.fail("bundle_verification.txt not found in import folder")
    else:
        expected_shas = _parse_verification_file(verify_file)
        if not expected_shas:
            results.fail("bundle_verification.txt exists but has no SHA256 entries")
        else:
            for rel_path, exp_sha in expected_shas.items():
                actual_path = import_dir / rel_path
                if not actual_path.exists():
                    results.fail(f"SHA256 check: bundle missing for {rel_path}")
                    continue
                actual_sha = sha256_file(actual_path)
                results.check(
                    actual_sha == exp_sha,
                    f"SHA256 match  : {rel_path}",
                    f"SHA256 MISMATCH: {rel_path}",
                )

    # 3. Every .bundle file passes `git bundle verify`
    for bp in sorted(import_dir.rglob("*.bundle")):
        rel = str(bp.relative_to(import_dir))
        _, rc = git("bundle", "verify", str(bp))
        results.check(rc == 0,
                      f"git bundle verify OK  : {rel}",
                      f"git bundle verify FAIL: {rel}")


def _parse_verification_file(path: Path) -> dict[Path, str]:
    """Parse bundle_verification.txt → {relative_path: sha256}."""
    expected: dict[Path, str] = {}
    current: Path | None = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip()
            if ":" not in line:
                continue
            key, _, val = line.partition(":")
            key = key.strip()
            val = val.strip()
            if key == "Bundle File":
                current = Path(val)
            elif key == "SHA256" and current:
                expected[current] = val
                current = None
    return expected


# ═══════════════════════════════════════════════════════════════════════════════
#  EXPORT CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class RepoSpec:
    """Expected state of one exported repo."""
    label       : str
    rel_path    : str          # relative to export_root (the full-test-repo/ dir)
    branches    : int
    tags        : int
    default_br  : str = "main"


# Repos that must be initialized on the default (main) branch of the export
MAIN_BRANCH_REPOS: list[RepoSpec] = [
    RepoSpec("super repo",      "",                                    4, 4, "main"),
    RepoSpec("user-service",    "services/user-service",               4, 3, "main"),
    RepoSpec("payment-service", "services/payment-service",            4, 3, "main"),
    RepoSpec("database-lib",    "services/user-service/lib/database",  3, 2, "main"),
    RepoSpec("cache-lib",       "services/payment-service/lib/cache",  3, 2, "main"),
    RepoSpec("logger-lib",      "services/user-service/lib/database/utils/logger", 3, 2, "main"),
]


def check_exports(export_root: Path, results: Results) -> None:
    log = results._log
    print()
    print("─" * 62)
    print(" Export checks")
    print("─" * 62)
    log("")
    log("─" * 65)
    log("Export checks")
    log("─" * 65)

    for spec in MAIN_BRANCH_REPOS:
        repo = export_root / spec.rel_path if spec.rel_path else export_root
        label = spec.label
        print(f"\n  Checking: {label}")
        log(f"\nChecking: {label}")

        if not is_git_repo(repo):
            results.fail(f"{label}: not a git repo at {repo}")
            continue

        # Branch count
        br = local_branches(repo)
        results.check(
            len(br) == spec.branches,
            f"{label}: branches = {len(br)} (expected {spec.branches})",
            f"{label}: branches = {len(br)}, expected {spec.branches}  got {br}",
        )

        # Tag count
        tg = tags(repo)
        results.check(
            len(tg) == spec.tags,
            f"{label}: tags = {len(tg)} (expected {spec.tags})",
            f"{label}: tags = {len(tg)}, expected {spec.tags}  got {tg}",
        )

        # No remotes (air-gap compliance)
        rm = remotes(repo)
        results.check(
            len(rm) == 0,
            f"{label}: no remotes (air-gapped)",
            f"{label}: has remotes — {rm}",
        )

        # Default branch is checked out
        cb = current_branch(repo)
        results.check(
            cb == spec.default_br,
            f"{label}: checked out '{cb}' (expected '{spec.default_br}')",
            f"{label}: checked out '{cb}', expected '{spec.default_br}'",
        )


def check_branch_submodule_sets(export_root: Path, results: Results) -> None:
    """
    Verify that the super repo's tree declares the correct submodule set
    per branch — this confirms bundle.py captured the right branch-specific
    submodule references AND that all branches were preserved.
    """
    log = results._log
    print()
    print("─" * 62)
    print(" Branch-specific submodule set checks")
    print("─" * 62)
    log("")
    log("─" * 65)
    log("Branch-specific submodule set checks")
    log("─" * 65)

    expected_by_branch = {
        "main": {
            "services/user-service",
            "services/payment-service",
        },
        "develop": {
            "services/user-service",
            "services/notification-service",
        },
        "feature/api-gateway": {
            "services/user-service",
            "services/notification-service",
        },
        "release/2.0": {
            "services/user-service",
            "services/notification-service",
        },
    }

    for branch, expected_paths in expected_by_branch.items():
        actual = set(gitlink_paths(export_root, branch))
        results.check(
            actual == expected_paths,
            f"super/{branch}: submodule set correct {sorted(actual)}",
            f"super/{branch}: expected {sorted(expected_paths)}, got {sorted(actual)}",
        )

    # Verify user-service branches have the correct nested submodule sets
    us_repo = export_root / "services" / "user-service"
    if is_git_repo(us_repo):
        us_expected = {
            "main":         {"lib/database"},
            "develop":      {"lib/database", "lib/feature-flags"},
            "feature/oauth":{"lib/database"},
            "release/2.0":  {"lib/database"},
        }
        for branch, expected_paths in us_expected.items():
            actual = set(gitlink_paths(us_repo, branch))
            results.check(
                actual == expected_paths,
                f"user-service/{branch}: submodule set correct {sorted(actual)}",
                f"user-service/{branch}: expected {sorted(expected_paths)}, got {sorted(actual)}",
            )


def check_branch_specific_bundles_restored(import_dir: Path,
                                           export_root: Path,
                                           results: Results) -> None:
    """
    Verify that bundles for branch-only submodules (notification-service,
    feature-flags-lib) were captured.  Even though export.py only initializes
    the default branch, the bundle files must exist so develop can be restored
    later.
    """
    log = results._log
    print()
    print("─" * 62)
    print(" Branch-specific bundle capture checks")
    print("─" * 62)
    log("")
    log("─" * 65)
    log("Branch-specific bundle capture checks")
    log("─" * 65)

    branch_only = [
        "services/notification-service.bundle",
        "services/user-service/lib/feature-flags.bundle",
    ]
    for rel in branch_only:
        bp = import_dir / rel
        results.check(
            bp.exists(),
            f"Branch-only bundle captured: {rel}",
            f"Branch-only bundle MISSING : {rel}  (bundle.py missed a non-default branch submodule)",
        )


# ═══════════════════════════════════════════════════════════════════════════════
#  LOCATE MOST RECENT IMPORT / EXPORT DIRECTORIES
# ═══════════════════════════════════════════════════════════════════════════════

def find_latest(search_root: Path, suffix: str) -> Path | None:
    """Return the most recent folder matching *_<suffix> inside search_root."""
    candidates = sorted(search_root.glob(f"*_{suffix}"), reverse=True)
    return candidates[0] if candidates else None


# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    from datetime import datetime
    import getpass as _getpass

    start      = datetime.now()
    script_dir = Path(__file__).parent.resolve()
    root_dir   = script_dir.parent          # project root (one level above tests/)

    import_dir = find_latest(root_dir, "import")
    export_dir = find_latest(root_dir, "export")

    # ── Log file setup ────────────────────────────────────────────────────────
    logs_dir = root_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path = logs_dir / f"{start.strftime('%Y%m%d_%H%M')}_verify_test.txt"
    log_fh   = open(log_path, "w", encoding="utf-8")

    def log(msg: str) -> None:
        log_fh.write(msg + "\n")
        log_fh.flush()

    try:
        _ran_by = _getpass.getuser()
    except Exception:
        _ran_by = "unknown"

    log("=================================================================")
    log("Verify Test Log")
    log("=================================================================")
    log(f"Generated      : {start.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"Ran by         : {_ran_by}")
    log(f"Import dir     : {import_dir.name if import_dir else '(not found)'}")
    log(f"Export dir     : {export_dir.name if export_dir else '(not found)'}")
    log("=================================================================")
    log("")

    try:
        _run_checks(root_dir, import_dir, export_dir, log)
    except Exception as exc:
        import traceback
        msg = f"FATAL ERROR: {exc}"
        print_err(msg)
        log("")
        log(msg)
        log(traceback.format_exc())
        sys.exit(1)
    finally:
        elapsed = (datetime.now() - start).total_seconds()
        mins, secs = int(elapsed // 60), int(elapsed % 60)
        log("")
        log(f"Time Taken     : {mins}m {secs}s")
        log(f"Log written to : {log_path}")
        log_fh.close()

    print()
    print_info(f"Log written to : logs/{log_path.name}")


def _run_checks(root_dir: Path, import_dir, export_dir, log) -> None:
    """Separated from main() so the log always closes via finally."""
    print()
    print("=" * 62)
    print(" Verifying Full Test Repository Transfer")
    print("=" * 62)
    log("=================================================================")
    log("Verifying Full Test Repository Transfer")
    log("=================================================================")

    if not import_dir:
        print_err("No *_import folder found.  Run bundle.py first.")
        log("[ERR]  No *_import folder found.")
        sys.exit(1)
    if not export_dir:
        print_err("No *_export folder found.  Run export.py first.")
        log("[ERR]  No *_export folder found.")
        sys.exit(1)

    export_root = export_dir / "full-test-repo"
    if not export_root.exists():
        print_err(f"Expected export at: {export_root}")
        print_err("Make sure export.py completed successfully.")
        log(f"[ERR]  Expected export at: {export_root}")
        sys.exit(1)

    print(f"\n  Import : {import_dir.name}/")
    print(f"  Export : {export_dir.name}/{export_root.name}")
    log(f"Import : {import_dir.name}/")
    log(f"Export : {export_dir.name}/{export_root.name}")
    log("")

    results = Results(log_fn=log)

    check_bundles(import_dir, results)
    check_exports(export_root, results)
    check_branch_submodule_sets(export_root, results)
    check_branch_specific_bundles_restored(import_dir, export_root, results)

    # ── summary ───────────────────────────────────────────────────────────────
    total  = len(results.passed) + len(results.failed)
    passed = len(results.passed)
    failed = len(results.failed)

    print()
    print("=" * 62)
    print(" Summary")
    print("=" * 62)
    print(f"  Passed : {passed}/{total}")
    print(f"  Failed : {failed}/{total}")
    log("")
    log("=================================================================")
    log("Summary")
    log("=================================================================")
    log(f"Passed : {passed}/{total}")
    log(f"Failed : {failed}/{total}")

    if failed == 0:
        print()
        print(f"  {_GREEN}ALL CHECKS PASSED{_RESET}")
        print()
        log("")
        log("ALL CHECKS PASSED")
    else:
        print()
        print("  FAILURES:")
        log("")
        log("FAILURES:")
        for msg in results.failed:
            print(f"    {_RED}✗{_RESET} {msg}")
            log(f"  ✗ {msg}")
        print()
        print("  Common causes:")
        print("    - bundle.py missed a submodule (check cross-branch scanning)")
        print("    - export.py didn't materialize all local branches from origin/*")
        print("    - A submodule was not initialized before bundling")
        sys.exit(1)


if __name__ == "__main__":
    main()