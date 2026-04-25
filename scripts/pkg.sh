#!/usr/bin/env bash
# scripts/pkg.sh — Package management helper for airgap-devkit forks
#
# Use this script when customising a fork: add, remove, or re-version tools
# without having to hunt down every config file manually.
#
# Commands:
#   list                         List all bundled tools and their versions
#   remove <id>                  Remove a tool from the kit
#   set-version <id> <version>   Change a tool's pinned version
#   add <id>                     Scaffold a new tool directory
#   check                        Audit configuration consistency
#
# Examples:
#   bash scripts/pkg.sh list
#   bash scripts/pkg.sh remove matlab
#   bash scripts/pkg.sh set-version cmake 3.31.0
#   bash scripts/pkg.sh add my-tool
#   bash scripts/pkg.sh check

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info() { echo -e "${CYAN}[pkg]${RESET} $*"; }
ok()   { echo -e "${GREEN}[ok]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[!!]${RESET}  $*"; }
err()  { echo -e "${RED}[ERR]${RESET} $*" >&2; exit 1; }
step() { echo -e "  ${BOLD}→${RESET} $*"; }

# ── python3 check ───────────────────────────────────────────────────────────
need_python() {
    command -v python3 &>/dev/null && return 0
    err "python3 is required. Install it first, or run: bash tools/languages/python/setup.sh"
}

# ── discover all tools ───────────────────────────────────────────────────────
# Outputs one line per tool: id|name|version|category|platform|prebuilt|reldir
discover_tools() {
    need_python
    python3 - "$REPO_ROOT" <<'PYEOF'
import sys, glob, json, os

repo = sys.argv[1]
patterns = [
    "tools/*/*/devkit.json",
    "tools/*/*/*/devkit.json",
    "packages/*/devkit.json",
]
seen = {}
for pat in patterns:
    for path in sorted(glob.glob(os.path.join(repo, pat))):
        try:
            with open(path) as f:
                d = json.load(f)
        except Exception:
            continue
        tid = d.get("id")
        if not tid or tid in seen:
            continue
        seen[tid] = {
            "id":      tid,
            "name":    d.get("name", tid),
            "version": d.get("version", "?"),
            "cat":     d.get("category", "?"),
            "plat":    d.get("platform", "both"),
            "pre":     "yes" if d.get("uses_prebuilt") else "no",
            "dir":     os.path.relpath(os.path.dirname(path), repo).replace("\\", "/"),
        }

for t in sorted(seen.values(), key=lambda x: (x["cat"], x["name"])):
    print("{id}|{name}|{version}|{cat}|{plat}|{pre}|{dir}".format(**t))
PYEOF
}

