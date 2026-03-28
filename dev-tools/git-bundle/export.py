#!/usr/bin/env python3
# Author: Nima Shafie
"""
export.py  —  Recreate a Git super repository + all submodules from the .bundle
               files produced by bundle.py.  Suitable for air-gapped destinations.

Usage:
    python export.py

Output:
    <YYYYMMDD_HHmm>_export/
        <repo-name>/          ← fully restored repository with all branches
        export_log.txt        ← detailed log of every step

Requirements:
    Python 3.11+,  Git 2.x  —  no pip installs needed
"""

import hashlib
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
#  USER CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
# Leave empty to auto-detect the most recent *_import folder in the same directory.
IMPORT_FOLDER_OVERRIDE = ""

# 1 = abort when any SHA256 does not match;  0 = log a warning and continue
STRICT_SHA_VERIFY = 1
# ─────────────────────────────────────────────────────────────────────────────


# ═══════════════════════════════════════════════════════════════════════════════
#  COLOUR OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

import platform as _platform

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
_GREEN  = "[32m" if _COLOR else ""
_YELLOW = "[33m" if _COLOR else ""
_RED    = "[31m" if _COLOR else ""
_CYAN   = "[36m" if _COLOR else ""
_RESET  = "[0m"  if _COLOR else ""

def ok(msg: str)        -> None: print(f"{_GREEN}[OK]{_RESET}   {msg}")
def warn(msg: str)      -> None: print(f"{_YELLOW}[WARN]{_RESET} {msg}")
def print_err(msg: str) -> None: print(f"{_RED}[ERR]{_RESET}  {msg}")
def print_info(msg: str)-> None: print(f"{_CYAN}[INFO]{_RESET} {msg}")


# ═══════════════════════════════════════════════════════════════════════════════
#  LOW-LEVEL HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def git(*args, cwd: Path | None = None) -> tuple[str, str, int]:
    """Run git with *args in *cwd*.  Returns (stdout, stderr, returncode)."""
    result = subprocess.run(
        ["git"] + list(args),
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "echo"},
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def is_git_repo(path: Path) -> bool:
    return (path / ".git").exists()


# ═══════════════════════════════════════════════════════════════════════════════
#  GIT HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def local_branches(repo: Path) -> list[str]:
    out, _, _ = git("for-each-ref", "--format=%(refname:short)", "refs/heads", cwd=repo)
    return [b for b in out.splitlines() if b]


def remote_branches(repo: Path) -> list[str]:
    out, _, _ = git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin", cwd=repo)
    return [b for b in out.splitlines() if b and b not in ("origin/HEAD", "origin/origin")]


def materialize_local_branches(repo: Path) -> None:
    """
    Create a local branch for every origin/* ref.
    After cloning a bundle, all branches appear as origin/* — this converts
    them to proper local branches so the repo is fully usable offline.
    """
    current, _, _ = git("rev-parse", "--abbrev-ref", "HEAD", cwd=repo)
    for rb in remote_branches(repo):
        lb = rb[len("origin/"):]
        if lb == current:
            continue   # cannot force-update the currently checked-out branch
        git("branch", "-f", lb, rb, cwd=repo)


def default_branch(repo: Path) -> str:
    for candidate in ("main", "develop", "master"):
        _, _, rc = git("show-ref", "--verify", "--quiet", f"refs/heads/{candidate}", cwd=repo)
        if rc == 0:
            return candidate
    branches = local_branches(repo)
    return branches[0] if branches else ""


def count_tags(repo: Path) -> int:
    out, _, _ = git("tag", cwd=repo)
    return len([t for t in out.splitlines() if t])


def count_commits(repo: Path) -> str:
    out, _, rc = git("rev-list", "--all", "--count", cwd=repo)
    return out if (rc == 0 and out.isdigit()) else "0"


