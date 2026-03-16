#!/usr/bin/env python3
# Author: Nima Shafie
"""
bundle.py  —  Bundle a Git super repository (with all submodules at any depth)
               into .bundle files for air-gapped transfer.

Usage:
    python bundle.py

Output:
    <YYYYMMDD_HHmm>_import/
        <repo-name>.bundle
        <path/to/submodule>.bundle    (mirrors submodule folder structure)
        bundle_verification.txt       (SHA256 + stats for every bundle)
        metadata.txt                  (import instructions)

Requirements:
    Python 3.11+,  Git 2.x  —  no pip installs needed
"""

import hashlib
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
#  USER CONFIGURATION
#
#  Set REPO_PATH to the Git super repository you want to bundle.
#
#  To target a real repository, replace the default below.  Examples:
#
#      Windows  ->  targeting a folder called "git-bundle" on your Desktop:
#          REPO_PATH = Path(r"C:\Users\YourName\Desktop\git-bundle")
#
#      Linux    ->  same idea:
#          REPO_PATH = Path.home() / "Desktop" / "git-bundle"
#
#  The default below points at the test repository created by running:
#      python tests/create_test_repo.py
#  No changes needed if you just want to test the workflow first.
# ─────────────────────────────────────────────────────────────────────────────
REPO_PATH = Path(__file__).parent / "tests" / "test_repos" / "full-test-repo"
# ─────────────────────────────────────────────────────────────────────────────


# ═══════════════════════════════════════════════════════════════════════════════
#  COLOUR OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

import platform as _platform

def _supports_color() -> bool:
    """True when the terminal is likely to render ANSI escape codes."""
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

def git(*args, cwd: Path | None = None, check: bool = False) -> tuple[str, str, int]:
    """Run git with *args in *cwd*.  Returns (stdout, stderr, returncode).
    If check=True, raises RuntimeError on non-zero exit."""
    result = subprocess.run(
        ["git"] + list(args),
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "echo"},
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def human_size(path: Path) -> str:
    """File size as a human-readable string, e.g. '2.3M'."""
    b = float(path.stat().st_size)
    for unit in ("B", "K", "M", "G"):
        if b < 1024:
            return f"{b:.0f}{unit}"
        b /= 1024.0
    return f"{b:.1f}T"


def dir_size_str(path: Path) -> str:
    """Total size of all files under *path* as a human-readable string."""
    total = float(sum(f.stat().st_size for f in path.rglob("*") if f.is_file()))
    for unit in ("B", "K", "M", "G"):
        if total < 1024:
            return f"{total:.0f}{unit}"
        total /= 1024.0
    return f"{total:.1f}T"


def is_git_repo(path: Path) -> bool:
    """
    True only when *path* is a fully operable git repository.

    A .git FILE (used by submodules) may point at a deleted modules directory.
    Simply checking existence returns True for these broken repos and causes
    git to crash with "not a git repository" when we try to use them.
    """
    if not (path / ".git").exists():
        return False
    _, _, rc = git("rev-parse", "--git-dir", cwd=path)
    return rc == 0


# ═══════════════════════════════════════════════════════════════════════════════
#  GIT HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

_fetched_repos: set[Path] = set()   # guard: fetch at most once per repo per run


def fetch_once(repo: Path) -> None:
    """Fetch all refs from origin exactly once per repo.  No-op if no remote."""
    key = repo.resolve()
    if key in _fetched_repos:
        return
    _fetched_repos.add(key)

    url, _, rc = git("config", "--get", "remote.origin.url", cwd=repo)
    if rc != 0 or not url:
        return

    git("-c", "protocol.file.allow=always",
        "fetch", "--all", "--no-tags", "--quiet", "--no-progress",
        cwd=repo)


def local_branches(repo: Path) -> list[str]:
    out, _, _ = git("for-each-ref", "--format=%(refname:short)", "refs/heads", cwd=repo)
    return [b for b in out.splitlines() if b]


def remote_branches(repo: Path) -> list[str]:
    """Return origin/* branch names, excluding tracking sentinels."""
    out, _, _ = git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin", cwd=repo)
    return [b for b in out.splitlines() if b and b not in ("origin/HEAD", "origin/origin")]


def all_refs_for_scan(repo: Path) -> list[str]:
    """
    All refs to scan for gitlinks: local branches first, then any origin/* refs
    whose corresponding local branch does not yet exist.  This catches submodules
    that only appear on a branch not yet materialized locally.
    """
    local  = local_branches(repo)
    remote = remote_branches(repo)
    local_set = set(local)
    extra = [rb for rb in remote if rb[len("origin/"):] not in local_set]
    return local + extra