# ── find the devkit.json path for a given tool ID ───────────────────────────
# Prints the absolute path on success; exits 1 if not found.
find_tool() {
    local id="$1"
    need_python
    python3 - "$REPO_ROOT" "$id" <<'PYEOF'
import sys, glob, json, os

repo, tid = sys.argv[1], sys.argv[2]
patterns = [
    "tools/*/*/devkit.json",
    "tools/*/*/*/devkit.json",
    "packages/*/devkit.json",
]
for pat in patterns:
    for path in sorted(glob.glob(os.path.join(repo, pat))):
        try:
            with open(path) as f:
                d = json.load(f)
            if d.get("id") == tid:
                print(os.path.abspath(path))
                sys.exit(0)
        except Exception:
            pass
sys.exit(1)
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════
# list
# ═══════════════════════════════════════════════════════════════════════════
cmd_list() {
    info "Scanning ${REPO_ROOT}..."
    echo ""
    printf "${BOLD}%-28s %-12s %-18s %-10s %-8s %s${RESET}\n" \
        "ID" "VERSION" "CATEGORY" "PLATFORM" "PREBUILT" "LOCATION"
    printf '%0.s─' {1..100}; echo
    while IFS='|' read -r id _name ver cat plat pre dir; do
        printf "%-28s %-12s %-18s %-10s %-8s %s\n" "$id" "$ver" "$cat" "$plat" "$pre" "$dir"
    done < <(discover_tools)
}

# ═══════════════════════════════════════════════════════════════════════════
# remove <id>
# ═══════════════════════════════════════════════════════════════════════════
cmd_remove() {
    local id="${1:-}"
    [[ -z "$id" ]] && err "Usage: pkg.sh remove <tool-id>"

    local djson
    djson=$(find_tool "$id") \
        || err "Tool '${id}' not found. Run 'bash scripts/pkg.sh list' to see IDs."
    local tool_dir
    tool_dir="$(dirname "$djson")"

    echo ""
    info "Removing: ${id}"
    echo ""
    echo -e "${BOLD}Automatic changes:${RESET}"
    step "Remove '${id}' from layout.json"
    step "Remove '${id}' from .ci/config.json profiles"
    echo ""
    echo -e "${BOLD}Manual steps shown after confirmation:${RESET}"
    step "install-cli.sh — profile variable lines to remove"
    step "server/internal/api/handlers.go — ToolIDs lines to review"
    step "README.md / TOOLS.md — remove documentation row"
    step "run: bash scripts/generate-sbom.sh"
    echo ""

    printf "Proceed? [y/N]: "
    read -r reply
    [[ "${reply^^}" != "Y" ]] && { info "Aborted."; exit 0; }
    echo ""

    # --- layout.json ---
    python3 - "$REPO_ROOT" "$id" <<'PYEOF'
import sys, json, os

repo, tid = sys.argv[1], sys.argv[2]
path = os.path.join(repo, "layout.json")
with open(path) as f:
    layout = json.load(f)

changed = False
for cat, ids in layout.get("tool_order", {}).items():
    if tid in ids:
        ids.remove(tid)
        changed = True
        print(f"  layout.json: removed '{tid}' from '{cat}'")

if changed:
    with open(path, "w") as f:
        json.dump(layout, f, indent=2)
        f.write("\n")
else:
    print(f"  layout.json: '{tid}' was not listed (already clean)")
PYEOF

    # --- .ci/config.json ---
    python3 - "$REPO_ROOT" "$id" <<'PYEOF'
import sys, json, os

repo, tid = sys.argv[1], sys.argv[2]
path = os.path.join(repo, ".ci", "config.json")
if not os.path.exists(path):
    print("  .ci/config.json: not found, skipping")
    sys.exit(0)

with open(path) as f:
    ci = json.load(f)

changed = False
for pname, ids in ci.get("profiles", {}).items():
    if isinstance(ids, list) and tid in ids:
        ids.remove(tid)
        changed = True
        print(f"  .ci/config.json: removed '{tid}' from profile '{pname}'")

if changed:
    with open(path, "w") as f:
        json.dump(ci, f, indent=2)
        f.write("\n")
else:
    print(f"  .ci/config.json: '{tid}' not in any profile")
PYEOF

    ok "JSON configs updated."
    echo ""

    # --- install-cli.sh — show lines to remove manually ---
    local cli_grep
    # Match the id itself AND the UPPER_SNAKE_CASE variable form (e.g. 7zip → 7ZIP, vscode-extensions → VSCODE_EXTENSIONS)
    local id_upper
    id_upper="$(echo "${id}" | tr '[:lower:]-' '[:upper:]_')"
    cli_grep=$(grep -n "${id}\|INSTALL_${id_upper}" "${REPO_ROOT}/install-cli.sh" 2>/dev/null || true)
    if [[ -n "$cli_grep" ]]; then
        warn "install-cli.sh — manually remove/adjust these lines:"
        echo "$cli_grep" | sed 's/^/    /'
    else
        ok "install-cli.sh: no references to '${id}'"
    fi
    echo ""

    # --- handlers.go — show lines to review ---
    local go_grep
    go_grep=$(grep -n "\"${id}\"" "${REPO_ROOT}/server/internal/api/handlers.go" 2>/dev/null || true)
    if [[ -n "$go_grep" ]]; then
        warn "server/internal/api/handlers.go — review these ToolIDs entries:"
        echo "$go_grep" | sed 's/^/    /'
    else
        ok "handlers.go: no references to '${id}'"
    fi
    echo ""

    # --- optional: delete the tool directory ---
    printf "Delete tool directory '%s'? [y/N]: " "${tool_dir#${REPO_ROOT}/}"
    read -r del_reply
    if [[ "${del_reply^^}" == "Y" ]]; then
        rm -rf "$tool_dir"
        ok "Deleted: ${tool_dir#${REPO_ROOT}/}"
        warn "Prebuilt archives in prebuilt/ must be removed separately (it's a submodule)."
    else
        info "Directory kept. You can delete it manually: rm -rf ${tool_dir#${REPO_ROOT}/}"
    fi

    echo ""
    ok "Done. Run 'bash scripts/pkg.sh check' to verify, then update README.md and TOOLS.md."
}

# ═══════════════════════════════════════════════════════════════════════════
# set-version <id> <new-version>
# ═══════════════════════════════════════════════════════════════════════════
cmd_set_version() {
    local id="${1:-}" new_ver="${2:-}"
    [[ -z "$id" || -z "$new_ver" ]] && err "Usage: pkg.sh set-version <tool-id> <new-version>"

    local djson
    djson=$(find_tool "$id") \
        || err "Tool '${id}' not found."

    local old_ver uses_prebuilt
    old_ver=$(python3 -c "import sys,json; d=json.load(open(sys.argv[1])); print(d.get('version','?'))" "$djson")
    uses_prebuilt=$(python3 -c "import sys,json; d=json.load(open(sys.argv[1])); print('yes' if d.get('uses_prebuilt') else 'no')" "$djson")

    if [[ "$old_ver" == "$new_ver" ]]; then
        info "Version is already ${new_ver} — nothing to do."
        exit 0
    fi

    info "Updating ${id}: ${old_ver} → ${new_ver}"

    python3 - "$djson" "$new_ver" <<'PYEOF'
import sys, json

path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = json.load(f)
d["version"] = ver
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
print(f"  Updated: {path}")
PYEOF

    ok "devkit.json updated."
    echo ""

    if [[ "$uses_prebuilt" == "yes" ]]; then
        # Infer prebuilt manifest path from the tool's relative directory
        local rel_dir
        rel_dir=$(python3 -c "import sys,os; print(os.path.relpath(os.path.dirname(sys.argv[1]),sys.argv[2]).replace('\\\\','/'))" \
            "$djson" "$REPO_ROOT")
        # Strip leading "tools/" if present to get the prebuilt sub-path
        local sub="${rel_dir#tools/}"
        warn "This tool uses prebuilt binaries. You must also:"
        step "Create:  prebuilt/${sub}/${new_ver}/manifest.json"
        step "  (copy from prebuilt/${sub}/${old_ver}/manifest.json and update version + SHA256)"
        step "Add new archive files to prebuilt/${sub}/${new_ver}/"
        step "Update setup.sh if it hardcodes the version string"
    fi

    echo ""
    warn "Remaining manual steps:"
    step "Update version references in README.md and TOOLS.md"
    step "Run: bash scripts/generate-sbom.sh"
    step "Run: bash tests/validate-manifests.sh"
}

# ═══════════════════════════════════════════════════════════════════════════
# add <id>
# ═══════════════════════════════════════════════════════════════════════════
cmd_add() {
    local id="${1:-}"
    [[ -z "$id" ]] && err "Usage: pkg.sh add <tool-id>"

    if find_tool "$id" &>/dev/null 2>&1; then
        err "Tool '${id}' already exists. Use 'set-version' to change its version."
    fi

    echo ""
    echo -e "${BOLD}Scaffolding new tool: ${id}${RESET}"
    echo ""

    printf "Display name [%s]: " "$id"
    read -r name; name="${name:-$id}"

    printf "Version [1.0.0]: "
    read -r version; version="${version:-1.0.0}"

    echo "Categories: Build Tools | Developer Tools | Frameworks | Languages | Toolchains"
    printf "Category [Developer Tools]: "
    read -r category; category="${category:-Developer Tools}"

    printf "Platform (both/windows/linux) [both]: "
    read -r platform; platform="${platform:-both}"

    printf "One-line description: "
    read -r description; description="${description:-TODO: add description}"

    printf "Uses prebuilt binaries from prebuilt/ submodule? [y/N]: "
    read -r pre_ans
    local uses_prebuilt="false"
    [[ "${pre_ans^^}" == "Y" ]] && uses_prebuilt="true"

    # Map category to directory
    local cat_dir
    case "${category,,}" in
        "build tools")           cat_dir="tools/build-tools" ;;
        "languages")             cat_dir="tools/languages" ;;
        "toolchains")            cat_dir="tools/toolchains" ;;
        "frameworks")            cat_dir="tools/frameworks" ;;
        "bundles"|"packages")    cat_dir="packages" ;;
        *)                       cat_dir="tools/dev-tools" ;;
    esac

    local tool_dir="${REPO_ROOT}/${cat_dir}/${id}"
    echo ""
    info "Directory: ${cat_dir}/${id}/"

    if [[ -d "$tool_dir" ]]; then
        warn "Directory already exists."
        printf "Use it anyway? [y/N]: "
        read -r use_existing
        [[ "${use_existing^^}" != "Y" ]] && exit 1
    fi

    mkdir -p "$tool_dir"

    # Write devkit.json
    python3 - "$tool_dir" "$id" "$name" "$version" "$category" "$platform" "$description" "$uses_prebuilt" <<'PYEOF'
