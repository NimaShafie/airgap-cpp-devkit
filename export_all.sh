#!/bin/bash

##############################################################################
# export_all.sh
#
# Author: Nima Shafie
#
# Purpose: Recreate a Git super repository + submodules from bundles created
#          by bundle_all.sh, suitable for air-gapped use.
#
# Features:
#  - Auto-detects most recent *_import folder (or use IMPORT_FOLDER_OVERRIDE)
#  - Verifies SHA256 for ALL bundles (uses bundle_verification.txt from import)
#  - Clones super repo from bundle, materializes local branches, removes remote
#  - Restores submodule bundles into local cache: <repo>/_submodule_cache/<path>
#  - Provides git scheckout to switch branches + fully init submodules offline
#
# Requirements: git, sha256sum
##############################################################################

set -e
set -u

# Suppress noisy git progress/warnings
exec 3>&2
exec 2>&1

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=echo

##############################################################################
# USER CONFIGURATION
##############################################################################

# Leave empty to auto-detect the most recent *_import folder.
# Example: IMPORT_FOLDER_OVERRIDE="20260306_1631_import"
IMPORT_FOLDER_OVERRIDE=""

# SHA verification behavior:
#   1 = fail export if any SHA mismatch / missing expected bundle
#   0 = warn only
STRICT_SHA_VERIFY=1

##############################################################################
# SCRIPT CONFIGURATION
##############################################################################

SCRIPT_DIR="$(pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_START_TIME=$(date +%s)

print_header() {
  echo -e "${BLUE}============================================================${NC}" >&3
  echo -e "${BLUE}$1${NC}" >&3
  echo -e "${BLUE}============================================================${NC}" >&3
}

print_success(){ echo -e "${GREEN}[OK]${NC} $1" >&3; }
print_warning(){ echo -e "${YELLOW}[WARN]${NC} $1" >&3; }
print_error(){ echo -e "${RED}[ERR]${NC} $1" >&3; }
print_info(){ echo -e "${YELLOW}[INFO]${NC} $1" >&3; }

##############################################################################
# VALIDATION
##############################################################################

print_header "Git Export Script - Recreate Repository from Bundles"

