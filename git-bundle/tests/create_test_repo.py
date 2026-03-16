#!/usr/bin/env python3
# Author: Nima Shafie
"""
tests/create_test_repo.py

Creates a comprehensive local Git test fixture for validating bundle.py and
export.py end-to-end.  All repos live under <script_dir>/../test/ so they
are isolated from the tool scripts themselves.

Test structure created
──────────────────────────────────────────────────────────────────────────────
BASE REPOS (bare ingredients, nested later):
  full-test-base-user-service/        4 branches, 3 tags
  full-test-base-payment-service/     4 branches, 3 tags
  full-test-base-notification-service/  3 branches, 2 tags  ← develop-only
  full-test-base-database-lib/        3 branches, 2 tags
  full-test-base-cache-lib/           3 branches, 2 tags
  full-test-base-logger-lib/          3 branches, 2 tags
  full-test-base-feature-flags-lib/   2 branches, 2 tags  ← user-service develop-only

SUPER REPO (full-test-repo/):
  main    → services/user-service, services/payment-service
  develop → services/user-service, services/notification-service
             (user-service on develop also gets lib/feature-flags)
  feature/api-gateway  (branched from develop)
  release/2.0          (branched from develop)
  4 branches, 4 tags total

NESTING SUMMARY:
  services/user-service/
    lib/database/         ← all user-service branches
      utils/logger/       ← all database branches
    lib/feature-flags/    ← user-service develop branch ONLY
  services/payment-service/
    lib/cache/            ← all payment-service branches
  services/notification-service/   ← super-repo develop branch ONLY

Total unique repos to bundle: 8
  1 super repo  +  7 submodule repos
──────────────────────────────────────────────────────────────────────────────

Usage:
    python tests/create_test_repo.py

Requirements:
    Python 3.11+,  Git 2.x
"""

import os
import platform as _platform
import shutil
import subprocess
import sys
from pathlib import Path
from textwrap import dedent


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

def git(*args, cwd: Path | None = None, check: bool = True) -> str:
    """Run a git command; return stdout.  Raises on non-zero unless check=False."""
    env = {**os.environ,
           "GIT_TERMINAL_PROMPT": "0",
           "GIT_AUTHOR_NAME": "Test",
           "GIT_AUTHOR_EMAIL": "test@example.com",
           "GIT_COMMITTER_NAME": "Test",
           "GIT_COMMITTER_EMAIL": "test@example.com"}
    result = subprocess.run(
        ["git"] + list(args),
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed in {cwd}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout.strip()


def init_repo(path: Path) -> None:
    """Create a new git repo with sane defaults for local file:// submodule use."""
    path.mkdir(parents=True, exist_ok=True)
    git("init", cwd=path)
    git("config", "--local", "protocol.file.allow", "always", cwd=path)
    git("config", "--local", "core.longpaths", "true", cwd=path)
    # Use a consistent initial branch name regardless of global config
    git("checkout", "-b", "main", cwd=path, check=False)


def write_commit(repo: Path, files: dict[str, str], message: str,
                 tag: str | None = None) -> None:
    """Write *files* (name→content), stage everything, commit, optionally tag."""
    for name, content in files.items():
        (repo / name).parent.mkdir(parents=True, exist_ok=True)
        (repo / name).write_text(dedent(content), encoding="utf-8")
    git("add", ".", cwd=repo)
    git("commit", "-m", message, cwd=repo)
    if tag:
        git("tag", tag, cwd=repo)


def add_submodule(parent: Path, sub_path: str, sub_repo: Path) -> None:
    """Add *sub_repo* as a submodule at *sub_path* inside *parent*."""
    url = sub_repo.resolve().as_uri()          # file:// URI — portable on all OSes
    (parent / sub_path).parent.mkdir(parents=True, exist_ok=True)
    git("-c", "protocol.file.allow=always",
        "submodule", "add", url, sub_path, cwd=parent)


def remove_submodule(parent: Path, sub_path: str) -> None:
    """
    Cleanly remove a submodule from *parent* at *sub_path*.
    Handles both normal and Windows-NTFS locking edge cases.
    """
    # 1. Deinit clears .git/config entries
    git("submodule", "deinit", "-f", "--", sub_path, cwd=parent, check=False)
    # 2. Remove gitlink from index
    git("rm", "-f", "--cached", "--", sub_path, cwd=parent, check=False)
    # 3. Remove section from .gitmodules
    gm = parent / ".gitmodules"
    if gm.exists():
        # Find the submodule name for this path
        out = git("config", "--file", str(gm), "--list", cwd=parent, check=False)
        name = None
        for line in out.splitlines():
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            parts = key.split(".")
            if len(parts) >= 3 and parts[0] == "submodule" and parts[-1] == "path" and val == sub_path:
                name = ".".join(parts[1:-1])
                break
        if name:
            git("config", "-f", str(gm),
                "--remove-section", f"submodule.{name}", cwd=parent, check=False)
        # If .gitmodules is now empty, delete it
        content = gm.read_text(encoding="utf-8").strip()
        if not content:
            gm.unlink()
        else:
            git("add", ".gitmodules", cwd=parent, check=False)
    # 4. Remove the working directory itself
    target = parent / sub_path
    if target.exists():
        shutil.rmtree(target, ignore_errors=True)
    # 5. Remove leftover git modules metadata
    mods = parent / ".git" / "modules" / sub_path
    if mods.exists():
        shutil.rmtree(mods, ignore_errors=True)


def checkout(repo: Path, branch: str, new: bool = False,
             from_branch: str | None = None) -> None:
    if new:
        if from_branch:
            git("checkout", "-b", branch, from_branch, cwd=repo)
        else:
            git("checkout", "-b", branch, cwd=repo)
    else:
        git("checkout", branch, cwd=repo)


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — BASE REPOS
# ═══════════════════════════════════════════════════════════════════════════════

def create_user_service(base: Path) -> Path:
    path = base / "full-test-base-user-service"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {"user.py": '''\
        class User:
            version = "1.0.0"
            def login(self): return "logged in"
        '''}, "Initial user service v1.0", tag="v1.0.0")

    checkout(path, "develop", new=True)
    write_commit(path, {"user.py": '''\
        class User:
            version = "1.5.0"
            def login(self): return "logged in"
            def logout(self): return "logged out"
        '''}, "Add logout feature", tag="v1.5.0")

    checkout(path, "feature/oauth", new=True)
    write_commit(path, {"oauth.py": '''\
        def oauth_login(): return "oauth"
        '''}, "Add OAuth support")

    checkout(path, "develop")
    checkout(path, "release/2.0", new=True)
    write_commit(path, {"user.py": '''\
        class User:
            version = "2.0.0"
            def login(self): return "logged in v2"
            def logout(self): return "logged out"
        '''}, "Release v2.0", tag="v2.0.0")

    checkout(path, "main")
    ok("user-service          : 4 branches (main, develop, feature/oauth, release/2.0)  3 tags")
    return path