import sys, json, os

tool_dir, tid, name, ver, cat, plat, desc, prebuilt_str = sys.argv[1:]
d = {
    "id":           tid,
    "name":         name,
    "version":      ver,
    "category":     cat,
    "platform":     plat,
    "description":  desc,
    "setup":        "setup.sh",
    "receipt_name": tid,
    "estimate":     "~30s",
}
if prebuilt_str == "true":
    d["uses_prebuilt"] = True

with open(os.path.join(tool_dir, "devkit.json"), "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
print(f"  Created: devkit.json")
PYEOF

    # Write setup.sh template
    # Use printf so we can embed the variables cleanly
    printf '#!/usr/bin/env bash\n' > "${tool_dir}/setup.sh"
    printf '# setup.sh — installer for %s\n' "$name" >> "${tool_dir}/setup.sh"
    printf 'set -euo pipefail\n\n' >> "${tool_dir}/setup.sh"
    printf 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n' >> "${tool_dir}/setup.sh"
    printf 'REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"\n\n' >> "${tool_dir}/setup.sh"
    printf 'source "${REPO_ROOT}/tools/lib/devkit-install.sh"\n\n' >> "${tool_dir}/setup.sh"
    printf 'VERSION="%s"\n' "$version" >> "${tool_dir}/setup.sh"
    printf 'PREFIX="${INSTALL_PREFIX:-$(devkit_default_prefix %s)}"\n\n' "$id" >> "${tool_dir}/setup.sh"
    printf 'devkit_parse_args "$@"\n\n' >> "${tool_dir}/setup.sh"
    if [[ "$uses_prebuilt" == "true" ]]; then
        local sub="${cat_dir#tools/}"
        printf '# Locate the prebuilt archive\n' >> "${tool_dir}/setup.sh"
        printf 'PREBUILT_DIR="${PREBUILT_DIR:-${REPO_ROOT}/prebuilt}"\n' >> "${tool_dir}/setup.sh"
        printf 'PARTS_DIR="${PREBUILT_DIR}/%s/%s/${VERSION}"\n' "$sub/$id" >> "${tool_dir}/setup.sh"
        printf 'ARCHIVE="$(devkit_find_file "${PARTS_DIR}")"\n\n' >> "${tool_dir}/setup.sh"
        printf '# TODO: choose the right install method:\n' >> "${tool_dir}/setup.sh"
        printf '#   devkit_extract        "${ARCHIVE}" "${PREFIX}"   # tar/zip archive\n' >> "${tool_dir}/setup.sh"
        printf '#   devkit_install_exe    "${ARCHIVE}" "${PREFIX}"   # NSIS installer\n' >> "${tool_dir}/setup.sh"
        printf '#   devkit_install_nsis_s "${ARCHIVE}" "${PREFIX}"   # silent NSIS (/S)\n' >> "${tool_dir}/setup.sh"
        printf '#   devkit_install_msi    "${ARCHIVE}" "${PREFIX}"   # MSI package\n\n' >> "${tool_dir}/setup.sh"
    else
        printf '# TODO: add installation logic here.\n' >> "${tool_dir}/setup.sh"
        printf '# Source files live alongside this script in: %s/%s/\n\n' "$cat_dir" "$id" >> "${tool_dir}/setup.sh"
    fi
    printf 'mkdir -p "${PREFIX}"\n' >> "${tool_dir}/setup.sh"
    printf 'devkit_write_receipt "%s" "${VERSION}" "$(uname -s | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"')" "${PREFIX}"\n' "$id" >> "${tool_dir}/setup.sh"
    chmod +x "${tool_dir}/setup.sh"
    ok "  Created: setup.sh"

    # Add to layout.json
    python3 - "$REPO_ROOT" "$id" "$category" <<'PYEOF'
