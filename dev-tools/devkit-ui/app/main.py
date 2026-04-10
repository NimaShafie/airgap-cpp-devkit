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


def _detect_prefix() -> Path:
    if OS == "windows":
        local = os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))
        return Path(local) / "airgap-cpp-devkit"
    # Linux: prefer system-wide
    if Path("/opt/airgap-cpp-devkit").exists():
        return Path("/opt/airgap-cpp-devkit")
    return Path.home() / ".local" / "share" / "airgap-cpp-devkit"


INSTALL_PREFIX = _detect_prefix()

# ---------------------------------------------------------------------------
# Tool definitions
# ---------------------------------------------------------------------------
# uses_prebuilt: True  = installs from prebuilt-binaries submodule (fast path)
#                False = installs from vendored source/scripts only (no submodule needed)
TOOLS = [
    {
        "id": "toolchains/clang",
        "name": "clang-format + clang-tidy",
        "version": "22.1.2",
        "category": "Toolchains",
        "platform": "both",
        "description": "LLVM C++ formatter and static analyzer",
        "setup": "toolchains/clang/source-build/setup.sh",
        "receipt_name": "toolchains/clang",
        "estimate": "~2min",
        "uses_prebuilt": True,
    },
    {
        "id": "cmake",
        "name": "CMake",
        "version": "4.3.1",
        "category": "Build Tools",
        "platform": "both",
        "description": "Cross-platform build system generator",
        "setup": "build-tools/cmake/setup.sh",
        "receipt_name": "cmake",
        "estimate": "~30s",
        "uses_prebuilt": True,
    },
    {
        "id": "python",
        "name": "Python",
        "version": "3.14.4",
        "category": "Languages",
        "platform": "both",
        "description": "Portable Python interpreter + 20 vendored pip packages",
        "setup": "languages/python/setup.sh",
        "receipt_name": "python",
        "estimate": "~45s",
        "uses_prebuilt": True,
    },
    {
        "id": "lcov",
        "name": "lcov",
        "version": "2.4",
        "category": "Build Tools",
        "platform": "linux",
        "description": "Code coverage reporting tool",
        "setup": "build-tools/lcov/setup.sh",
        "receipt_name": "lcov",
        "estimate": "~10s",
        "uses_prebuilt": False,
    },
    {
        "id": "style-formatter",
        "name": "Style Formatter",
        "version": "22.1.2",
        "category": "Toolchains",
        "platform": "both",
        "description": "Pre-commit hook enforcing LLVM C++ style",
        "setup": "toolchains/clang/style-formatter/bootstrap.sh",
        "receipt_name": "style-formatter",
        "estimate": "~5s",
        "uses_prebuilt": False,
    },
    {
        "id": "conan",
        "name": "Conan",
        "version": "2.27.0",
        "category": "Developer Tools",
        "platform": "both",
        "description": "C/C++ package manager (self-contained, no Python required)",
        "setup": "dev-tools/conan/setup.sh",
        "receipt_name": "conan",
        "estimate": "~5s",
        "uses_prebuilt": True,
    },
    {
        "id": "sqlite",
        "name": "SQLite CLI",
        "version": "3.53.0",
        "category": "Developer Tools",
        "platform": "both",
        "description": "SQLite database inspection CLI",
        "setup": "dev-tools/sqlite/setup.sh",
        "receipt_name": "sqlite",
        "estimate": "~3s",
        "uses_prebuilt": True,
    },
    {
        "id": "7zip",
        "name": "7-Zip",
        "version": "26.00",
        "category": "Developer Tools",
        "platform": "both",
        "description": "Archive tool for Windows and Linux",
        "setup": "dev-tools/7zip/setup.sh",
        "receipt_name": "7zip",
        "estimate": "~2s",
        "uses_prebuilt": True,
    },
    {
        "id": "servy",
        "name": "Servy",
        "version": "7.8",
        "category": "Developer Tools",
        "platform": "windows",
        "description": "Windows service manager (portable)",
        "setup": "dev-tools/servy/setup.sh",
        "receipt_name": "servy",
        "estimate": "~3s",
        "uses_prebuilt": True,
    },
    {
        "id": "vscode-extensions",
        "name": "VS Code Extensions",
        "version": "Various",
        "category": "Developer Tools",
        "platform": "both",
        "description": "C/C++, TestMate, Python extensions for VS Code",
        "setup": "dev-tools/vscode-extensions/setup.sh",
        "receipt_name": "dev-tools/vscode-extensions",
        "estimate": "~30s",
        "uses_prebuilt": False,
    },
    {
        "id": "winlibs-gcc-ucrt",
        "name": "WinLibs GCC",
        "version": "15.2.0",
        "category": "Toolchains",
        "platform": "windows",
        "description": "GCC 15.2.0 + MinGW-w64 for Windows",
        "setup": "toolchains/gcc/windows/setup.sh",
        "receipt_name": "winlibs-gcc-ucrt",
        "estimate": "~8min",
        "uses_prebuilt": True,
    },
    {
        "id": "matlab",
        "name": "MATLAB Verification",
        "version": "-",
        "category": "Developer Tools",
        "platform": "both",
        "description": "Verifies MATLAB toolboxes (Database + Compiler)",
        "setup": "dev-tools/matlab/setup.sh",
        "receipt_name": "matlab",
        "estimate": "~2s",
        "uses_prebuilt": False,
    },
]

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
            "install_path": None, "user": None, "hostname": None, "log_file": None}
    if not path.exists():
        return data
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
    return INSTALL_PREFIX / clean / "INSTALL_RECEIPT.txt"


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
        "prefix": str(INSTALL_PREFIX),
        "hostname": platform.node(),
        "submodule": submodule,
    })


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
        cmd = ["bash", str(REPO_ROOT / "tests" / "run-tests.sh")]
        if verbose:
            cmd.append("--verbose")
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                cwd=str(REPO_ROOT),
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
        cmd = ["bash", str(setup_script)]
        if rebuild:
            cmd.append("--rebuild")
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                cwd=str(REPO_ROOT),
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
            cmd = ["bash", str(setup_script)]
            if rebuild:
                cmd.append("--rebuild")
            try:
                proc = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.STDOUT,
                    cwd=str(REPO_ROOT),
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


@app.get("/health")
async def health():
    return {"status": "ok", "os": OS, "prefix": str(INSTALL_PREFIX)}