def materialize_local_branches(repo: Path) -> None:
    """Create a local branch for every origin/* ref (skips currently checked-out branch)."""
    current, _, _ = git("rev-parse", "--abbrev-ref", "HEAD", cwd=repo)
    for rb in remote_branches(repo):
        lb = rb[len("origin/"):]
        if lb == current:
            continue   # git will not force-update the checked-out branch
        git("branch", "-f", lb, rb, cwd=repo)


def default_branch(repo: Path) -> str:
    """Return the most appropriate default branch name for *repo*."""
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


def branch_commit_summary(repo: Path) -> list[tuple[str, str, str]]:
    """Return (branch, subject, date) for the most recent commit on every local branch."""
    rows: list[tuple[str, str, str]] = []
    for branch in sorted(local_branches(repo)):
        out, _, rc = git("log", "-1", "--format=%s%ci", branch, cwd=repo)
        if rc == 0 and "" in out:
            subject, date = out.split("", 1)
            rows.append((branch, subject.strip(), date.strip()))
        else:
            rows.append((branch, "(no commits)", ""))
    return rows


# ═══════════════════════════════════════════════════════════════════════════════
#  SUBMODULE DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════════

def submodule_paths_from_gitmodules(repo: Path) -> list[str]:
    """Read the on-disk .gitmodules and return declared submodule paths."""
    gm = repo / ".gitmodules"
    if not gm.exists():
        return []
    out, _, rc = git("config", "--file", str(gm),
                     "--get-regexp", r"^submodule\..*\.path$", cwd=repo)
    if rc != 0:
        return []
    return [line.split(None, 1)[1].strip()
            for line in out.splitlines() if len(line.split(None, 1)) == 2]


def submodule_paths_from_all_branches(repo: Path) -> dict[str, str]:
    """
    Scan every ref for tree entries with mode 160000 (gitlinks).
    Returns {submodule_path: first_ref_that_contains_it}.

    This catches submodules that exist only on non-default branches.
    """
    refs = all_refs_for_scan(repo)
    seen: dict[str, str] = {}
    for ref in refs:
        out, _, rc = git("ls-tree", "-r", "--full-name", ref, cwd=repo)
        if rc != 0:
            continue
        for line in out.splitlines():
            parts = line.split(None, 3)
            if len(parts) == 4 and parts[0] == "160000":
                path = parts[3]
                if path not in seen:
                    seen[path] = ref
    return seen


def submodule_paths_from_committed_tree(modules_dir: Path) -> list[str]:
    """
    Read the .gitmodules content from the COMMITTED tree (HEAD:.gitmodules)
    of a modules-dir repo and return the declared submodule paths.

    This is immune to alternates contamination: even if refs in the modules-dir
    are contaminated (pointing to super-repo commits), HEAD itself always points
    to the submodule's own checked-out commit — whose .gitmodules lists only
    THIS submodule's nested submodules (not the super-repo's).

    Falls back to git ls-tree gitlinks if no .gitmodules blob exists.
    """
    # Try reading .gitmodules from the committed HEAD tree
    content, _, rc = git("show", "HEAD:.gitmodules", cwd=modules_dir)
    if rc == 0 and content.strip():
        import re
        return re.findall(r"^\s*path\s*=\s*(.+)$", content, re.MULTILINE)

    # Fallback: use git ls-tree on HEAD directly (HEAD should be the correct
    # submodule commit — only TAGS are contaminated, not HEAD/branch refs)
    out, _, rc = git("ls-tree", "-r", "--full-name", "HEAD", cwd=modules_dir)
    if rc != 0:
        return []
    paths = []
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) == 4 and parts[0] == "160000":
            paths.append(parts[3])
    return paths