def dir_size_str(path: Path) -> str:
    total = float(sum(f.stat().st_size for f in path.rglob("*") if f.is_file()))
    for unit in ("B", "K", "M", "G"):
        if total < 1024:
            return f"{total:.0f}{unit}"
        total /= 1024.0
    return f"{total:.1f}T"


def airgap_repo(repo: Path) -> None:
    """
    Finalize a cloned repo for air-gapped use:
      - materialize all local branches from origin/* refs
      - remove the origin remote  (repo has no network path)
      - remove any stray local branch literally named 'origin'
    """
    materialize_local_branches(repo)

    _, _, rc = git("remote", "get-url", "origin", cwd=repo)
    if rc == 0:
        git("remote", "remove", "origin", cwd=repo)

    _, _, rc2 = git("show-ref", "--verify", "--quiet", "refs/heads/origin", cwd=repo)
    if rc2 == 0:
        git("branch", "-D", "origin", cwd=repo)


# ═══════════════════════════════════════════════════════════════════════════════
#  .GITMODULES PARSING
# ═══════════════════════════════════════════════════════════════════════════════

def parse_gitmodules(gm_path: Path) -> list[dict[str, str]]:
    """
    Parse a .gitmodules file.  Returns a list of dicts with keys
    'name', 'path', and optionally 'url'.
    """
    if not gm_path.exists():
        return []

    result = subprocess.run(
        ["git", "config", "--file", str(gm_path), "--list"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    if result.returncode != 0:
        return []

    entries: dict[str, dict[str, str]] = {}
    for line in result.stdout.splitlines():
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        parts = key.split(".")
        # key is like: submodule.<name>.<attr>
        if len(parts) < 3 or parts[0] != "submodule":
            continue
        attr = parts[-1]
        name = ".".join(parts[1:-1])   # handles dots in submodule names
        entries.setdefault(name, {"name": name})[attr] = value

    return [e for e in entries.values() if "path" in e]


# ═══════════════════════════════════════════════════════════════════════════════
#  SHA256 VERIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

def parse_verification_file(path: Path) -> dict[Path, str]:
    """
    Parse bundle_verification.txt produced by bundle.py.
    Returns {relative_bundle_path: expected_sha256}.

    Uses key:value splitting with strip() so that changes in column-padding
    inside bundle_verification.txt never break the parser.
    """
    expected: dict[Path, str] = {}
    current_file: Path | None = None

    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip()
            if ":" not in line:
                continue
            key, _, val = line.partition(":")
            key = key.strip()
            val = val.strip()
            if key == "Bundle File":
                current_file = Path(val)
            elif key == "SHA256" and current_file:
                expected[current_file] = val
                current_file = None

    return expected


def verify_sha256(import_dir: Path, log_fn) -> bool:
    """
    Compare every .bundle file against the SHA256 values recorded in
    bundle_verification.txt.  Returns True when all checksums match.
    """
    verify_file = import_dir / "bundle_verification.txt"
    if not verify_file.exists():
        log_fn("[WARN] bundle_verification.txt not found — skipping SHA256 verification")
        return True

    expected = parse_verification_file(verify_file)
    if not expected:
        log_fn("[WARN] No SHA256 entries found in bundle_verification.txt — skipping")
        return True

    all_ok   = True
    verified = 0

    for rel_path, exp_sha in expected.items():
        actual_path = import_dir / rel_path
        if not actual_path.exists():
            log_fn(f"[ERR]  Missing bundle: {rel_path}")
            all_ok = False
            continue

        actual_sha = sha256_file(actual_path)
        if actual_sha == exp_sha:
            log_fn(f"[OK]   SHA256 verified: {rel_path}")
            verified += 1
        else:
            log_fn(f"[ERR]  SHA256 MISMATCH: {rel_path}")
            log_fn(f"       expected : {exp_sha}")
            log_fn(f"       actual   : {actual_sha}")
            all_ok = False

    log_fn(f"SHA256 check complete — {verified}/{len(expected)} passed")
    return all_ok


# ═══════════════════════════════════════════════════════════════════════════════
#  RECURSIVE SUBMODULE INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

def init_submodules_recursive(
    repo_dir    : Path,
    import_dir  : Path,
    rel_prefix  : str,        # this repo's path relative to the super repo root
    counter     : list[int],  # mutable [current_index] — shared across recursion
    total       : int,        # total repos (for [N/total] display)
    log_fn,
) -> None:
    """
    Depth-first: for each submodule declared in *repo_dir*/.gitmodules,
    find its bundle in *import_dir*, clone it into the correct path,
    checkout the default branch, materialize all branches, remove origin,
    then recurse into nested submodules.
    """
    submodules = parse_gitmodules(repo_dir / ".gitmodules")
    if not submodules:
        return

    for sub in submodules:
        sub_path = sub["path"]        # relative to repo_dir
        sub_name = sub.get("name", Path(sub_path).name)

        # Full relative path from the super repo root to this submodule
        sub_rel = f"{rel_prefix}/{sub_path}" if rel_prefix else sub_path

        counter[0] += 1
        idx = counter[0]

        bundle_path = import_dir / (sub_rel + ".bundle")
        sub_dir     = repo_dir / sub_path

        print_info(f"[{idx}/{total}] [{sub_name}] : {sub_rel}")
        log_fn(f"\n{'─' * 65}")
        log_fn(f"Submodule #{idx}: {sub_rel}")

        if not bundle_path.exists():
            warn(f"[{idx}/{total}] [{sub_name}] : bundle not found — {bundle_path.name}")
            log_fn(f"Status : BUNDLE NOT FOUND at {bundle_path}")
            continue

        # Remove any stale directory before cloning
        if sub_dir.exists():
            shutil.rmtree(sub_dir)
        sub_dir.parent.mkdir(parents=True, exist_ok=True)

        _, err, rc = git("clone", str(bundle_path), str(sub_dir), "--quiet")
        if rc != 0:
            print_err(f"[{idx}/{total}] [{sub_name}] : clone failed — {err}")
            log_fn(f"Status : CLONE FAILED — {err}")
            continue

        # Checkout default branch, materialize all branches, remove origin
        db = default_branch(sub_dir)
        if db:
            git("checkout", db, cwd=sub_dir)
        airgap_repo(sub_dir)

        n_br   = len(local_branches(sub_dir))
        n_tags = count_tags(sub_dir)

        n_commits_sub = count_commits(sub_dir)
        sub_url_log, _, _ = git("config", "--get", "remote.origin.url", cwd=sub_dir)
        ok(f"[{idx}/{total}] [{sub_name}] : {n_br} branches, {n_tags} tags")
        log_fn("")
        log_fn(f"Submodule Repo #{idx}: {sub_rel}")
        log_fn("-----------------------------------------------------------------")
        log_fn(f"Cloned to      : {sub_dir}")
        log_fn(f"Branches       : {n_br}")
        log_fn(f"Tags           : {n_tags}")
        log_fn(f"Total Commits  : {n_commits_sub}")
        log_fn(f"Remote URL     : {sub_url_log or '(none)'}")
        log_fn("")

        # Register with parent so `git submodule status` shows it as initialized
        git("submodule", "init", "--", sub_path, cwd=repo_dir)
        git("config", "--local", f"submodule.{sub_name}.url",
            str(sub_dir.resolve()), cwd=repo_dir)

        # Recurse into this submodule's own submodules
        init_submodules_recursive(sub_dir, import_dir, sub_rel, counter, total, log_fn)


# ═══════════════════════════════════════════════════════════════════════════════
#  METADATA HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def read_metadata(import_dir: Path) -> dict[str, str]:
    """Parse metadata.txt (key : value lines) produced by bundle.py."""
    meta_path = import_dir / "metadata.txt"
    if not meta_path.exists():
        return {}
    result: dict[str, str] = {}
    with open(meta_path, encoding="utf-8") as fh:
        for line in fh:
            if " : " in line:
                key, _, val = line.partition(" : ")
                result[key.strip()] = val.strip()
    return result


# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    start      = datetime.now()
    script_dir = Path(__file__).parent.resolve()

    # ── locate import folder ──────────────────────────────────────────────────
    if IMPORT_FOLDER_OVERRIDE:
        import_dir = (script_dir / IMPORT_FOLDER_OVERRIDE).resolve()
    else:
        candidates = sorted(script_dir.glob("*_import"), reverse=True)
        import_dir = candidates[0] if candidates else None

    # ── export dir + log file (opened before any sys.exit so errors are logged) ──
    # We derive the export name from import; if import is missing, use a fallback.
    import_name  = import_dir.name if (import_dir and import_dir.is_dir()) else "unknown_import"
    export_name  = import_name.replace("_import", "_export")
    export_dir   = script_dir / export_name
    export_dir.mkdir(parents=True, exist_ok=True)

    # export_log.txt stays inside the export folder (bundled with the transfer).
    # logs/<timestamp>_export.txt goes to the root logs/ folder for easy access.
    timestamp2 = import_name.split("_import")[0]   # e.g. "20260310_2331"
    logs_dir   = script_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path   = export_dir / "export_log.txt"
    log_path2  = logs_dir / f"{timestamp2}_export.txt"
    log_fh     = open(log_path,  "w", encoding="utf-8")
    log_fh2    = open(log_path2, "w", encoding="utf-8")

    def log(msg: str) -> None:
        log_fh.write(msg + "\n");  log_fh.flush()
        log_fh2.write(msg + "\n"); log_fh2.flush()

    import getpass as _getpass
    try:
        _ran_by = _getpass.getuser()
    except Exception:
        _ran_by = "unknown"

    try:
        _export_main(
            start      = start,
            script_dir = script_dir,
            import_dir = import_dir,
            export_dir = export_dir,
            ran_by     = _ran_by,
            log        = log,
        )
    except SystemExit:
        raise
    except Exception as exc:
        import traceback
        msg = f"FATAL ERROR: {exc}"
        print_err(msg)
        log("")
        log(msg)
        log(traceback.format_exc())
        sys.exit(1)
    finally:
        log_fh.close()
        log_fh2.close()

    print_info(f"Log written to : logs/{log_path2.name}")


def _export_main(*, start, script_dir, import_dir, export_dir, ran_by, log) -> None:
    """Real export logic — separated so log_fh always closes via finally."""

    if not import_dir or not import_dir.is_dir():
        msg = "Could not find an *_import folder."
        print_err(msg)
        print_err("Set IMPORT_FOLDER_OVERRIDE at the top of export.py, or run bundle.py first.")
        log(f"[ERR]  {msg}")
        sys.exit(1)

    log("=================================================================")
    log("Git Export Log")
    log("=================================================================")
    log(f"Generated      : {start.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"Ran by         : {ran_by}")
    log(f"Import Folder  : {import_dir}")
    log(f"Export Folder  : {export_dir}")
    log(f"Strict SHA     : {STRICT_SHA_VERIFY}")
    log("=================================================================")
    log("")

    print()
    print_info(f"Import : {import_dir.name}/")
    print_info(f"Export : {export_dir.name}/")
    print()

    # ── identify super repo name from metadata ────────────────────────────────
    meta      = read_metadata(import_dir)
    repo_name = meta.get("Super Repo", "")

    if not repo_name:
        # Fallback: the only bundle at the import root level
        top_bundles = list(import_dir.glob("*.bundle"))
        if len(top_bundles) == 1:
            repo_name = top_bundles[0].stem
        else:
            print_err("Cannot determine super repository name.")
            print_err("metadata.txt is missing or malformed.")
            sys.exit(1)

    super_bundle = import_dir / f"{repo_name}.bundle"
    if not super_bundle.exists():
        print_err(f"Super repository bundle not found: {super_bundle}")
        sys.exit(1)

    # Total repos = super (1) + every other bundle
    all_bundles = list(import_dir.rglob("*.bundle"))
    total       = len(all_bundles)   # used for [N/total] display

    # ── SHA256 verification ───────────────────────────────────────────────────
    print_info("Verifying SHA256 checksums...")
    log("\n── SHA256 Verification ──────────────────────────────────────────")

    sha_ok = verify_sha256(import_dir, log)

    if not sha_ok:
        if STRICT_SHA_VERIFY:
            print_err("SHA256 verification failed.  Aborting.")
            print_err("Set STRICT_SHA_VERIFY = 0 to skip this check.")
            sys.exit(1)
        else:
            warn("SHA256 verification had failures — continuing (STRICT_SHA_VERIFY=0)")
    else:
        ok(f"All {total} bundle(s) verified")

    print()

    # ── clone super repository ────────────────────────────────────────────────
    repo_dir = export_dir / repo_name

    print_info(f"[1/{total}] [{repo_name}] : (super repository)")
    log(f"\n{'═' * 65}")
    log(f"Repo #1: {repo_name} (super)")
    log("=" * 65)

    if repo_dir.exists():
        shutil.rmtree(repo_dir)

    _, err, rc = git("clone", str(super_bundle), str(repo_dir), "--quiet")
    if rc != 0:
        print_err(f"[1/{total}] [{repo_name}] : clone failed — {err}")
        log(f"Status : CLONE FAILED — {err}")
        sys.exit(1)

    # Checkout default branch + materialize all branches + remove origin
    db = default_branch(repo_dir)
    if db:
        git("checkout", db, cwd=repo_dir)
    airgap_repo(repo_dir)

    n_br   = len(local_branches(repo_dir))
    n_tags = count_tags(repo_dir)

    n_commits_super = count_commits(repo_dir)
    ok(f"[1/{total}] [{repo_name}] : {n_br} branches, {n_tags} tags")
    log("")
    log("=================================================================")
    log(f"SUPER REPOSITORY: {repo_name}")
    log("=================================================================")
    log(f"Cloned to      : {repo_dir}")
    log(f"Branches       : {n_br}")
    log(f"Tags           : {n_tags}")
    log(f"Total Commits  : {n_commits_super}")
    log("")

    # ── recursively initialize submodules ─────────────────────────────────────
    counter = [1]   # starts at 1 (super repo was index 1)

    init_submodules_recursive(
        repo_dir   = repo_dir,
        import_dir = import_dir,
        rel_prefix = "",
        counter    = counter,
        total      = total,
        log_fn     = log,
    )

    restored = counter[0] - 1   # how many submodules were processed

    # ── final summary ─────────────────────────────────────────────────────────
    elapsed    = (datetime.now() - start).total_seconds()
    mins, secs = int(elapsed // 60), int(elapsed % 60)

    ok(f"Time           : {mins}m {secs}s")
    print()

    total_size = dir_size_str(export_dir)
    sub_bundle_count = len([b for b in import_dir.rglob("*.bundle")
                            if b.name != f"{repo_name}.bundle"])

    log("")
    log("=================================================================")
    log("SUMMARY")
    log("=================================================================")
    log(f"Total Export Size              : {total_size}")
    log(f"Super Repository               : {repo_name}")
    log(f"Submodule Bundles Discovered   : {sub_bundle_count}")
    log(f"Submodule Bundles Restored     : {restored}")
    log(f"Repository Path                : {repo_dir}")
    log(f"Time Taken                     : {mins}m {secs}s")
    log(f"Script Completed               : {datetime.now().strftime('%Y%m%d_%H%M')}")
    log("=================================================================")

    ok(f"Export folder  : {export_dir.name}/")
    ok(f"Total size     : {total_size}")
    ok(f"Super repo     : {repo_name}")
    ok(f"Submodules     : {restored} restored")


if __name__ == "__main__":
    main()