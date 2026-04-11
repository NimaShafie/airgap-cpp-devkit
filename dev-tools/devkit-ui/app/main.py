"""
airgap-cpp-devkit — DevKit Manager
FastAPI + HTMX web UI for managing devkit tool installations.
"""
import asyncio
import json
import os
import platform
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, StreamingResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import jinja2
from fastapi.templating import Jinja2Templates

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
APP_DIR = Path(__file__).parent          # .../devkit-ui/app/
REPO_ROOT = APP_DIR.parent.parent.parent  # app/ -> devkit-ui/ -> dev-tools/ -> repo root
TEMPLATES_DIR = APP_DIR / "templates"
STATIC_DIR = APP_DIR / "static"


def _detect_os() -> str:
    s = platform.system().lower()
    if "windows" in s or os.environ.get("MSYSTEM"):
        return "windows"
    return "linux"


OS = _detect_os()


_PREFIX_OVERRIDE_FILE = REPO_ROOT / "dev-tools" / "devkit-ui" / ".devkit-prefix"


def _detect_prefix() -> Path:
    # 1. Persisted UI override
    if _PREFIX_OVERRIDE_FILE.exists():
        try:
            p = _PREFIX_OVERRIDE_FILE.read_text(encoding="utf-8").strip()
            if p:
                return Path(p)
        except Exception:
            pass
    # 2. Auto-detect
    if OS == "windows":
        local = os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))
        return Path(local) / "airgap-cpp-devkit"
    if Path("/opt/airgap-cpp-devkit").exists():
        return Path("/opt/airgap-cpp-devkit")
    return Path.home() / ".local" / "share" / "airgap-cpp-devkit"


INSTALL_PREFIX = _detect_prefix()


def _current_prefix() -> Path:
    """Return live prefix (re-reads override file each request)."""
    return _detect_prefix()


def _to_bash_path(p: Path) -> str:
    """Convert a path to forward slashes so Git Bash on Windows won't mangle \\n, \\t, \\a, etc."""
    if OS == "windows":
        return str(p).replace("\\", "/")
    return str(p)


def _detect_privilege() -> str:
    """Return 'admin' if the process has elevated/root privileges, else 'user'."""
    try:
        if OS == "windows":
            import ctypes
            return "admin" if ctypes.windll.shell32.IsUserAnAdmin() else "user"
        else:
            return "admin" if os.getuid() == 0 else "user"
    except Exception:
        return "user"


def _get_system_info() -> dict:
    import shutil as _shutil
    prefix = _current_prefix()
    disk_free = disk_total = None
    try:
        check = prefix if prefix.exists() else (prefix.parent if prefix.parent.exists() else Path("/"))
        stat = _shutil.disk_usage(str(check))
        disk_free = f"{stat.free / (1024**3):.1f} GB"
        disk_total = f"{stat.total / (1024**3):.1f} GB"
    except Exception:
        pass
    privilege = _detect_privilege()
    if privilege == "admin":
        admin_prefix_str = (
            r"C:\Program Files\airgap-cpp-devkit" if OS == "windows"
            else "/opt/airgap-cpp-devkit"
        )
    else:
        admin_prefix_str = None
    return {
        "python_version": f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
        "privilege": privilege,
        "disk_free": disk_free,
        "disk_total": disk_total,
        "admin_prefix": admin_prefix_str,
    }

# ---------------------------------------------------------------------------
# Tool discovery — scans for devkit.json manifests in tool directories.
#
# To add a new tool, create a devkit.json in its directory (see packages/
# for an example). No Python edits required.
#
# Search order (first match by id wins):
#   dev-tools/*/          dev-tools/*/*/
#   build-tools/*/
#   languages/*/
#   toolchains/*/         toolchains/*/*/     toolchains/*/*/*/
#   frameworks/*/
#   packages/*/           ← user-contributed or custom tools
# ---------------------------------------------------------------------------
_TOOL_SCAN_PATTERNS = [
    "dev-tools/*/devkit.json",
    "dev-tools/*/*/devkit.json",
    "build-tools/*/devkit.json",
    "languages/*/devkit.json",
    "toolchains/*/devkit.json",
    "toolchains/*/*/devkit.json",
    "toolchains/*/*/*/devkit.json",
    "frameworks/*/devkit.json",
    "packages/*/devkit.json",
]