def gitdirs_from_modules(modules_dir: Path, prefix: str) -> list[tuple["Path", str]]:
    """
    For a modules-dir (bare-like) repo, discover nested submodule gitdirs.

    Strategy (in order of reliability):
    1. Read submodule paths from HEAD:.gitmodules in the committed tree —
       HEAD is always the correct submodule commit, immune to tag contamination.
    2. For each path found, check if a nested gitdir already exists on disk.
    3. If the gitdir doesn't exist, try to create it using the URL from the
       modules-dir's config or the committed .gitmodules content.

    This correctly finds lib/cache inside payment-service even when the
    modules/ subdirectory was deleted by create_test_repo's branch-cycling.
    """
    sub_paths = submodule_paths_from_committed_tree(modules_dir)

    # Also scan modules/ subdirectory for any existing gitdirs (belt-and-suspenders)
    existing: dict[str, Path] = {}
    nested_root = modules_dir / "modules"
    if nested_root.is_dir():
        for head_file in sorted(nested_root.rglob("HEAD")):
            gitdir = head_file.parent
            if (gitdir / "config").exists():
                rel = gitdir.relative_to(nested_root).as_posix()
                existing[rel] = gitdir

    results: list[tuple[Path, str]] = []
    for sub_path in sub_paths:
        new_prefix = f"{prefix}/{sub_path}" if prefix else sub_path
        if sub_path in existing:
            results.append((existing[sub_path], new_prefix))
        else:
            # Nested gitdir doesn't exist on disk — read URL from committed
            # .gitmodules blob and queue the URL for _fresh_clone in the BFS.
            # We return a sentinel Path("__url__:<url>") that the BFS will
            # recognise and handle by cloning.
            url_out, _, rc = git("show", f"HEAD:.gitmodules", cwd=modules_dir)
            if rc == 0:
                import re
                # Find the url for this specific submodule path
                block_re = re.compile(
                    r'\[submodule\s+"([^"]+)"\].*?(?=\[submodule|\Z)',
                    re.DOTALL
                )
                for m in block_re.finditer(url_out):
                    block = m.group(0)
                    if re.search(r"^\s*path\s*=\s*" + re.escape(sub_path) + r"\s*$",
                                 block, re.MULTILINE):
                        um = re.search(r"^\s*url\s*=\s*(.+)$", block, re.MULTILINE)
                        if um:
                            url = um.group(1).strip()
                            results.append((Path(f"__url__:{url}"), new_prefix))
                            break
    return results


def discover_submodules(repo: Path) -> dict[str, str]:
    """
    Return {submodule_path: branch_hint} for every submodule discoverable
    in *repo*, combining .gitmodules and full cross-branch tree scanning.
    """
    from_branches = submodule_paths_from_all_branches(repo)

    # .gitmodules on the current branch may list paths not in any tree scan
    db = default_branch(repo)
    for p in submodule_paths_from_gitmodules(repo):
        if p not in from_branches:
            from_branches[p] = db

    return from_branches


# ═══════════════════════════════════════════════════════════════════════════════
#  SUBMODULE INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

def _git_dir_of(repo: Path) -> Path:
    """
    Return the actual git directory for *repo*.

    Three cases:
      Normal working tree    → repo/.git  is a DIRECTORY  → return it
      Submodule working tree → repo/.git  is a TEXT FILE  containing
                               "gitdir: <relative-path>" → resolve that path
      Bare / modules dir     → repo has HEAD but no .git child → return repo
    """
    git_entry = repo / ".git"
    if git_entry.is_dir():
        return git_entry
    if git_entry.is_file():
        content = git_entry.read_text(encoding="utf-8").strip()
        if content.startswith("gitdir: "):
            rel = content[len("gitdir: "):]
            return (repo / rel).resolve()
    # Bare repo or modules dir — the directory itself is the git dir
    return repo


def _modules_dir(repo: Path, sub_path: str) -> Path:
    """
    Return the git-modules directory for a submodule at *sub_path* inside *repo*.

    Correctly handles both normal working-tree repos (where repo/.git is a dir)
    and submodule working trees (where repo/.git is a FILE pointing to the real
    git dir inside the super repo's .git/modules/ hierarchy).
    """
    return _git_dir_of(repo) / "modules" / Path(sub_path)