def create_payment_service(base: Path) -> Path:
    path = base / "full-test-base-payment-service"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {"payment.py": '''\
        class Payment:
            version = "1.0.0"
            def process(self): return "processed"
        '''}, "Initial payment service v1.0", tag="v1.0.0")

    checkout(path, "develop", new=True)
    write_commit(path, {"payment.py": '''\
        class Payment:
            version = "1.2.0"
            def process(self): return "processed"
            def refund(self): return "refunded"
        '''}, "Add refund feature", tag="v1.2.0")

    checkout(path, "feature/stripe", new=True)
    write_commit(path, {"stripe.py": '''\
        def stripe_payment(): return "stripe"
        '''}, "Add Stripe integration")

    checkout(path, "main")
    checkout(path, "hotfix/1.0.1", new=True, from_branch="main")
    write_commit(path, {"payment.py": '''\
        class Payment:
            version = "1.0.1"
            def process(self): return "processed (fixed)"
        '''}, "Hotfix v1.0.1", tag="v1.0.1")

    checkout(path, "main")
    ok("payment-service       : 4 branches (main, develop, feature/stripe, hotfix/1.0.1)  3 tags")
    return path


def create_notification_service(base: Path) -> Path:
    path = base / "full-test-base-notification-service"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {"notify.py": '''\
        class Notify:
            version = "1.0.0"
            def send(self): return "sent"
        '''}, "Initial notification service v1.0", tag="v1.0.0")

    checkout(path, "develop", new=True)
    write_commit(path, {"notify.py": '''\
        class Notify:
            version = "1.2.0"
            def send(self): return "sent"
            def schedule(self): return "scheduled"
        '''}, "Add schedule support", tag="v1.2.0")

    checkout(path, "feature/sms", new=True)
    write_commit(path, {"sms.py": '''\
        def sms_send(): return "sms"
        '''}, "Add SMS support")

    checkout(path, "main")
    ok("notification-service  : 3 branches (main, develop, feature/sms)  2 tags")
    return path