import sys, json, os

repo, tid, cat = sys.argv[1], sys.argv[2], sys.argv[3]
path = os.path.join(repo, "layout.json")
with open(path) as f:
    layout = json.load(f)

tool_order = layout.setdefault("tool_order", {})
cat_list   = tool_order.setdefault(cat, [])
if tid not in cat_list:
    cat_list.append(tid)
    with open(path, "w") as f:
        json.dump(layout, f, indent=2)
        f.write("\n")
    print(f"  Updated: layout.json (added '{tid}' to '{cat}')")
else:
    print(f"  layout.json: '{tid}' already present")
PYEOF

    echo ""
    ok "Scaffold complete: ${cat_dir}/${id}/"
    echo ""
    warn "Next steps:"
    step "Complete the installation logic in ${cat_dir}/${id}/setup.sh"
    if [[ "$uses_prebuilt" == "true" ]]; then
        local sub="${cat_dir#tools/}"
        step "Create prebuilt/${sub}/${id}/${version}/manifest.json with SHA256 checksums"
        step "Place binary archives in prebuilt/${sub}/${id}/${version}/"
    fi
    step "Add a row to README.md and TOOLS.md"
    step "Add a test case to tests/run-tests.sh"
    step "Run: bash scripts/generate-sbom.sh"
    step "Syntax-check: bash -n ${cat_dir}/${id}/setup.sh && echo OK"
}