def ensure_initialized(repo: Path, sub_path: str,
                       branch_hint: str, log_fn) -> bool:
    """
    Ensure the submodule at *sub_path* is registered in .git/modules/.

    For branch-specific submodules (e.g. notification-service on develop only),
    we temporarily checkout that branch, run submodule update --init, then
    restore the original branch.  After restoring, git removes the submodule
    working directory — but .git/modules/ survives.  We therefore check
    .git/modules/ for success, not the working tree.

    Also removes stale .git FILEs (dead pointers from earlier branch inits)
    so git can write a clean pointer on re-init.
    """
    target = repo / sub_path

    if is_git_repo(target):                    # working tree present and operable
        return True
    if _modules_dir(repo, sub_path).exists():  # already registered, just not checked out
        return True

    stale_git = target / ".git"
    if stale_git.is_file():
        stale_git.unlink()
        log_fn(f"[INFO] Removed stale .git pointer at {target}")

    orig, _, _ = git("rev-parse", "--abbrev-ref", "HEAD", cwd=repo)
    switched = False

    try:
        if branch_hint and branch_hint != orig:
            _, _, rc = git("checkout", branch_hint, cwd=repo)
            switched = (rc == 0)

        git("-c", "protocol.file.allow=always",
            "submodule", "update", "--init", "--", sub_path, cwd=repo)

    except Exception as exc:
        log_fn(f"[WARN] Exception while initializing '{sub_path}': {exc}")

    finally:
        if switched:
            git("checkout", orig, cwd=repo)
            # Restore any submodule working trees that were cleaned up when we
            # switched to branch_hint.  For example, switching the super-repo to
            # "develop" causes git to remove "services/payment-service/" (which is
            # main-only) from the working tree.  Switching back to main puts the
            # gitlink back in the index but does NOT recreate the directory.
            # This update re-checks-out every submodule that belongs on the
            # original branch, ensuring the BFS can still see payment-service etc.
            git("-c", "protocol.file.allow=always",
                "submodule", "update", "--init", "--checkout", "--recursive",
                cwd=repo, check=False)

    return _modules_dir(repo, sub_path).exists()


# ═══════════════════════════════════════════════════════════════════════════════
#  BUNDLING
# ═══════════════════════════════════════════════════════════════════════════════

def prune_unreachable_tags(repo: Path) -> list[str]:
    """
    Delete any tag whose target commit is NOT reachable from local branches or HEAD.

    This removes super-repo tags that leak into submodule gitdirs via git's
    local-clone alternates mechanism.  For modules-dir repos (which have no local
    branches), we fall back to checking reachability from HEAD.
    """
    deleted: list[str] = []
    branches_exist, _, _ = git("for-each-ref", "--format=%(refname:short)", "refs/heads", cwd=repo)
    has_branches = bool(branches_exist.strip())

    out, _, _ = git("for-each-ref", "--format=%(refname:short)", "refs/tags", cwd=repo)
    for tag in [t for t in out.splitlines() if t]:
        commit, _, rc = git("rev-parse", f"{tag}^{{commit}}", cwd=repo)
        if rc != 0:
            # Object unreachable even via alternates — definitely foreign, delete it
            git("tag", "-d", tag, cwd=repo, check=False)
            deleted.append(tag)
            continue

        if has_branches:
            # Normal working-tree repo: keep tags reachable from any local branch
            branches_out, _, _ = git("branch", "--contains", commit, cwd=repo)
            if not branches_out.strip():
                git("tag", "-d", tag, cwd=repo, check=False)
                deleted.append(tag)
        else:
            # Modules-dir repo (no local branches): keep tags reachable from HEAD
            # HEAD is the checked-out submodule commit — the correct anchor point.
            # git merge-base --is-ancestor <commit> HEAD returns 0 if reachable.
            _, _, reach_rc = git("merge-base", "--is-ancestor", commit, "HEAD", cwd=repo)
            if reach_rc != 0:
                git("tag", "-d", tag, cwd=repo, check=False)
                deleted.append(tag)
    return deleted