def create_database_lib(base: Path) -> Path:
    path = base / "full-test-base-database-lib"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {"db.py": '''\
        class Database:
            version = "1.0"
            def connect(self): return "connected"
        '''}, "Initial database library", tag="v1.0")

    checkout(path, "develop", new=True)
    write_commit(path, {"db.py": '''\
        class Database:
            version = "2.0"
            def connect(self): return "connected"
            def disconnect(self): return "disconnected"
        '''}, "Add disconnect", tag="v2.0")

    checkout(path, "feature/pool", new=True)
    write_commit(path, {"pool.py": '''\
        class ConnectionPool: pass
        '''}, "Add connection pool")

    checkout(path, "main")
    ok("database-lib          : 3 branches (main, develop, feature/pool)  2 tags")
    return path


def create_cache_lib(base: Path) -> Path:
    path = base / "full-test-base-cache-lib"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {"cache.py": '''\
        class Cache:
            version = "1.0"
            def set(self, k, v): pass
            def get(self, k): pass
        '''}, "Initial cache library", tag="v1.0")

    checkout(path, "develop", new=True)
    write_commit(path, {"cache.py": '''\
        class Cache:
            version = "1.5"
            def set(self, k, v): pass
            def get(self, k): pass
            def delete(self, k): pass
        '''}, "Add delete method", tag="v1.5")

    checkout(path, "feature/redis", new=True)
    write_commit(path, {"redis.py": '''\
        def redis_cache(): return "redis"
        '''}, "Add Redis backend")

    checkout(path, "main")
    ok("cache-lib             : 3 branches (main, develop, feature/redis)  2 tags")
    return path


def create_logger_lib(base: Path) -> Path:
    path = base / "full-test-base-logger-lib"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {"logger.py": '''\
        class Logger:
            def log(self, msg): print(msg)
        '''}, "Initial logger", tag="v1.0")

    checkout(path, "develop", new=True)
    write_commit(path, {"logger.py": '''\
        class Logger:
            def log(self, msg): print(msg)
            def error(self, msg): print("ERROR:", msg)
        '''}, "Add error logging", tag="v2.0")

    checkout(path, "feature/json", new=True)
    write_commit(path, {"logger.py": '''\
        import json
        class Logger:
            def log(self, msg): print(json.dumps(msg))
            def error(self, msg): print("ERROR:", msg)
        '''}, "Add JSON logging")

    checkout(path, "main")
    ok("logger-lib            : 3 branches (main, develop, feature/json)  2 tags")
    return path


def create_feature_flags_lib(base: Path) -> Path:
    path = base / "full-test-base-feature-flags-lib"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {"flags.py": '''\
        class Flags:
            enabled = False
        '''}, "Initial feature flags lib", tag="v1.0.0")

    checkout(path, "develop", new=True)
    write_commit(path, {"flags.py": '''\
        class Flags:
            enabled = True
        '''}, "Enable flags by default in develop", tag="v1.1.0")

    checkout(path, "main")
    ok("feature-flags-lib     : 2 branches (main, develop)  2 tags")
    return path


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 2 — WIRE UP NESTING
# ═══════════════════════════════════════════════════════════════════════════════

def wire_logger_into_database(database: Path, logger: Path) -> None:
    """Add logger-lib into ALL branches of database-lib at utils/logger."""
    # Add on main
    checkout(database, "main")
    add_submodule(database, "utils/logger", logger)
    git("commit", "-m", "Add logger as nested submodule", cwd=database)

    # Merge forward so all branches have it
    for branch in ("develop", "feature/pool"):
        checkout(database, branch)
        git("merge", "main", "--no-edit", "-m",
            f"Merge logger submodule into {branch}", cwd=database)

    checkout(database, "main")
    ok("database-lib ← logger-lib wired on all branches")


def wire_database_into_user_service(user: Path, database: Path) -> None:
    """
    Add database-lib into ALL branches of user-service at lib/database.
    Also add feature-flags-lib into user-service/develop ONLY.
    """
    # Add on main
    checkout(user, "main")
    add_submodule(user, "lib/database", database)
    git("commit", "-m", "Add database-lib as nested submodule", cwd=user)

    # Propagate to other branches
    for branch in ("develop", "feature/oauth", "release/2.0"):
        checkout(user, branch)
        git("merge", "main", "--no-edit", "-m",
            f"Merge database submodule into {branch}", cwd=user)

    checkout(user, "main")
    ok("user-service ← database-lib wired on all branches")