def _load_tools() -> list:
    import glob as _glob
    tools: list = []
    seen_ids: set = set()
    for pattern in _TOOL_SCAN_PATTERNS:
        for manifest_path in sorted(_glob.glob(str(REPO_ROOT / pattern))):
            try:
                data = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
            except Exception as exc:
                print(f"[devkit] Warning: cannot load {manifest_path}: {exc}", file=sys.stderr)
                continue
            tool_id = data.get("id", "").strip()
            if not tool_id or tool_id in seen_ids:
                continue
            seen_ids.add(tool_id)
            # Apply defaults so templates never see missing keys
            data.setdefault("platform", "both")
            data.setdefault("category", "Developer Tools")
            data.setdefault("estimate", "~1min")
            data.setdefault("uses_prebuilt", False)
            data.setdefault("setup_args", [])
            data.setdefault("version", "")
            data.setdefault("version_label", None)
            tools.append(data)
    tools.sort(key=lambda t: (t.get("sort_order", 99), t.get("category", ""), t.get("name", "")))
    return tools


TOOLS = _load_tools()

PROFILES = {
    "cpp-dev": {
        "name": "C++ Developer",
        "description": "Core C++ development tools",
        "tools": ["toolchains/clang", "cmake", "python", "conan", "vscode-extensions", "sqlite", "7zip"],
        "color": "blue",
    },
    "devops": {
        "name": "DevOps",
        "description": "Infrastructure and automation tools",
        "tools": ["cmake", "python", "conan", "sqlite", "7zip"],
        "color": "green",
    },
    "minimal": {
        "name": "Minimal",
        "description": "Required tools only",
        "tools": ["toolchains/clang", "cmake", "python", "style-formatter"],
        "color": "gray",
    },
    "full": {
        "name": "Full Install",
        "description": "All available tools",
        "tools": [t["id"] for t in TOOLS],
        "color": "purple",
    },
}

# ---------------------------------------------------------------------------
# Prebuilt-binaries submodule detection
# ---------------------------------------------------------------------------
def get_submodule_status() -> dict:
    """Check whether the prebuilt-binaries submodule is initialised and up to date."""
    submodule_dir = REPO_ROOT / "prebuilt-binaries"
    result = {
        "initialized": False,
        "stale": False,       # True if submodule pointer is ahead/behind
        "commit": None,
        "path": str(submodule_dir),
        "prebuilt_tool_count": sum(1 for t in TOOLS if t.get("uses_prebuilt")),
    }

    if not submodule_dir.exists():
        return result

    # Non-empty directory means the submodule has been checked out
    try:
        contents = list(submodule_dir.iterdir())
    except PermissionError:
        contents = []
    result["initialized"] = len(contents) > 0

    if not result["initialized"]:
        return result

    # Ask git for the submodule status line
    try:
        proc = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "submodule", "status", "prebuilt-binaries"],
            capture_output=True, text=True, timeout=5,
        )
        line = proc.stdout.strip()
        if line:
            # Leading char: ' ' = OK, '+' = stale (commit differs), '-' = not init
            result["stale"] = line[0] == "+"
            result["commit"] = line.lstrip(" +-").split()[0][:10]
    except Exception:
        pass

    return result


# ---------------------------------------------------------------------------
# Receipt reader
# ---------------------------------------------------------------------------
def _parse_receipt(path: Path) -> dict:
    data = {"status": "not_installed", "version": None, "date": None,
            "install_path": None, "user": None, "hostname": None, "log_file": None,
            "receipt_exists": False}
    if not path.exists():
        return data
    data["receipt_exists"] = True
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
        for line in content.splitlines():
            line = line.strip()
            if line.startswith("Version"):
                data["version"] = line.split(":", 1)[-1].strip()
            elif line.startswith("Status"):
                data["status"] = line.split(":", 1)[-1].strip()
            elif line.startswith("Date"):
                data["date"] = line.split(":", 1)[-1].strip()
            elif line.startswith("Install path"):
                data["install_path"] = line.split(":", 1)[-1].strip()
            elif line.startswith("User"):
                data["user"] = line.split(":", 1)[-1].strip()
            elif line.startswith("Hostname"):
                data["hostname"] = line.split(":", 1)[-1].strip()
            elif line.startswith("Log file"):
                data["log_file"] = line.split(":", 1)[-1].strip()
    except Exception:
        pass
    return data


def _get_receipt_path(receipt_name: str) -> Path:
    # Handle nested names like "toolchains/clang"
    clean = receipt_name.replace("/", os.sep)
    return _current_prefix() / clean / "INSTALL_RECEIPT.txt"


def get_tool_status(tool: dict) -> dict:
    receipt_path = _get_receipt_path(tool["receipt_name"])
    receipt = _parse_receipt(receipt_path)
    installed = receipt["status"] == "success"
    # Platform check
    available = tool["platform"] == "both" or tool["platform"] == OS
    return {
        **tool,
        "installed": installed,
        "available": available,
        "receipt": receipt,
        "receipt_path": str(receipt_path),
    }