def bundle_repo(repo: Path, bundle_path: Path) -> dict:
    """
    Create a git bundle for *repo* at *bundle_path*.
    --all captures every branch, tag, and remote-tracking ref.
    Returns a dict with verification status and stats.

    *repo* may be either:
      • A normal working-tree repository (repo/.git exists)
      • A bare / modules-dir repository (has HEAD but no .git child)
        — these are queued by the BFS when the submodule only exists on a
          non-default branch, so the working tree is absent but git history
          is fully accessible in the modules dir.
    """
    bundle_path.parent.mkdir(parents=True, exist_ok=True)

    # Bare / modules-dir detection: git dir IS the directory (no .git child).
    is_bare = not (repo / ".git").exists() and (repo / "HEAD").exists()

    # One fetch to pull in any missing refs, then materialize all as local branches
    fetch_once(repo)
    materialize_local_branches(repo)
    prune_unreachable_tags(repo)   # remove tags contaminated via alternates

    if not is_bare:
        # Land on the default branch before creating the bundle
        db = default_branch(repo)
        if db:
            git("checkout", db, cwd=repo)

    branches = local_branches(repo)
    if not branches and not is_bare:
        git("branch", "main", "HEAD", cwd=repo)
        branches = local_branches(repo)

    # Explicitly enumerate local branches and tags rather than using --all.
    # --all would include refs/remotes/origin/* AND any tag refs that leaked in
    # from git's local-clone alternates (which can cause super-repo tags to
    # appear in submodule gitdirs).  Explicit refs/heads/* + refs/tags/* gives
    # exactly what we want: every local branch and every locally-created tag.
    bundle_refs_out, _, _ = git(
        "for-each-ref", "--format=%(refname)",
        "refs/heads", "refs/tags", cwd=repo,
    )
    bundle_refs = [r for r in bundle_refs_out.splitlines() if r]
    # HEAD must be first so git clone can determine the default branch to checkout.
    # Without it, git clone picks an arbitrary ref — often a tag — as HEAD.
    bundle_refs = ["HEAD"] + bundle_refs

    if not bundle_refs:
        raise RuntimeError("No local branches or tags found to bundle")

    _, err, rc = git("bundle", "create", str(bundle_path), *bundle_refs, cwd=repo)
    if rc != 0:
        raise RuntimeError(err or "git bundle create failed")

    _, _, vrc = git("bundle", "verify", str(bundle_path), cwd=repo)

    tag_list = sorted(git("tag", cwd=repo)[0].splitlines())
    return {
        "verified"   : vrc == 0,
        "branches"   : len(branches),
        "branch_list": branches,
        "tags"       : len(tag_list),
        "tag_list"   : tag_list,
        "commits"    : count_commits(repo),
        "size"       : human_size(bundle_path),
        "sha256"     : sha256_file(bundle_path),
    }


# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    start      = datetime.now()
    repo_path  = Path(REPO_PATH).expanduser().resolve()
    script_dir = Path(__file__).parent.resolve()
    timestamp  = start.strftime("%Y%m%d_%H%M")
    import_dir = script_dir / f"{timestamp}_import"
    import_dir.mkdir(parents=True, exist_ok=True)

    # ── Log files ─────────────────────────────────────────────────────────────
    # bundle_verification.txt  → inside the import folder (used by export.py)
    # logs/<timestamp>_bundle.txt → root-level logs/ folder for easy access
    logs_dir  = script_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path  = import_dir / "bundle_verification.txt"
    log_path2 = logs_dir / f"{timestamp}_bundle.txt"
    log_fh    = open(log_path,  "w", encoding="utf-8")
    log_fh2   = open(log_path2, "w", encoding="utf-8")

    def log(msg: str) -> None:
        log_fh.write(msg + "\n");  log_fh.flush()
        log_fh2.write(msg + "\n"); log_fh2.flush()

    repo_name = repo_path.name

    import getpass as _getpass
    try:
        _ran_by = _getpass.getuser()
    except Exception:
        _ran_by = "unknown"

    try:
        _bundle_main(
            repo_path  = repo_path,
            repo_name  = repo_name,
            script_dir = script_dir,
            timestamp  = timestamp,
            import_dir = import_dir,
            start      = start,
            ran_by     = _ran_by,
            log        = log,
        )
    except SystemExit:
        raise                      # allow sys.exit codes to propagate normally
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