command -v git >/dev/null 2>&1 || { print_error "Git is not installed"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { print_error "sha256sum is not installed"; exit 1; }

##############################################################################
# Locate import folder
##############################################################################

print_info "Auto-detecting import folder..."

IMPORT_FOLDER=""
if [ -n "${IMPORT_FOLDER_OVERRIDE}" ]; then
  IMPORT_FOLDER="$SCRIPT_DIR/${IMPORT_FOLDER_OVERRIDE}"
else
  IMPORT_FOLDER=$(find "$SCRIPT_DIR" -maxdepth 1 -type d -name "*_import" | sort -r | head -n 1 || true)
fi

if [ -z "${IMPORT_FOLDER}" ] || [ ! -d "${IMPORT_FOLDER}" ]; then
  print_error "Could not find *_import folder in: $SCRIPT_DIR"
  print_info "Set IMPORT_FOLDER_OVERRIDE at the top of export_all.sh if needed"
  exit 1
fi

IMPORT_NAME=$(basename "$IMPORT_FOLDER")
EXPORT_NAME="${IMPORT_NAME%_import}_export"
EXPORT_FOLDER="$SCRIPT_DIR/$EXPORT_NAME"

print_success "Found import folder: $IMPORT_NAME"
print_info "Export folder will be: $EXPORT_NAME"

mkdir -p "$EXPORT_FOLDER"

EXPORT_LOG="$EXPORT_FOLDER/export_log.txt"
{
  echo "================================================================="
  echo "Git Export Log"
  echo "================================================================="
  echo "Generated: $(date)"
  echo "Ran by: $(whoami)"
  echo "Import Folder: $IMPORT_FOLDER"
  echo "Export Folder: $EXPORT_FOLDER"
  echo "Strict SHA Verify: $STRICT_SHA_VERIFY"
  echo "================================================================="
  echo ""
} > "$EXPORT_LOG"

log() { echo "$1" | tee -a "$EXPORT_LOG" >&3; }

##############################################################################
# Step 0: SHA256 verification
##############################################################################

print_header "Step 0: Verifying Bundle SHA256"

VERIFY_FILE="$IMPORT_FOLDER/bundle_verification.txt"

if [ ! -f "$VERIFY_FILE" ]; then
  print_warning "bundle_verification.txt not found in import folder - skipping SHA verification"
  print_info "Expected at: $VERIFY_FILE"
  echo "[WARN] bundle_verification.txt missing - skipped SHA verification" >> "$EXPORT_LOG"
else
  declare -A EXPECTED_SHA
  parse_ok=0

  while IFS='|' read -r f s; do
    [ -z "${f}" ] && continue
    [ -z "${s}" ] && continue
    EXPECTED_SHA["$f"]="$s"
    parse_ok=1
  done < <(
    awk '
      BEGIN{file=""; sha=""}
      /^Bundle File:[[:space:]]*/{
        file=$0; sub(/^Bundle File:[[:space:]]*/,"",file); gsub(/\r/,"",file)
      }
      /^SHA256:[[:space:]]*/{
        sha=$0; sub(/^SHA256:[[:space:]]*/,"",sha); gsub(/\r/,"",sha)
        if(file!="" && sha!=""){
          print file "|" sha
          file=""; sha=""
        }
      }
    ' "$VERIFY_FILE"
  )

  if [ "$parse_ok" -ne 1 ]; then
    print_warning "Could not parse expected SHA256 values from bundle_verification.txt"
    print_info "Continuing without SHA enforcement"
    echo "[WARN] Could not parse SHA values - skipped SHA enforcement" >> "$EXPORT_LOG"
  else
    ALL_BUNDLES=$(find "$IMPORT_FOLDER" -type f -name "*.bundle" | sort || true)

    if [ -z "${ALL_BUNDLES}" ]; then
      print_error "No .bundle files found in import folder: $IMPORT_FOLDER"
      exit 1
    fi

    mismatch=0
    missing=0
    extra=0

    for key in "${!EXPECTED_SHA[@]}"; do
      expected="${EXPECTED_SHA[$key]}"
      found_path=$(find "$IMPORT_FOLDER" -type f -name "$key" | head -n 1 || true)

      if [ -z "${found_path}" ]; then
        missing=$((missing+1))
        log "[ERR] Missing bundle expected by verification log: $key"
        continue
      fi

      actual=$(sha256sum "$found_path" | awk '{print $1}')

      if [ "$actual" != "$expected" ]; then
        mismatch=$((mismatch+1))
        log "[ERR] SHA MISMATCH: $key"
        log "      expected: $expected"
        log "      actual:   $actual"
      else
        log "[OK] SHA verified: $key"
      fi
    done

    while IFS= read -r bundle_path; do
      [ -z "${bundle_path}" ] && continue
      bn=$(basename "$bundle_path")
      if [ -z "${EXPECTED_SHA[$bn]+x}" ]; then
        extra=$((extra+1))
        log "[WARN] Bundle not listed in verification log (not validated): $bn"
      fi
    done < <(echo "$ALL_BUNDLES")

    if [ "$missing" -gt 0 ] || [ "$mismatch" -gt 0 ]; then
      if [ "$STRICT_SHA_VERIFY" -eq 1 ]; then
        print_error "SHA verification failed (missing: $missing, mismatched: $mismatch)"
        exit 1
      else
        print_warning "SHA verification issues found (missing: $missing, mismatched: $mismatch)"
        print_info "STRICT_SHA_VERIFY=0 so continuing"
      fi
    else
      print_success "SHA verification passed (validated: ${#EXPECTED_SHA[@]}, unlisted: $extra)"
    fi
  fi
fi

##############################################################################
# Step 1: Locate super repository bundle
##############################################################################

print_header "Step 1: Locating Super Repository Bundle"

SUPER_BUNDLE=$(find "$IMPORT_FOLDER" -maxdepth 1 -type f -name "*.bundle" | head -n 1 || true)
if [ -z "${SUPER_BUNDLE}" ]; then
  print_error "No super repository bundle found in import folder"
  exit 1
fi

REPO_NAME=$(basename "$SUPER_BUNDLE" .bundle)
REPO_DIR="$EXPORT_FOLDER/$REPO_NAME"

print_success "Found super repository bundle: $SUPER_BUNDLE"
print_info "Repository name: $REPO_NAME"

##############################################################################
# Step 2: Clone super repository
##############################################################################

print_header "Step 2: Cloning Super Repository"

print_info "Cloning to: $REPO_DIR"

rm -rf "$REPO_DIR" >/dev/null 2>&1 || true

print_info "Cloning super repository from bundle..."

git clone "$SUPER_BUNDLE" "$REPO_DIR" --quiet

cd "$REPO_DIR"

git config --local protocol.file.allow always

default_branch=""
if git show-ref --verify --quiet refs/heads/main; then
  default_branch="main"
elif git show-ref --verify --quiet refs/heads/develop; then
  default_branch="develop"
elif git show-ref --verify --quiet refs/heads/master; then
  default_branch="master"
else
  default_branch=$(git for-each-ref --format='%(refname:short)' refs/heads | head -n 1 || true)
fi

print_info "Determining default branch..."
if [ -n "${default_branch}" ]; then
  git checkout "$default_branch" >/dev/null 2>&1 || true
  print_success "Checked out branch: $default_branch"
else
  print_warning "Could not determine default branch"
fi

print_info "Creating local branches from bundle refs..."

git for-each-ref --format='%(refname:short)' refs/remotes/origin/ 2>/dev/null | while read -r rb; do
  [ -z "$rb" ] && continue
  [ "$rb" = "origin/HEAD" ] && continue
  [ "$rb" = "origin/origin" ] && continue
  git branch -f "${rb#origin/}" "$rb" >/dev/null 2>&1 || true
  git branch --set-upstream-to="$rb" "${rb#origin/}" >/dev/null 2>&1 || true
done

if git remote get-url origin >/dev/null 2>&1; then
  git remote remove origin >/dev/null 2>&1 || true
fi

print_success "Local branches created for all remote refs"

if git show-ref --verify --quiet refs/heads/origin; then
  git branch -D origin >/dev/null 2>&1 || true
fi

BRANCH_COUNT=$(git branch | wc -l | tr -d ' ')
TAG_COUNT=$(git tag | wc -l | tr -d ' ')
COMMIT_COUNT=$(git rev-list --all --count 2>/dev/null || echo 0)

{
  echo "================================================================="
  echo "SUPER REPOSITORY: $REPO_NAME"
  echo "================================================================="
  echo "Cloned to: $REPO_DIR"
  echo "Branches: $BRANCH_COUNT"
  echo "Tags: $TAG_COUNT"
  echo "Total Commits: $COMMIT_COUNT"
  echo ""
} >> "$EXPORT_LOG"

print_success "Super repository cloned successfully"

##############################################################################
# Step 3: Discover submodule bundles
##############################################################################

print_header "Step 3: Discovering Submodule Bundles"

SUB_BUNDLES=$(cd "$IMPORT_FOLDER" && find . -type f -name "*.bundle" | grep -v "^\./${REPO_NAME}\.bundle$" | sort || true)

if [ -z "${SUB_BUNDLES}" ]; then
  print_warning "No submodule bundles found"
  SUB_BUNDLE_COUNT=0
else
  SUB_BUNDLE_COUNT=$(echo "$SUB_BUNDLES" | wc -l | tr -d ' ')
  print_success "Found $SUB_BUNDLE_COUNT submodule bundle(s)"
fi

##############################################################################
# Step 4: Restore submodule bundles into local cache
##############################################################################

print_header "Step 4: Restoring Submodules into Local Cache"

CACHE_DIR="$REPO_DIR/_submodule_cache"
mkdir -p "$CACHE_DIR"

restored=0
idx=0

if [ "$SUB_BUNDLE_COUNT" -gt 0 ]; then
  while IFS= read -r rel_bundle; do
    [ -z "${rel_bundle}" ] && continue
    idx=$((idx+1))

    rel_no_dot=${rel_bundle#./}
    sub_rel_dir=$(dirname "$rel_no_dot")
    sub_bundle_file=$(basename "$rel_no_dot")
    sub_name=$(basename "$sub_bundle_file" .bundle)

    src_bundle="$IMPORT_FOLDER/$rel_no_dot"
    dest_repo="$CACHE_DIR/${sub_rel_dir}/${sub_name}"

    mkdir -p "$(dirname "$dest_repo")"
    rm -rf "$dest_repo" >/dev/null 2>&1 || true

    print_info "[$idx/$SUB_BUNDLE_COUNT] Restoring to cache: _submodule_cache/${sub_rel_dir}/${sub_name}"

    git clone "$src_bundle" "$dest_repo" --quiet || true

    if [ ! -d "$dest_repo/.git" ]; then
      print_warning "[$idx/$SUB_BUNDLE_COUNT] Restore failed (skipping): $rel_no_dot"
      echo "[WARN] Cache restore failed: $rel_no_dot" >> "$EXPORT_LOG"
      continue
    fi

    (
      cd "$dest_repo"
      git config --local protocol.file.allow always

      git for-each-ref --format='%(refname:short)' refs/remotes/origin/ 2>/dev/null | while read -r rb; do
        [ -z "$rb" ] && continue
        [ "$rb" = "origin/HEAD" ] && continue
        [ "$rb" = "origin/origin" ] && continue
        git branch -f "${rb#origin/}" "$rb" >/dev/null 2>&1 || true
      done

      git remote remove origin >/dev/null 2>&1 || true
    )

    restored=$((restored+1))
  done < <(echo "$SUB_BUNDLES")
fi

print_success "Restored $restored submodule bundle(s) into cache"

##############################################################################
# Step 5: Configure git scheckout <branch>
##############################################################################

print_header "Step 5: Configuring git scheckout <branch>"

SCK_SCRIPT="$REPO_DIR/.git/scheckout.sh"

cat > "$SCK_SCRIPT" <<'SCKEOF'
#!/bin/bash
set -e

if [ $# -lt 1 ]; then
  echo "Usage: git scheckout <branch>" >&2
  exit 1
fi

TARGET="$1"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then
  echo "Not in a git repository" >&2
  exit 1
fi

cd "$ROOT"

git checkout "$TARGET" >/dev/null 2>&1

SUPER_ROOT="$ROOT"
CACHE_DIR="$SUPER_ROOT/_submodule_cache"

git config --local protocol.file.allow always >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Stale submodule removal
#
# EXPECTED_ROOT lists only top-level gitlinks, so we keep any working dir
# that is UNDER a top-level gitlink (nested submodules), and only remove
# dirs that are completely outside the new branch's submodule tree.
# ---------------------------------------------------------------------------
EXPECTED_ROOT=$(git ls-tree -r --full-name HEAD 2>/dev/null | awk '$1=="160000" {print $4}' || true)

remove_submodule_dir() {
  local p="$1"
  git submodule deinit -f -- "$p" >/dev/null 2>&1 || true
  if [ -d ".git/modules/$p" ]; then
    rm -rf ".git/modules/$p" >/dev/null 2>&1 || true
  fi
  if [ -e "$p" ]; then
    rm -rf "$p" >/dev/null 2>&1 || true
  fi
}

# BUG FIX (Bug 3): A submodule dir is stale only when it is NOT a direct match
# AND NOT nested under any expected top-level gitlink.  The previous code only
# checked for exact matches, so nested submodules were always flagged stale.
find_stale_submodules() {
  find . -mindepth 2 -maxdepth 10 -type f -name ".git" 2>/dev/null | sed 's#^\./##' | while read -r gitfile; do
    dir=$(dirname "$gitfile")
    stale=true
    while IFS= read -r expected; do
      [ -z "$expected" ] && continue
      # Keep if exact match OR nested under an expected top-level submodule
      if [ "$dir" = "$expected" ] || [[ "$dir" == "$expected/"* ]]; then
        stale=false
        break
      fi
    done < <(echo "$EXPECTED_ROOT")
    if $stale; then
      echo "$dir"
    fi
  done | sort -u
}

STALE=$(find_stale_submodules)
if [ -n "$STALE" ]; then
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    remove_submodule_dir "$p"
  done < <(echo "$STALE")
fi

# ---------------------------------------------------------------------------
# rewrite_gitmodules_to_cache
#
# Temporarily rewrites .gitmodules URLs to point to _submodule_cache, then
# syncs those URLs into .git/config so that "git submodule update --init"
# clones from the cache.
#
# BUG FIX (Bug 2): The original code left .gitmodules permanently modified,
# causing "git checkout" to fail on the NEXT scheckout call because the
# tracked file had local changes.  We now restore .gitmodules AFTER the
# submodule update so the working tree is always clean.
# (Restoration is done in init_one_level, after git submodule update --init.)
# ---------------------------------------------------------------------------
rewrite_gitmodules_to_cache() {
  local repo_root="$1"
  local super_rel="$2"

  if [ ! -f "$repo_root/.gitmodules" ]; then
    return
  fi

  git -C "$repo_root" config -f "$repo_root/.gitmodules" --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null | while read -r key; do
    [ -z "$key" ] && continue

    name=$(echo "$key" | sed 's/^submodule\.//; s/\.path$//')
    sub_path=$(git -C "$repo_root" config -f "$repo_root/.gitmodules" "$key" 2>/dev/null || true)
    [ -z "$sub_path" ] && continue

    if [ -n "$super_rel" ]; then
      full_rel="$super_rel/$sub_path"
    else
      full_rel="$sub_path"
    fi

    if [ -d "$CACHE_DIR/$full_rel/.git" ]; then
      git -C "$repo_root" config -f "$repo_root/.gitmodules" "submodule.${name}.url" "$CACHE_DIR/$full_rel" >/dev/null 2>&1 || true
    fi
  done

  # Propagate rewritten URLs from .gitmodules into .git/config
  git -C "$repo_root" submodule sync >/dev/null 2>&1 || true
  # NOTE: .gitmodules is still dirty here; init_one_level restores it after update
}

# Initialize direct submodules for one repo level (no recursion)
init_one_level() {
  local repo_root="$1"
  local super_rel="$2"

  rewrite_gitmodules_to_cache "$repo_root" "$super_rel"
  git -C "$repo_root" -c protocol.file.allow=always submodule update --init --jobs 4 >/dev/null 2>&1 || true

  # BUG FIX (Bug 2): Restore .gitmodules to committed state so git checkout
  # on the next scheckout call does not fail due to a dirty tracked file.
  if [ -f "$repo_root/.gitmodules" ]; then
    git -C "$repo_root" checkout -- .gitmodules >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# finalize_repo
#
# BUG FIX (Bug 1): The original code used "git submodule foreach --recursive"
# to materialize local branches and remove the origin remote.  That foreach
# runs inside a git-spawned subshell, and its entire output was silenced with
# ">/dev/null 2>&1 || true".  When the foreach failed (e.g. due to module
# state issues), it did so completely silently, leaving every submodule with
# only one local branch and origin still present.
#
# We now call finalize_repo directly on each submodule path using "git -C",
# which is deterministic and has no silent-failure risk from foreach.
# ---------------------------------------------------------------------------
finalize_repo() {
  local repo_dir="$1"

  git -C "$repo_dir" config --local protocol.file.allow always >/dev/null 2>&1 || true

  # Materialize all local branches from remote-tracking refs
  git -C "$repo_dir" for-each-ref --format='%(refname:short)' refs/remotes/origin/ 2>/dev/null | \
  while IFS= read -r rb; do
    [ -z "$rb" ] && continue
    [ "$rb" = "origin/HEAD" ] && continue
    [ "$rb" = "origin/origin" ] && continue
    lb="${rb#origin/}"
    git -C "$repo_dir" branch -f "$lb" "$rb" >/dev/null 2>&1 || true
  done

  # Remove origin remote so the repo is fully air-gapped
  if git -C "$repo_dir" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo_dir" remote remove origin >/dev/null 2>&1 || true
  fi

  # Clean up any stray local branch named "origin" (artifact of some clone ops)
  if git -C "$repo_dir" show-ref --verify --quiet refs/heads/origin; then
    git -C "$repo_dir" branch -D origin >/dev/null 2>&1 || true
  fi
}

# Recursively initialize submodules depth-first, rewriting URLs at each level
# BEFORE cloning children, then finalize each child after full recursion.
init_recursive() {
  local repo_root="$1"
  local super_rel="$2"

  init_one_level "$repo_root" "$super_rel"

  local child_paths
  child_paths=$(git -C "$repo_root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' || true)
  if [ -z "$child_paths" ]; then
    return
  fi

  while IFS= read -r child; do
    [ -z "$child" ] && continue

    local child_super_rel
    if [ -n "$super_rel" ]; then
      child_super_rel="$super_rel/$child"
    else
      child_super_rel="$child"
    fi

    if [ -d "$repo_root/$child/.git" ] || [ -f "$repo_root/$child/.git" ]; then
      init_recursive "$repo_root/$child" "$child_super_rel"
      # Finalize this child after it and all its descendants are initialized
      finalize_repo "$repo_root/$child"
    fi
  done < <(echo "$child_paths")
}

# Start at superproject root
init_recursive "$SUPER_ROOT" ""

# ── Final air-gap pass ────────────────────────────────────────────────────
# Walk every initialized submodule working copy and ensure:
#   * all local branches are materialized from refs/remotes/origin/*
#   * the origin remote is removed
#
# This is a deterministic second pass that guarantees correct state even
# when the inline finalize_repo calls inside init_recursive are disrupted
# by Windows-specific git locking, gitmodules restoration ordering, or
# submodule sync re-setting the remote URL mid-recursion.
#
# Uses process substitution (not a pipe) so the while body runs in the
# current shell -- no subshell variable-scope or silent-exit risk.
# The _submodule_cache repos have .git DIRECTORIES (not files), so
# "-type f" already excludes them; the grep -v is belt-and-suspenders.
while IFS= read -r sub_gitfile; do
  [ -z "$sub_gitfile" ] && continue
  sub_dir=$(dirname "$sub_gitfile")
  [ -z "$sub_dir" ] && continue
  finalize_repo "$sub_dir"
done < <(find "$SUPER_ROOT" -mindepth 2 -name ".git" -type f 2>/dev/null \
           | grep -v "_submodule_cache" \
           | sort)

echo "OK switched to '$TARGET' with submodules initialized"
SCKEOF

chmod +x "$SCK_SCRIPT"

cd "$REPO_DIR"
git config alias.scheckout "!bash .git/scheckout.sh" >/dev/null 2>&1 || true

print_success "Configured: git scheckout <branch>"

##############################################################################
# Step 6: Initialize submodules for current branch
##############################################################################

print_header "Step 6: Initializing Submodules for Current Branch"

cd "$REPO_DIR"

current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [ -z "$current_branch" ]; then
  print_warning "Could not determine current branch"
else
  print_info "Initializing submodules on branch: $current_branch"
  git scheckout "$current_branch" >/dev/null 2>&1 || true
  print_success "Submodules initialized for: $current_branch"
fi

##############################################################################
# Step 7: Documentation
##############################################################################

print_header "Step 7: Creating Documentation"

NOTES="$EXPORT_FOLDER/NETWORK_CONNECTIVITY_NOTES.txt"
cat > "$NOTES" <<EOF_NOTES
NETWORK / AIR-GAPPED NOTES

- This repo was recreated from git bundle files.
- No network remotes were kept.

Clean branch switching (handles Windows submodule cleanup):

  cd $REPO_DIR
  git scheckout main
  git scheckout develop

How it works:
- Submodule bundles are restored into:
    _submodule_cache/
- git scheckout rewrites .gitmodules URLs at every nesting level to the cache,
  then initializes submodules level-by-level offline.
EOF_NOTES

print_success "Network connectivity notes created: $NOTES"

##############################################################################
# FINAL SUMMARY
##############################################################################

print_header "Export Complete!"

SCRIPT_END_TIME=$(date +%s)
ELAPSED_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
MINUTES=$((ELAPSED_TIME / 60))
SECONDS=$((ELAPSED_TIME % 60))

TOTAL_SIZE=$(du -sh "$EXPORT_FOLDER" | awk '{print $1}')

log "================================================================="
log "SUMMARY"
log "================================================================="
log "Total Export Size: $TOTAL_SIZE"
log "Super Repository: $REPO_NAME"
log "Submodule Bundles Discovered: $SUB_BUNDLE_COUNT"
log "Submodule Bundles Restored: $restored"
log "Repository Path: $REPO_DIR"
log "Time Taken: ${MINUTES}m ${SECONDS}s"
log "Script Completed: $(date +%Y%m%d_%H%M)"
log "================================================================="

echo "" >&3
print_success "Export folder: $EXPORT_FOLDER"
print_success "Total size: $TOTAL_SIZE"
print_success "Super repository: $REPO_NAME"
print_success "Submodule bundles discovered: $SUB_BUNDLE_COUNT"
print_success "Submodule bundles restored: $restored"
print_success "Time taken: ${MINUTES}m ${SECONDS}s"

echo "" >&3
print_info "Repository location:"
echo "  $REPO_DIR" >&3

echo "" >&3
print_info "Documentation created:"
echo "  - export_log.txt (detailed export log)" >&3
echo "  - NETWORK_CONNECTIVITY_NOTES.txt (branch switching guide)" >&3

echo "" >&3
print_warning "Important Notes:"
echo "  1. Use: git scheckout <branch> for clean branch switches with submodules" >&3
echo "  2. Submodule URLs are rewritten to local _submodule_cache paths (all levels)" >&3

echo "" >&3
print_success "All done!"

echo "" >&3
print_info "You can now work with your repository at:"
echo "  cd $REPO_DIR" >&3