def get_all_tools_status() -> list:
    return [get_tool_status(t) for t in TOOLS]


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="DevKit Manager", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
_jinja_env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(str(TEMPLATES_DIR)),
    autoescape=jinja2.select_autoescape(["html"]),
)

def render(name: str, ctx: dict) -> HTMLResponse:
    t = _jinja_env.get_template(name)
    return HTMLResponse(t.render(**ctx))


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    tools = get_all_tools_status()
    installed_count = sum(1 for t in tools if t["installed"])
    available_count = sum(1 for t in tools if t["available"])
    categories = {}
    for t in tools:
        cat = t["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(t)
    submodule = get_submodule_status()
    return render("dashboard.html", {
        "request": request,
        "tools": tools,
        "categories": categories,
        "profiles": PROFILES,
        "installed_count": installed_count,
        "available_count": available_count,
        "total_count": len(tools),
        "os": OS,
        "prefix": str(_current_prefix()),
        "hostname": platform.node(),
        "submodule": submodule,
        "system_info": _get_system_info(),
    })


@app.get("/api/prefix", response_class=JSONResponse)
async def api_get_prefix():
    return {
        "prefix": str(_current_prefix()),
        "is_override": _PREFIX_OVERRIDE_FILE.exists(),
        "default": str(_detect_prefix() if not _PREFIX_OVERRIDE_FILE.exists() else None),
    }


@app.post("/api/prefix")
async def api_set_prefix(request: Request):
    body = await request.json()
    new_prefix = body.get("prefix", "").strip()
    if not new_prefix:
        return JSONResponse({"error": "prefix cannot be empty"}, status_code=400)
    try:
        _PREFIX_OVERRIDE_FILE.write_text(new_prefix, encoding="utf-8")
        return {"prefix": new_prefix, "ok": True}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


@app.delete("/api/prefix")
async def api_reset_prefix():
    """Remove override, revert to auto-detected prefix."""
    if _PREFIX_OVERRIDE_FILE.exists():
        _PREFIX_OVERRIDE_FILE.unlink()
    return {"prefix": str(_detect_prefix()), "ok": True}


@app.get("/api/submodule", response_class=JSONResponse)
async def api_submodule():
    return get_submodule_status()


@app.post("/init-submodule")
async def init_submodule():
    """Stream output of git submodule update --init --recursive prebuilt-binaries."""
    async def stream():
        yield "data: Initialising prebuilt-binaries submodule...\n\n"
        cmd = [
            "git", "-C", str(REPO_ROOT),
            "submodule", "update", "--init", "--recursive", "prebuilt-binaries",
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
            async for line in proc.stdout:
                text = line.decode("utf-8", errors="replace").rstrip()
                if text:
                    yield f"data: {text}\n\n"
            await proc.wait()
            if proc.returncode == 0:
                yield "data: ✓ prebuilt-binaries initialised successfully\n\n"
                yield "data: DONE:success\n\n"
            else:
                yield f"data: ✗ git exited with code {proc.returncode}\n\n"
                yield "data: DONE:failed\n\n"
        except Exception as e:
            yield f"data: ERROR: {e}\n\n"
            yield "data: DONE:failed\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/run-tests")
async def run_tests(verbose: bool = False):
    """Stream output of tests/run-tests.sh."""
    async def stream():
        yield "data: Running smoke tests...\n\n"
        cmd = ["bash", "tests/run-tests.sh", "--os", OS, "--prefix", _to_bash_path(_current_prefix())]
        if verbose:
            cmd.append("--verbose")
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                cwd=_to_bash_path(REPO_ROOT),
            )
            async for line in proc.stdout:
                text = line.decode("utf-8", errors="replace").rstrip()
                if text:
                    yield f"data: {text}\n\n"
            await proc.wait()
            if proc.returncode == 0:
                yield "data: DONE:success\n\n"
            else:
                yield "data: DONE:failed\n\n"
        except Exception as e:
            yield f"data: ERROR: {e}\n\n"
            yield "data: DONE:failed\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/api/tools", response_class=JSONResponse)
async def api_tools():
    return get_all_tools_status()


@app.get("/api/tool/{tool_id:path}", response_class=JSONResponse)
async def api_tool(tool_id: str):
    tool = next((t for t in TOOLS if t["id"] == tool_id), None)
    if not tool:
        return JSONResponse({"error": "Tool not found"}, status_code=404)
    return get_tool_status(tool)