def _bundle_main(*, repo_path, repo_name, script_dir, timestamp,
                 import_dir, start, ran_by, log) -> None:
    """Real bundling logic — separated so log_fh always closes via finally."""

    # ── validate user config ──────────────────────────────────────────────────
    if not repo_path.exists():
        msg = f"Repository not found: {repo_path}"
        print_err(msg)
        print_err("Edit REPO_PATH at the top of bundle.py")
        log(f"[ERR]  {msg}")
        sys.exit(1)
    if not is_git_repo(repo_path):
        msg = f"Not a git repository: {repo_path}"
        print_err(msg)
        log(f"[ERR]  {msg}")
        sys.exit(1)

    # Auto-detect remote URL — written to log for reference only, no network access.
    remote_url, _, _ = git("config", "--get", "remote.origin.url", cwd=repo_path)
    remote_git_address = remote_url if remote_url else "(no remote configured)"

    log("=================================================================")
    log("Git Bundle Verification Log")
    log("=================================================================")
    log(f"Generated      : {start.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"Ran by         : {ran_by}")
    log(f"Source         : {repo_path}")
    log(f"Remote Address : {remote_git_address}")
    log(f"Output         : {import_dir}")
    log("=================================================================")
    log("")

    print()
    print_info(f"Source : {repo_path}")
    print_info(f"Output : {import_dir}")
    print()

    # ── Phase 1: BFS discovery of all repos ───────────────────────────────────
    #
    # Performance note: fetch_once() is called exactly once per repo (guarded
    # by _fetched_repos).  git ls-tree is the only tree scan — no redundant
    # fetches inside the bundle step.
    #
    print_info("Discovering repositories...")

    # Temp dir for fresh clones of branch-specific submodules.
    # Must outlive the BFS so nested submodule discovery can use the clones.
    _bfs_tmp_ctx = tempfile.TemporaryDirectory()
    bfs_tmp      = Path(_bfs_tmp_ctx.name)
    _clone_n     = [0]

    def _fresh_clone(parent_repo: Path, sub_path: str) -> "Path | None":
        """
        Clone a submodule directly from its source URL into a clean temp dir.

        Modules-dirs have Remote URL: (none) — git does not always write
        remote.origin.url into the modules-dir config for locally-cloned repos.
        Instead we read the URL from the parent repo's .gitmodules file, which
        always contains the original source URL set by 'git submodule add'.
        """
        # Try .gitmodules in the parent working tree first
        url, _, rc = git("config", "--file", ".gitmodules",
                         f"submodule.{sub_path}.url", cwd=parent_repo)
        if rc != 0 or not url.strip():
            # Fallback: try the resolved URL from git config (after 'submodule init')
            url, _, rc = git("config", "--get",
                             f"submodule.{sub_path}.url", cwd=parent_repo)
        if rc != 0 or not url.strip():
            log(f"[DEBUG] _fresh_clone({sub_path}): no URL found in .gitmodules (rc={rc})")
            return None
        log(f"[DEBUG] _fresh_clone({sub_path}): URL={url.strip()}")
        clone_path = bfs_tmp / f"clone_{_clone_n[0]}"
        _clone_n[0] += 1
        _, _, crc = git("-c", "protocol.file.allow=always",
                        "clone", "--no-local", url.strip(), str(clone_path))
        if crc != 0 or not is_git_repo(clone_path):
            return None
        # Initialize nested submodules so discovery (e.g. lib/cache) works
        git("-c", "protocol.file.allow=always",
            "submodule", "update", "--init", "--recursive",
            cwd=clone_path, check=False)
        return clone_path

    queue    : list[tuple[Path, str]] = [(repo_path, "")]
    visited  : set[Path]              = set()
    all_repos: list[tuple[Path, str]] = []      # super repo first, then submodules in BFS order

    while queue:
        repo, prefix = queue.pop(0)
        abs_repo = repo.resolve()

        if abs_repo in visited:
            continue
        visited.add(abs_repo)
        all_repos.append((repo, prefix))

        # Fetch + materialize branches once so cross-branch scanning is complete
        fetch_once(repo)
        materialize_local_branches(repo)

        # Belt-and-suspenders: initialize any registered submodule gitdirs one
        # level deep so that _modules_dir() checks below are reliable.
        repo_is_working_tree = (repo / ".git").exists()

        if not repo_is_working_tree:
            # ── modules-dir repo ─────────────────────────────────────────────
            # Do NOT call discover_submodules here.  A modules-dir's object store
            # is linked via alternates to the super repo's objects, so refs
            # materialised inside the modules-dir can point to super-repo commits
            # whose trees contain the super-repo's gitlinks — not this repo's.
            # Scanning modules/ directly is immune to this contamination.
            nested = gitdirs_from_modules(repo, prefix)
            log(f"Scanned: {repo} | prefix='{prefix}' | nested submodules found: {len(nested)}")
            for nested_gitdir, nested_prefix in nested:
                # Handle sentinel: __url__:<url> means we need a fresh clone
                str_gitdir = str(nested_gitdir)
                if str_gitdir.startswith("__url__:"):
                    url = str_gitdir[len("__url__:"):]
                    log(f"[INFO] Fresh clone needed for {nested_prefix} (url={url})")
                    clone_path = bfs_tmp / f"clone_{_clone_n[0]}"
                    _clone_n[0] += 1
                    _, _, crc = git("-c", "protocol.file.allow=always",
                                   "clone", "--no-local", url, str(clone_path))
                    if crc != 0 or not is_git_repo(clone_path):
                        log(f"[WARN] Fresh clone failed for {nested_prefix} (skipping)")
                        continue
                    # Init nested submodules of the fresh clone
                    git("-c", "protocol.file.allow=always",
                        "submodule", "update", "--init", "--recursive",
                        cwd=clone_path, check=False)
                    log(f"[INFO] Fresh clone created: {clone_path} → {nested_prefix}")
                    queue.append((clone_path, nested_prefix))
                    continue

                abs_gitdir = nested_gitdir.resolve()
                in_bfs_tmp = abs_gitdir.parts[:len(bfs_tmp.resolve().parts)] == bfs_tmp.resolve().parts
                if not in_bfs_tmp:
                    try:
                        abs_gitdir.relative_to(repo_path.resolve())
                    except ValueError:
                        log(f"[WARN] Skipping nested gitdir outside super root: {abs_gitdir}")
                        continue
                if abs_gitdir in visited:
                    continue
                queue.append((nested_gitdir, nested_prefix))
        else:
            # ── working-tree repo ─────────────────────────────────────────────
            # Pre-init submodule gitdirs so _modules_dir() checks are reliable.
            git("-c", "protocol.file.allow=always",
                "submodule", "update", "--init",
                cwd=repo, check=False)

            submod_map = discover_submodules(repo)   # {submodule_path: branch_hint}
            log(f"Scanned: {repo} | prefix='{prefix}' | submodules found: {len(submod_map)}")

            for sub_path, branch_hint in sorted(submod_map.items()):
                abs_sub = (repo / sub_path).resolve()

                # Strict containment check — repos inside bfs_tmp (fresh clones) are trusted
                in_bfs_tmp = abs_sub.parts[:len(bfs_tmp.resolve().parts)] == bfs_tmp.resolve().parts
                if not in_bfs_tmp:
                    try:
                        abs_sub.relative_to(repo_path.resolve())
                    except ValueError:
                        log(f"[WARN] Skipping submodule outside super root: {abs_sub}")
                        continue

                if abs_sub in visited:
                    continue

                # Debug: log exact state for every submodule
                _igr       = is_git_repo(abs_sub)
                _git_ent   = (abs_sub / ".git")
                _git_exist = _git_ent.exists()
                _git_type  = ("dir" if _git_ent.is_dir() else "file" if _git_ent.is_file() else "none") if _git_exist else "missing"
                _mod_dir   = _modules_dir(repo, sub_path)
                log(f"[DEBUG] {sub_path}: abs={abs_sub} | .git={_git_type} | is_git_repo={_igr} | modules_dir_exists={_mod_dir.exists()}")

                if not _igr and not _mod_dir.exists():
                    if not ensure_initialized(repo, sub_path, branch_hint, log):
                        log(f"[WARN] Could not initialize submodule: {sub_path} (skipping)")
                        continue

                if is_git_repo(abs_sub):
                    effective_repo = abs_sub
                else:
                    # No working tree — clone fresh from the source URL.
                    # Read URL from parent repo's .gitmodules (not the modules-dir
                    # config, which often has Remote URL: none for local clones).
                    clone = _fresh_clone(repo, sub_path)
                    if clone:
                        log(f"[INFO] Fresh clone for {sub_path}: {clone}")
                        effective_repo = clone
                    else:
                        mod_dir = _modules_dir(repo, sub_path)
                        if mod_dir.exists():
                            effective_repo = mod_dir
                        else:
                            log(f"[WARN] Could not resolve repo for submodule: {sub_path} (skipping)")
                            continue

                new_prefix = f"{prefix}/{sub_path}" if prefix else sub_path
                queue.append((effective_repo, new_prefix))

    total     = len(all_repos)
    sub_count = total - 1
    print_info(f"Found {total} repositor{'y' if total == 1 else 'ies'} "
          f"(super repo + {sub_count} submodule(s))")
    print()

    # ── Phase 2: Bundle every repo ────────────────────────────────────────────
    failed = 0

    for idx, (repo, prefix) in enumerate(all_repos, start=1):
        is_super  = prefix == ""
        name      = repo_name if is_super else repo.name
        disp_path = "(super repository)" if is_super else prefix

        # Bundle path mirrors the submodule's relative path inside the import folder
        if is_super:
            bundle_path = import_dir / f"{repo_name}.bundle"
        else:
            bundle_path = import_dir / (prefix + ".bundle")

        print_info(f"[{idx}/{total}] [{name}] : {disp_path}")
        log(f"\n{'=' * 65}")
        log(f"Repo #{idx}: {prefix or repo_name}")
        log("=" * 65)

        try:
            binfo = bundle_repo(repo, bundle_path)

            status  = "VERIFIED" if binfo["verified"] else "UNVERIFIED"
            summary = (f"{binfo['branches']} branches, {binfo['tags']} tags, "
                       f"{binfo['commits']} commits, {binfo['size']}")

            if binfo["verified"]:
                ok(f"[{idx}/{total}] [{name}] : {summary}")
            else:
                warn(f"[{idx}/{total}] [{name}] : {summary}")

            # Full details to the log file
            rel_bundle = bundle_path.relative_to(import_dir)
            if is_super:
                log("")
                log("=================================================================")
                log(f"SUPER REPOSITORY: {repo_name}")
                log("=================================================================")
            else:
                log("")
                log(f"Submodule Repo #{idx}: {prefix}")
                log("-----------------------------------------------------------------")
                sub_url, _, _ = git("config", "--get", "remote.origin.url", cwd=repo)
                log(f"Remote URL       : {sub_url or '(none)'}")
            log(f"Bundle File      : {rel_bundle}")
            log(f"Verification     : {status}")
            log(f"SHA256           : {binfo['sha256']}")
            log(f"File Size        : {binfo['size']}")
            log(f"Total Commits    : {binfo['commits']}")
            log(f"Tags             : {', '.join(binfo['tag_list']) if binfo['tag_list'] else '(none)'}")
            log(f"Path in Export   : ./{rel_bundle}")
            log("")
            log(f"Branches ({binfo['branches']}):")
            for _br, _subj, _date in branch_commit_summary(repo):
                log(f"  {_br}")
                log(f"    Latest commit : {_subj}")
                log(f"    Commit date   : {_date}")

        except Exception as exc:
            print_err(f"[{idx}/{total}] [{name}] : FAILED — {exc}")
            log(f"Status : FAILED — {exc}")
            failed += 1

    # ── metadata.txt ──────────────────────────────────────────────────────────
    meta_path = import_dir / "metadata.txt"
    with open(meta_path, "w", encoding="utf-8") as mf:
        mf.write("=" * 65 + "\n")
        mf.write("Git Bundle Metadata\n")
        mf.write("=" * 65 + "\n")
        mf.write(f"Timestamp      : {timestamp}\n")
        mf.write(f"Source Path    : {repo_path}\n")
        mf.write(f"Remote Address : {remote_git_address}\n")
        mf.write(f"Super Repo     : {repo_name}\n")
        mf.write(f"Total Repos    : {total}\n")
        mf.write(f"Submodules     : {sub_count}\n")
        mf.write("\nBUNDLE FILES:\n")
        mf.write("-" * 65 + "\n")
        for p in sorted(import_dir.rglob("*.bundle")):
            mf.write(f"  {p.relative_to(import_dir)}\n")
        mf.write("\nIMPORT INSTRUCTIONS:\n")
        mf.write("-" * 65 + "\n")
        mf.write("1. Transfer this entire folder to the destination network\n")
        mf.write("2. Run: python export.py\n")
        mf.write(f"3. Expected export folder: {timestamp}_export/\n")

    # ── final summary ─────────────────────────────────────────────────────────
    elapsed        = (datetime.now() - start).total_seconds()
    mins, secs     = int(elapsed // 60), int(elapsed % 60)
    total_size     = dir_size_str(import_dir)
    ok_count       = total - failed

    print()
    ok(f"Bundled {ok_count}/{total} repositories")
    ok(f"Total size  : {total_size}")
    ok(f"Output      : {import_dir.name}/")
    ok(f"Time        : {mins}m {secs}s")
    print()

    log("")
    log("=================================================================")
    log("SUMMARY")
    log("=================================================================")
    log(f"Total Export Size          : {total_size}")
    log(f"Super Repository Bundles   : 1")
    log(f"Submodule Repo Bundles     : {sub_count}")
    log(f"Successful                 : {ok_count}")
    log(f"Failed                     : {failed}")
    log(f"Time Taken                 : {mins}m {secs}s")
    log(f"Script Completed           : {datetime.now().strftime('%Y%m%d_%H%M')}")
    log("=================================================================")

    # Clean up temp clones used for fresh working-tree bundling
    _bfs_tmp_ctx.cleanup()

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()