def wire_feature_flags_into_user_service_develop(user: Path, feature_flags: Path) -> None:
    """Add feature-flags-lib into user-service ONLY on the develop branch."""
    checkout(user, "develop")
    add_submodule(user, "lib/feature-flags", feature_flags)
    git("commit", "-m", "Add feature-flags-lib (develop only)", cwd=user)
    checkout(user, "main")
    ok("user-service/develop ← feature-flags-lib (develop only)")


def wire_cache_into_payment_service(payment: Path, cache: Path) -> None:
    """Add cache-lib into ALL branches of payment-service at lib/cache."""
    checkout(payment, "main")
    add_submodule(payment, "lib/cache", cache)
    git("commit", "-m", "Add cache-lib as nested submodule", cwd=payment)

    for branch in ("develop", "feature/stripe", "hotfix/1.0.1"):
        checkout(payment, branch)
        git("merge", "main", "--no-edit", "-m",
            f"Merge cache submodule into {branch}", cwd=payment)

    checkout(payment, "main")
    ok("payment-service ← cache-lib wired on all branches")


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 3 — SUPER REPO
# ═══════════════════════════════════════════════════════════════════════════════

def create_super_repo(base: Path, user: Path, payment: Path,
                      notification: Path) -> Path:
    path = base / "full-test-repo"
    if path.exists():
        shutil.rmtree(path)
    init_repo(path)

    write_commit(path, {
        "README.md": '''\
            # Full Test Application
            Version: 1.0.0
            A comprehensive microservices application for testing git bundles.
            ''',
        ".gitignore": '''\
            *.pyc
            __pycache__/
            .env
            ''',
    }, "Initial commit v1.0", tag="v1.0.0")

    # ── main branch ──────────────────────────────────────────────────────────
    # user-service + payment-service
    add_submodule(path, "services/user-service", user)
    git("commit", "-m", "Add user-service (main)", cwd=path)

    add_submodule(path, "services/payment-service", payment)
    git("commit", "-m", "Add payment-service (main)", cwd=path)
    git("tag", "v1.5.0", cwd=path)

    # ── develop branch ───────────────────────────────────────────────────────
    # Replace payment-service with notification-service
    checkout(path, "develop", new=True)
    write_commit(path, {"README.md": '''\
        # Full Test Application
        Version: 2.0.0-dev
        A comprehensive microservices application for testing git bundles.
        ## Development Version
        New features in development.
        '''}, "Update to v2.0-dev", tag="v2.0.0-dev")

    remove_submodule(path, "services/payment-service")
    git("commit", "-m", "Remove payment-service (develop branch-specific)", cwd=path)

    add_submodule(path, "services/notification-service", notification)
    git("commit", "-m", "Add notification-service (develop branch-specific)", cwd=path)

    # ── feature/api-gateway branch (from develop) ─────────────────────────
    checkout(path, "feature/api-gateway", new=True, from_branch="develop")
    write_commit(path, {"gateway.py": '''\
        class APIGateway:
            def route(self): return "routed"
        '''}, "Add API gateway")

    # ── release/2.0 branch (from develop) ────────────────────────────────
    checkout(path, "release/2.0", new=True, from_branch="develop")
    write_commit(path, {"README.md": '''\
        # Full Test Application
        Version: 2.0.0
        A comprehensive microservices application for testing git bundles.
        ## Production Release
        Ready for deployment.
        '''}, "Release v2.0", tag="v2.0.0")

    checkout(path, "main")
    ok("super repo (full-test-repo) created")
    ok("4 branches: main, develop, feature/api-gateway, release/2.0")
    ok("4 tags    : v1.0.0, v1.5.0, v2.0.0-dev, v2.0.0")
    return path


# ═══════════════════════════════════════════════════════════════════════════════
#  STEP 4 — INITIALIZE SUBMODULES ON ALL SUPER-REPO BRANCHES
# ═══════════════════════════════════════════════════════════════════════════════