@app.post("/install/{tool_id:path}")
async def install_tool(tool_id: str, rebuild: bool = False):
    tool = next((t for t in TOOLS if t["id"] == tool_id), None)
    if not tool:
        return JSONResponse({"error": "Tool not found"}, status_code=404)

    setup_script = REPO_ROOT / tool["setup"]

    async def stream():
        yield f"data: Installing {tool['name']} {tool['version']}...\n\n"
        cmd = ["bash", _to_bash_path(setup_script)] + tool.get("setup_args", [])
        if rebuild:
            cmd.append("--rebuild")
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                cwd=_to_bash_path(REPO_ROOT),
            )
            async for line in proc.stdout:
                text = line.decode("utf-8", errors="replace").rstrip()
                if text:
                    yield f"data: {text}\n\n"
            await proc.wait()
            if proc.returncode == 0:
                yield "data: ✓ Installation complete\n\n"
                yield "data: DONE:success\n\n"
            else:
                yield f"data: ✗ Installation failed (exit {proc.returncode})\n\n"
                yield "data: DONE:failed\n\n"
        except Exception as e:
            yield f"data: ERROR: {e}\n\n"
            yield "data: DONE:failed\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.post("/install-profile/{profile_id}")
async def install_profile(profile_id: str, rebuild: bool = False):
    profile = PROFILES.get(profile_id)
    if not profile:
        return JSONResponse({"error": "Profile not found"}, status_code=404)

    tool_ids = profile["tools"]
    # Filter for platform-available tools
    tools_to_install = [
        t for t in TOOLS
        if t["id"] in tool_ids and (t["platform"] == "both" or t["platform"] == OS)
    ]

    async def stream():
        yield f"data: Installing profile: {profile['name']} ({len(tools_to_install)} tools)\n\n"
        for tool in tools_to_install:
            yield f"data: \n\n"
            yield f"data: ── {tool['name']} {tool['version']}\n\n"
            setup_script = REPO_ROOT / tool["setup"]
            cmd = ["bash", _to_bash_path(setup_script)] + tool.get("setup_args", [])
            if rebuild:
                cmd.append("--rebuild")
            try:
                proc = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                    cwd=_to_bash_path(REPO_ROOT),
                )
                async for line in proc.stdout:
                    text = line.decode("utf-8", errors="replace").rstrip()
                    if text:
                        yield f"data: {text}\n\n"
                await proc.wait()
                status = "✓" if proc.returncode == 0 else "✗"
                yield f"data: {status} {tool['name']} done\n\n"
            except Exception as e:
                yield f"data: ERROR: {e}\n\n"
        yield "data: \n\n"
        yield "data: ✓ Profile installation complete\n\n"
        yield "data: DONE:success\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/logs", response_class=HTMLResponse)
async def logs_page(request: Request):
    log_dirs = []
    if OS == "windows":
        import tempfile
        log_base = Path(tempfile.gettempdir()) / "airgap-cpp-devkit" / "logs"
    else:
        log_base = Path("/var/log/airgap-cpp-devkit")
        if not log_base.exists():
            log_base = Path.home() / "airgap-cpp-devkit-logs"

    logs = []
    if log_base.exists():
        for f in sorted(log_base.rglob("*.log"), key=lambda x: x.stat().st_mtime, reverse=True)[:50]:
            logs.append({
                "name": f.name,
                "path": str(f),
                "size": f.stat().st_size,
                "modified": datetime.fromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d %H:%M"),
                "tool": f.parent.name,
            })

    return render("logs.html", {
        "request": request,
        "logs": logs,
        "log_base": str(log_base),
        "os": OS,
    })


@app.get("/api/log")
async def get_log(path: str):
    try:
        content = Path(path).read_text(encoding="utf-8", errors="replace")
        return JSONResponse({"content": content})
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=404)


@app.delete("/uninstall/{tool_id:path}")
async def uninstall_tool(tool_id: str):
    """Remove a tool's install directory from the prefix."""
    tool = next((t for t in TOOLS if t["id"] == tool_id), None)
    if not tool:
        return JSONResponse({"error": "Tool not found"}, status_code=404)

    receipt_path = _get_receipt_path(tool["receipt_name"])
    install_dir = receipt_path.parent  # <prefix>/<tool>/

    async def stream():
        yield f"data: Uninstalling {tool['name']}...\n\n"
        if not install_dir.exists():
            yield "data: Nothing to remove — directory does not exist.\n\n"
            yield "data: DONE:success\n\n"
            return
        try:
            import shutil
            shutil.rmtree(str(install_dir))
            yield f"data: ✓ Removed {install_dir}\n\n"
            yield "data: DONE:success\n\n"
        except Exception as e:
            yield f"data: ✗ ERROR: {e}\n\n"
            yield "data: DONE:failed\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/health")
async def health():
    return {"status": "ok", "os": OS, "prefix": str(_current_prefix())}