# ═══════════════════════════════════════════════════════════════════════════
# check — audit consistency across all config files
# ═══════════════════════════════════════════════════════════════════════════
cmd_check() {
    info "Auditing configuration consistency..."
    local issues=0

    # Collect tool IDs into an array
    local all_ids=()
    while IFS='|' read -r id _rest; do
        all_ids+=("$id")
    done < <(discover_tools)

    echo ""
    echo -e "${BOLD}Tools discovered (${#all_ids[@]})${RESET}"
    printf "  %s\n" "${all_ids[@]}"

    # ── layout.json ──────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}Checking layout.json...${RESET}"
    if python3 - "$REPO_ROOT" "${all_ids[@]}" <<'PYEOF'
import sys, json, os

repo = sys.argv[1]; tool_ids = set(sys.argv[2:])
path = os.path.join(repo, "layout.json")
with open(path) as f:
    layout = json.load(f)

layout_ids = {tid for ids in layout.get("tool_order", {}).values() for tid in ids}
missing  = tool_ids - layout_ids
orphaned = layout_ids - tool_ids

for tid in sorted(missing):
    print(f"  WARN: '{tid}' has devkit.json but is absent from layout.json")
for tid in sorted(orphaned):
    print(f"  WARN: '{tid}' is in layout.json but has no devkit.json")
if not missing and not orphaned:
    print("  OK: layout.json is in sync")
sys.exit(0 if not (missing or orphaned) else 1)
PYEOF
    then : ; else issues=$(( issues + 1 )); fi

    # ── .ci/config.json ──────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}Checking .ci/config.json profiles...${RESET}"
    if python3 - "$REPO_ROOT" "${all_ids[@]}" <<'PYEOF'
import sys, json, os

repo = sys.argv[1]; tool_ids = set(sys.argv[2:])
path = os.path.join(repo, ".ci", "config.json")
if not os.path.exists(path):
    print("  SKIP: .ci/config.json not found"); sys.exit(0)

with open(path) as f:
    ci = json.load(f)

ok = True
for pname, ids in ci.get("profiles", {}).items():
    if not isinstance(ids, list):
        continue
    for tid in ids:
        if tid.startswith("__"):
            continue
        if tid not in tool_ids:
            print(f"  WARN: profile '{pname}' references unknown tool '{tid}'")
            ok = False

if ok:
    print("  OK: all profile tool IDs are valid")
sys.exit(0 if ok else 1)
PYEOF
    then : ; else issues=$(( issues + 1 )); fi

    # ── server/internal/api/handlers.go ──────────────────────────────────
    echo ""
    echo -e "${BOLD}Checking handlers.go profile ToolIDs...${RESET}"
    if python3 - "$REPO_ROOT" "${all_ids[@]}" <<'PYEOF'
import sys, re, os

repo = sys.argv[1]; tool_ids = set(sys.argv[2:])
path = os.path.join(repo, "server", "internal", "api", "handlers.go")
if not os.path.exists(path):
    print("  SKIP: handlers.go not found"); sys.exit(0)

content = open(path).read()
arrays  = re.findall(r'ToolIDs:\s*\[\]string\{([^}]+)\}', content)
ok = True
for arr in arrays:
    for m in re.finditer(r'"([^"]+)"', arr):
        tid = m.group(1)
        if tid == "__all__":
            continue
        # IDs may use path form like "toolchains/clang"; accept either the full path or the last segment
        if tid not in tool_ids and tid.split("/")[-1] not in tool_ids:
            print(f"  WARN: handlers.go references unknown tool '{tid}'")
            ok = False

if ok:
    print("  OK: all handlers.go ToolIDs are valid")
sys.exit(0 if ok else 1)
PYEOF
    then : ; else issues=$(( issues + 1 )); fi

    # ── install-cli.sh — detect orphaned INSTALL_ variables ──────────────
    echo ""
    echo -e "${BOLD}Checking install-cli.sh for orphaned INSTALL_ variables...${RESET}"
    python3 - "$REPO_ROOT" "${all_ids[@]}" <<'PYEOF'
import sys, re, os

repo = sys.argv[1]; tool_ids = set(sys.argv[2:])
path = os.path.join(repo, "install-cli.sh")
if not os.path.exists(path):
    print("  SKIP: install-cli.sh not found"); sys.exit(0)

content = open(path).read()
# Find INSTALL_<NAME>=true lines
variables = re.findall(r'INSTALL_([A-Z0-9_]+)=true', content)
ok = True
for var in set(variables):
    # Convert UPPER_SNAKE back to lowercase-hyphen to match IDs
    candidate = var.lower().replace("_", "-")
    candidate2 = var.lower().replace("_", "")
    if candidate not in tool_ids and candidate2 not in tool_ids:
        print(f"  NOTE: INSTALL_{var} in install-cli.sh — no matching tool ID '{candidate}' (may be a variant name, verify manually)")
        ok = False

if ok:
    print("  OK: all INSTALL_ variables map to known tool IDs")
sys.exit(0)
PYEOF
    # install-cli.sh check is informational only, does not increment issues

    echo ""
    if (( issues == 0 )); then
        ok "All checks passed."
    else
        warn "${issues} check(s) found issues — review warnings above."
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# help
# ═══════════════════════════════════════════════════════════════════════════
cmd_help() {
    echo ""
    echo -e "${BOLD}pkg.sh — airgap-devkit package manager${RESET}"
    echo ""
    echo "  Usage: bash scripts/pkg.sh <command> [args]"
    echo ""
    printf "  ${CYAN}%-34s${RESET} %s\n" "list"                        "List all bundled tools and versions"
    printf "  ${CYAN}%-34s${RESET} %s\n" "remove <id>"                 "Remove a tool from the kit"
    printf "  ${CYAN}%-34s${RESET} %s\n" "set-version <id> <version>"  "Change a tool's pinned version"
    printf "  ${CYAN}%-34s${RESET} %s\n" "add <id>"                    "Scaffold a new tool directory"
    printf "  ${CYAN}%-34s${RESET} %s\n" "check"                       "Audit configuration consistency"
    echo ""
    echo "  Examples:"
    echo "    bash scripts/pkg.sh list"
    echo "    bash scripts/pkg.sh remove matlab"
    echo "    bash scripts/pkg.sh set-version cmake 3.31.0"
    echo "    bash scripts/pkg.sh add my-tool"
    echo "    bash scripts/pkg.sh check"
    echo ""
    echo "  See .claude/adding-tools.md for the full tool addition checklist."
    echo ""
}

# ── main dispatch ────────────────────────────────────────────────────────────
case "${1:-help}" in
    list)        cmd_list ;;
    remove)      cmd_remove "${2:-}" ;;
    set-version) cmd_set_version "${2:-}" "${3:-}" ;;
    add)         cmd_add "${2:-}" ;;
    check)       cmd_check ;;
    *)           cmd_help ;;
esac