def init_all_branches(super_repo: Path, log=None) -> None:
    """
    Walk every branch of the super repo and initialize the correct set of
    submodules.  This ensures that `git submodule status` works correctly on
    every branch without cross-branch contamination.

    Strategy:
      1. For each branch, deinit everything.
      2. Remove working-directory remnants that are not in this branch's tree.
      3. Sync + init only the submodules that appear in this branch's tree.
    """
    if log is None:
        log = lambda msg: None  # no-op if called without a log handle
    branches_out = git("for-each-ref", "--format=%(refname:short)", "refs/heads",
                       cwd=super_repo)
    branches = [b for b in branches_out.splitlines() if b]
    orig = git("rev-parse", "--abbrev-ref", "HEAD", cwd=super_repo)

    for branch in sorted(branches):
        checkout(super_repo, branch)

        # What submodule paths does this branch's tree declare?
        expected = set()
        ls = git("ls-tree", "-r", "--full-name", branch, cwd=super_repo,
                 check=False)
        for line in ls.splitlines():
            parts = line.split(None, 3)
            if len(parts) == 4 and parts[0] == "160000":
                expected.add(parts[3])

        # Deinit to clear cached state
        git("submodule", "deinit", "-f", "--all",
            cwd=super_repo, check=False)

        # Remove leftover working directories that should not be here
        for git_file in super_repo.rglob(".git"):
            if git_file == super_repo / ".git":
                continue
            sub_dir = git_file.parent
            try:
                rel = sub_dir.relative_to(super_repo).as_posix()
            except ValueError:
                continue
            # Keep if this rel path, or any of its parents, is in expected
            is_expected = any(
                rel == e or rel.startswith(e + "/")
                for e in expected
            )
            if not is_expected:
                shutil.rmtree(sub_dir, ignore_errors=True)
                modules_dir = super_repo / ".git" / "modules" / rel
                if modules_dir.exists():
                    shutil.rmtree(modules_dir, ignore_errors=True)

        # Init only what's correct for this branch
        git("-c", "protocol.file.allow=always",
            "submodule", "sync", "--recursive", cwd=super_repo, check=False)
        git("-c", "protocol.file.allow=always",
            "submodule", "update", "--init", "--recursive",
            cwd=super_repo, check=False)

        ok(f"Initialized submodules on branch: {branch}")
        log(f"[OK]   Initialized submodules on branch: {branch}")

    # ── Final pass ─────────────────────────────────────────────────────────
    # Branches are processed alphabetically so a later branch may delete
    # .git/modules/ dirs of submodules only on the original branch.
    # A clean re-init here ensures bundle.py starts from a valid state.
    checkout(super_repo, orig)
    git("submodule", "deinit", "-f", "--all", cwd=super_repo, check=False)
    git("-c", "protocol.file.allow=always",
        "submodule", "sync", "--recursive", cwd=super_repo, check=False)
    git("-c", "protocol.file.allow=always",
        "submodule", "update", "--init", "--recursive",
        cwd=super_repo, check=False)
    ok(f"Final re-init on 'main' — submodules ready for bundling")
    log(f"[OK]   Final re-init on 'main' — submodules ready for bundling")


# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main() -> None:
    from datetime import datetime
    import getpass as _getpass

    start      = datetime.now()
    script_dir = Path(__file__).parent.resolve()
    test_dir   = script_dir / "test_repos"

    # ── Log file setup (always written, even on error) ────────────────────────
    # Logs go to <project_root>/logs/ alongside bundle.py, export.py etc.
    root_dir = script_dir.parent
    log_path = root_dir / "logs" / f"{start.strftime('%Y%m%d_%H%M')}_create_test_repo.txt"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_fh   = open(log_path, "w", encoding="utf-8")

    def log(msg: str) -> None:
        log_fh.write(msg + "\n")
        log_fh.flush()

    try:
        _ran_by = _getpass.getuser()
    except Exception:
        _ran_by = "unknown"

    log("=================================================================")
    log("Create Test Repo Log")
    log("=================================================================")
    log(f"Generated      : {start.strftime('%Y-%m-%d %H:%M:%S')}")
    log(f"Ran by         : {_ran_by}")
    log(f"Test dir       : {test_dir}")
    log("=================================================================")
    log("")

    try:
        _main_body(test_dir, log)
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


def _main_body(test_dir: Path, log) -> None:
    """All the real work — separated so the log finally-block can always run."""

    if test_dir.exists():
        print_info(f"Removing existing test directory: {test_dir}")
        log(f"Removing existing test directory: {test_dir}")
        shutil.rmtree(test_dir, ignore_errors=True)
    test_dir.mkdir(parents=True)

    print()
    print("=" * 62)
    print(" Creating Test Fixture")
    print("=" * 62)
    print()
    print("Structure to be created:")
    print("  full-test-repo/")
    print("    main    → services/user-service, services/payment-service")
    print("    develop → services/user-service, services/notification-service")
    print("               (user-service/develop also has lib/feature-flags)")
    print()
    log("Structure:")
    log("  main    → services/user-service, services/payment-service")
    log("  develop → services/user-service, services/notification-service")
    log("            (user-service/develop also has lib/feature-flags)")
    log("")

    # ── Step 1: base repos ───────────────────────────────────────────────────
    print("─" * 62)
    print(" Step 1 of 4 : Creating base repositories")
    print("─" * 62)
    log("─" * 65)
    log("Step 1 of 4 : Creating base repositories")
    log("─" * 65)

    user         = create_user_service(test_dir)
    log("[OK]   user-service          : 4 branches (main, develop, feature/oauth, release/2.0)  3 tags")
    payment      = create_payment_service(test_dir)
    log("[OK]   payment-service       : 4 branches (main, develop, feature/stripe, hotfix/1.0.1)  3 tags")
    notification = create_notification_service(test_dir)
    log("[OK]   notification-service  : 3 branches (main, develop, feature/sms)  2 tags")
    database     = create_database_lib(test_dir)
    log("[OK]   database-lib          : 3 branches (main, develop, feature/pool)  2 tags")
    cache        = create_cache_lib(test_dir)
    log("[OK]   cache-lib             : 3 branches (main, develop, feature/redis)  2 tags")
    logger       = create_logger_lib(test_dir)
    log("[OK]   logger-lib            : 3 branches (main, develop, feature/json)  2 tags")
    feature_flags = create_feature_flags_lib(test_dir)
    log("[OK]   feature-flags-lib     : 2 branches (main, develop)  2 tags")
    log("")

    # ── Step 2: wire nesting ─────────────────────────────────────────────────
    print()
    print("─" * 62)
    print(" Step 2 of 4 : Wiring nested submodule structure")
    print("─" * 62)
    log("─" * 65)
    log("Step 2 of 4 : Wiring nested submodule structure")
    log("─" * 65)

    wire_logger_into_database(database, logger)
    log("[OK]   database-lib ← logger-lib wired on all branches")
    wire_database_into_user_service(user, database)
    log("[OK]   user-service ← database-lib wired on all branches")
    wire_feature_flags_into_user_service_develop(user, feature_flags)
    log("[OK]   user-service/develop ← feature-flags-lib (develop only)")
    wire_cache_into_payment_service(payment, cache)
    log("[OK]   payment-service ← cache-lib wired on all branches")
    log("")

    # ── Step 3: super repo ───────────────────────────────────────────────────
    print()
    print("─" * 62)
    print(" Step 3 of 4 : Creating super repository")
    print("─" * 62)
    log("─" * 65)
    log("Step 3 of 4 : Creating super repository")
    log("─" * 65)

    super_repo = create_super_repo(test_dir, user, payment, notification)
    log("[OK]   super repo created — 4 branches, 4 tags")
    log("")

    # ── Step 4: init submodules on all branches ──────────────────────────────
    print()
    print("─" * 62)
    print(" Step 4 of 4 : Initializing submodules on all branches")
    print("─" * 62)
    log("─" * 65)
    log("Step 4 of 4 : Initializing submodules on all branches")
    log("─" * 65)

    init_all_branches(super_repo, log)
    log("")

    # ── confirmation ─────────────────────────────────────────────────────────
    print()
    print("=" * 62)
    print(" Test Fixture Created Successfully")
    print("=" * 62)
    print()
    print(f"Super repo : {super_repo}")
    print()
    print("Submodule sets per branch (from git tree):")
    log("=================================================================")
    log("Test Fixture Created Successfully")
    log("=================================================================")
    log(f"Super repo : {super_repo}")
    log("")
    log("Submodule sets per branch (from git tree):")
    for branch in sorted(git("for-each-ref", "--format=%(refname:short)",
                             "refs/heads", cwd=super_repo).splitlines()):
        ls = git("ls-tree", "-r", "--full-name", branch,
                 cwd=super_repo, check=False)
        paths = [l.split(None, 3)[3] for l in ls.splitlines()
                 if len(l.split(None, 3)) == 4 and l.split()[0] == "160000"]
        line = f"  {branch:<28} → {', '.join(paths) or '(none)'}"
        print(line)
        log(line)

    print()
    print("Next steps:")
    print("  REPO_PATH in bundle.py already points here by default.")
    print("  You can run the full workflow straight away:")
    print()
    print("    python bundle.py")
    print("    python export.py")
    print("    python tests/verify_test.py")
    print()


if __name__ == "__main__":
    main()