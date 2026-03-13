#!/bin/bash

##############################################################################
# bundle_all.sh
#
# Author: Nima Shafie
#
# Purpose: Bundle a Git super repository with all its submodules (including
#          nested + deeply nested) for transfer to air-gapped networks.
#          Creates git bundles with full history and generates verification logs.
#
# Usage: ./bundle_all.sh
#
# Requirements: git, sha256sum
##############################################################################

set -e
set -u

##############################################################################
# SUPPRESS ALL GIT WARNINGS - Save stderr to file descriptor 3 for our messages
##############################################################################
exec 3>&2
exec 2>&1

##############################################################################
# PERFORMANCE OPTIMIZATION
##############################################################################
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=echo

##############################################################################
# USER CONFIGURATION - EDIT THESE VARIABLES
##############################################################################

# Local path to the Git super repository you want to bundle
REPO_PATH="$HOME/Desktop/git-bundles/test/full-test-repo"
#REPO_PATH="/path/to/your/super-repository"

# SSH remote Git address (for reference/documentation purposes)
REMOTE_GIT_ADDRESS="file://$HOME/Desktop/git-bundles/test/full-test-repo"
#REMOTE_GIT_ADDRESS="git@bitbucket.org:your-org/your-repo.git"

##############################################################################
# SCRIPT CONFIGURATION - Generally no need to edit below
##############################################################################

SCRIPT_DIR="$(pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M)
EXPORT_FOLDER="${SCRIPT_DIR}/${TIMESTAMP}_import"
LOG_FILE="${EXPORT_FOLDER}/bundle_verification.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_START_TIME=$(date +%s)

##############################################################################
# OUTPUT HELPERS
##############################################################################

print_header() {
  echo -e "${BLUE}============================================================${NC}" >&3
  echo -e "${BLUE}$1${NC}" >&3
  echo -e "${BLUE}============================================================${NC}" >&3
}

print_success(){ echo -e "${GREEN}[OK]${NC} $1" >&3; }
print_warning(){ echo -e "${YELLOW}[WARN]${NC} $1" >&3; }
print_error(){ echo -e "${RED}[ERR]${NC} $1" >&3; }
print_info(){ echo -e "${YELLOW}[INFO]${NC} $1" >&3; }

log_message(){ echo "$1" | tee -a "$LOG_FILE" >&3; }

##############################################################################
# GIT HELPERS
##############################################################################

checkout_default_branch() {
  local repo_label="$1"
  local current
  current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  if git show-ref --verify --quiet refs/heads/main; then
    [ "$current" = "main" ] || git checkout main >/dev/null 2>&1 || true
    echo "Checked out default branch 'main' for ${repo_label}" >> "$LOG_FILE"
    return
  fi
  if git show-ref --verify --quiet refs/heads/develop; then
    [ "$current" = "develop" ] || git checkout develop >/dev/null 2>&1 || true
    echo "Checked out default branch 'develop' for ${repo_label}" >> "$LOG_FILE"
    return
  fi
  if git show-ref --verify --quiet refs/heads/master; then
    [ "$current" = "master" ] || git checkout master >/dev/null 2>&1 || true
    echo "Checked out default branch 'master' for ${repo_label}" >> "$LOG_FILE"
    return
  fi

  local first_branch
  first_branch=$(git for-each-ref --format='%(refname:short)' refs/heads | head -n 1)
  if [ -n "$first_branch" ] && [ "$current" != "$first_branch" ]; then
    git checkout "$first_branch" >/dev/null 2>&1 || true
    echo "Checked out fallback branch '${first_branch}' for ${repo_label}" >> "$LOG_FILE"
  fi
}

# Count local branches
count_local_heads() {
  git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | wc -l | tr -d ' '
}

# Count remote origin/* branches (excluding origin/HEAD)
count_origin_heads() {
  git for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null | \
    grep -v '^origin/HEAD$' | wc -l | tr -d ' '
}

# Ensure local heads cover origin/* heads. Fetch/materialize if remote has more.
ensure_local_branches_from_origin() {
  local repo_label="$1"

  local remote_url
  remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
  if [ -z "$remote_url" ]; then
    return
  fi

  local local_count remote_count
  local_count=$(count_local_heads)
  remote_count=$(count_origin_heads)

  if [ "$remote_count" -eq 0 ] && [ "$local_count" -le 1 ]; then
    git -c protocol.file.allow=always fetch --all --tags --quiet --no-progress 2>/dev/null || true
    remote_count=$(count_origin_heads)
  fi

  if [ "$remote_count" -gt "$local_count" ]; then
    print_info "Fetching to materialize missing branches for $repo_label (origin: $remote_count, local: $local_count)"
    git -c protocol.file.allow=always fetch --all --tags --quiet --no-progress 2>/dev/null || true

    git for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null | while read -r rb; do
    case "$rb" in
        origin/*) ;;
        *) continue ;;
    esac
    [ "$rb" = "origin/HEAD" ] && continue
    git branch -f "${rb#origin/}" "$rb" 2>/dev/null || true
    done
  else
    git -c protocol.file.allow=always fetch --tags --quiet --no-progress 2>/dev/null || true
  fi
}

# Bundle current repo to a path (after ensuring local branches are complete)
bundle_repo_to_path() {
  local repo_label="$1"
  local out_bundle="$2"

  ensure_local_branches_from_origin "$repo_label"

  local final_branches
  final_branches=$(count_local_heads)
  if [ "$final_branches" -eq 0 ]; then
    git branch main HEAD 2>/dev/null || git branch master HEAD 2>/dev/null || true
  fi

  git -c advice.detachedHead=false bundle create "$out_bundle" --all --quiet 2>&1 | \
    grep -v "Enumerating\|Counting\|Delta\|Compressing\|Writing\|Total\|detached HEAD\|Note: switching" >> "$LOG_FILE" || true
}

# Ensure a particular submodule path is initialized at least once by checking out a branch that contains it.
ensure_submodule_initialized_via_branch() {
  local parent_repo_root="$1"      # absolute path to the parent repo working dir
  local sub_path="$2"              # submodule path relative to that parent repo
  local branch_to_use="$3"         # branch name in that parent repo that contains the gitlink

  if [ -e "$parent_repo_root/$sub_path/.git" ]; then
    return 0
  fi

  if [ -z "$branch_to_use" ]; then
    return 1
  fi

  local original_branch
  original_branch=$(git -C "$parent_repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  echo "Initializing submodule '$sub_path' in '$parent_repo_root' via branch '$branch_to_use' (was '$original_branch')" >> "$LOG_FILE"

  git -C "$parent_repo_root" checkout "$branch_to_use" >/dev/null 2>&1 || true
  git -C "$parent_repo_root" -c protocol.file.allow=always submodule sync --recursive >/dev/null 2>&1 || true

  git -C "$parent_repo_root" -c protocol.file.allow=always -c advice.detachedHead=false \
    submodule update --init --recursive --jobs 4 -- "$sub_path" 2>&1 | \
    grep -v "detached HEAD\|Note: switching to\|Note: checking out\|HEAD is now at" >> "$LOG_FILE" || true

  if [ -n "$original_branch" ]; then
    git -C "$parent_repo_root" checkout "$original_branch" >/dev/null 2>&1 || true
  fi

  if [ -e "$parent_repo_root/$sub_path/.git" ]; then
    return 0
  fi
  return 1
}

# True git repo check (more reliable than only testing for .git)
is_git_repo_dir() {
  local d="$1"
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

##############################################################################
# RECURSIVE DISCOVERY
##############################################################################
# We discover gitlinks across all local branches for:
#  - the super repo root (prefix "")
#  - each discovered submodule repo (prefix "services/user-service", etc.)
#
# Data structures:
#  - SEEN_REPOS_ABS[abs_repo_root]=1
#  - SEEN_SUB_REPO_PATHS[fullpath]=1 (fullpath relative to super root)
#  - FIRST_BRANCH_FOR_SUB["parent_abs|subpath"]=branch
##############################################################################

declare -A SEEN_REPOS_ABS
declare -A SEEN_SUB_REPO_PATHS
declare -A FIRST_BRANCH_FOR_SUB

# Queue stored in temp files (stable, avoids string/head/tail pitfalls)
QUEUE_FILE_ROOTS=""
QUEUE_FILE_PREFIXES=""

queue_init() {
  QUEUE_FILE_ROOTS="$(mktemp)"
  QUEUE_FILE_PREFIXES="$(mktemp)"
  : > "$QUEUE_FILE_ROOTS"
  : > "$QUEUE_FILE_PREFIXES"
}

queue_cleanup() {
  rm -f "$QUEUE_FILE_ROOTS" >/dev/null 2>&1 || true
  rm -f "$QUEUE_FILE_PREFIXES" >/dev/null 2>&1 || true
}

enqueue_repo() {
  local abs_root="$1"
  local prefix="$2"

  if [ -n "${SEEN_REPOS_ABS[$abs_root]+x}" ]; then
    return
  fi
  SEEN_REPOS_ABS[$abs_root]=1

  echo "$abs_root" >> "$QUEUE_FILE_ROOTS"
  echo "$prefix" >> "$QUEUE_FILE_PREFIXES"
}

dequeue_repo() {
  local _out_root_var="$1"
  local _out_prefix_var="$2"

  local r p
  r=$(head -n 1 "$QUEUE_FILE_ROOTS" 2>/dev/null || true)
  p=$(head -n 1 "$QUEUE_FILE_PREFIXES" 2>/dev/null || true)

  if [ -z "$r" ]; then
    return 1
  fi

  # drop first line
  tail -n +2 "$QUEUE_FILE_ROOTS" > "${QUEUE_FILE_ROOTS}.tmp" 2>/dev/null || true
  mv "${QUEUE_FILE_ROOTS}.tmp" "$QUEUE_FILE_ROOTS" 2>/dev/null || true

  tail -n +2 "$QUEUE_FILE_PREFIXES" > "${QUEUE_FILE_PREFIXES}.tmp" 2>/dev/null || true
  mv "${QUEUE_FILE_PREFIXES}.tmp" "$QUEUE_FILE_PREFIXES" 2>/dev/null || true

  eval "$_out_root_var=\$r"
  eval "$_out_prefix_var=\$p"
  return 0
}

scan_repo_for_gitlinks() {
  local repo_root="$1"   # absolute path
  local prefix="$2"      # path from super root to this repo ("" for super root)

  git -C "$repo_root" config --local protocol.file.allow always 2>/dev/null || true

  local branches
  branches=$(git -C "$repo_root" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | sort || true)
  if [ -z "$branches" ]; then
    return
  fi

  local found_in_this_repo=0

  while IFS= read -r br; do
    [ -z "$br" ] && continue

    local paths
    paths=$(git -C "$repo_root" ls-tree -r --full-name "$br" 2>/dev/null | awk '$1=="160000" {print $4}' || true)
    [ -z "$paths" ] && continue

    while IFS= read -r p; do
      [ -z "$p" ] && continue

      local full
      if [ -z "$prefix" ]; then
        full="$p"
      else
        full="$prefix/$p"
      fi

      if [ -z "${SEEN_SUB_REPO_PATHS[$full]+x}" ]; then
        SEEN_SUB_REPO_PATHS[$full]=1
      fi

      local key
      key="$repo_root|$p"
      if [ -z "${FIRST_BRANCH_FOR_SUB[$key]+x}" ]; then
        FIRST_BRANCH_FOR_SUB[$key]="$br"
      fi

      found_in_this_repo=1
    done < <(echo "$paths")
  done < <(echo "$branches")

  if [ "$found_in_this_repo" -eq 1 ]; then
    echo "Scanned repo: $repo_root (prefix: '$prefix') - found gitlinks" >> "$LOG_FILE"
  else
    echo "Scanned repo: $repo_root (prefix: '$prefix') - no gitlinks" >> "$LOG_FILE"
  fi
}

##############################################################################
# VALIDATION
##############################################################################

print_header "Git Bundle Script - Super Repository with Submodules"

command -v git >/dev/null 2>&1 || { print_error "Git is not installed"; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { print_error "sha256sum is not installed"; exit 1; }

if [ ! -d "$REPO_PATH" ]; then
  print_error "Repository path does not exist: $REPO_PATH"
  print_info "Edit REPO_PATH in bundle_all.sh"
  exit 1
fi
if [ ! -d "$REPO_PATH/.git" ]; then
  print_error "Path is not a git repository: $REPO_PATH"
  exit 1
fi

print_info "Creating export folder: $EXPORT_FOLDER"
mkdir -p "$EXPORT_FOLDER"

{
  echo "================================================================="
  echo "Git Bundle Verification Log"
  echo "================================================================="
  echo "Generated: $(date)"
  echo "Ran by: $(whoami)"
  echo "Source Repository: $REPO_PATH"
  echo "Remote Address: $REMOTE_GIT_ADDRESS"
  echo "Export Folder: $EXPORT_FOLDER"
  echo "================================================================="
  echo ""
} > "$LOG_FILE"

##############################################################################
# STEP 1: BUNDLE SUPER REPO
##############################################################################

print_header "Step 1: Bundling Super Repository"

cd "$REPO_PATH"
git config --local protocol.file.allow always

REPO_NAME=$(basename "$REPO_PATH")
BUNDLE_PATH="${EXPORT_FOLDER}/${REPO_NAME}.bundle"

print_info "Repository: $REPO_NAME"
print_info "Bundling to: $BUNDLE_PATH"

ensure_local_branches_from_origin "$REPO_NAME"

local_branch_count=$(count_local_heads)
print_info "Creating bundle with ${local_branch_count} branches..."

bundle_repo_to_path "$REPO_NAME" "$BUNDLE_PATH"

checkout_default_branch "$REPO_NAME"

print_info "Verifying bundle..."
if git bundle verify "$BUNDLE_PATH" >/dev/null 2>&1; then
  print_success "Super repository bundle verified successfully"
  bundle_status="VERIFIED"
else
  print_error "Super repository bundle verification FAILED"
  bundle_status="FAILED"
fi

bundle_sha=$(sha256sum "$BUNDLE_PATH" | awk '{print $1}')
bundle_size=$(du -h "$BUNDLE_PATH" | awk '{print $1}')
branches=$(count_local_heads)
tags=$(git tag | wc -l | tr -d ' ')
commits=$(git rev-list --all --count 2>/dev/null || echo 0)

{
  echo "================================================================="
  echo "SUPER REPOSITORY: $REPO_NAME"
  echo "================================================================="
  echo "Bundle File: ${REPO_NAME}.bundle"
  echo "Verification: $bundle_status"
  echo "SHA256: $bundle_sha"
  echo "File Size: $bundle_size"
  echo "Branches: $branches"
  echo "Tags: $tags"
  echo "Total Commits: $commits"
  echo "Path in Export: ./${REPO_NAME}.bundle"
  echo ""
} >> "$LOG_FILE"

##############################################################################
# STEP 2: RECURSIVELY DISCOVER + INIT + ENQUEUE ALL SUBMODULE REPOS
##############################################################################

print_header "Step 2: Discovering Submodule Repos (Recursive)"

queue_init
trap queue_cleanup EXIT

enqueue_repo "$REPO_PATH" ""

# BFS over repos: scan gitlinks across branches, init each discovered submodule path once, enqueue it
while :; do
  local_root=""
  local_prefix=""
  if ! dequeue_repo local_root local_prefix; then
    break
  fi

  if [ -z "$local_root" ]; then
    continue
  fi

  if ! is_git_repo_dir "$local_root"; then
    echo "Skipping non-repo root during scan: $local_root" >> "$LOG_FILE"
    continue
  fi

  # Materialize all remote branches before scanning so that submodules that only
  # appear on non-default branches (e.g. lib/feature-flags on develop) are discovered.
  if git -C "$local_root" config --get remote.origin.url >/dev/null 2>&1; then
    git -c protocol.file.allow=always -C "$local_root" fetch --all --tags --quiet --no-progress 2>/dev/null || true
    git -C "$local_root" for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null | \
      grep -v '^origin/HEAD$' | while read -r rb; do
        case "$rb" in origin/*) ;; *) continue ;; esac
        git -C "$local_root" branch -f "${rb#origin/}" "$rb" 2>/dev/null || true
      done
    echo "Pre-scan branch materialization done for: $local_root" >> "$LOG_FILE"
  fi

  scan_repo_for_gitlinks "$local_root" "$local_prefix"

  # Build unique submodule paths (relative to this repo root) across all branches in this repo
  branches_here=$(git -C "$local_root" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | sort || true)
  [ -z "$branches_here" ] && continue

  declare -A direct_seen
  direct_unique=""

  while IFS= read -r br; do
    [ -z "$br" ] && continue
    direct=$(git -C "$local_root" ls-tree -r --full-name "$br" 2>/dev/null | awk '$1=="160000" {print $4}' || true)
    [ -z "$direct" ] && continue

    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if [ -z "${direct_seen[$p]+x}" ]; then
        direct_seen[$p]=1
        if [ -z "$direct_unique" ]; then
          direct_unique="$p"
        else
          direct_unique="$direct_unique
$p"
        fi
      fi
    done < <(echo "$direct")
  done < <(echo "$branches_here")

  [ -z "$direct_unique" ] && continue

  # Init each submodule path once and enqueue it for deeper scanning
  while IFS= read -r subp; do
    [ -z "$subp" ] && continue

    key="$local_root|$subp"
    br_to_use="${FIRST_BRANCH_FOR_SUB[$key]:-}"

    ensure_submodule_initialized_via_branch "$local_root" "$subp" "$br_to_use" || true

    if [ -e "$local_root/$subp/.git" ] && is_git_repo_dir "$local_root/$subp"; then
      if [ -z "$local_prefix" ]; then
        new_prefix="$subp"
      else
        new_prefix="$local_prefix/$subp"
      fi
      enqueue_repo "$local_root/$subp" "$new_prefix"
    fi
  done < <(echo "$direct_unique")
done

# Gather all discovered submodule repo paths relative to super root
ALL_PATHS=$(printf "%s\n" "${!SEEN_SUB_REPO_PATHS[@]}" | sort || true)

if [ -z "$ALL_PATHS" ]; then
  print_warning "No submodule repos found across all branches (including nested)"
  SUBMODULE_COUNT=0
else
  SUBMODULE_COUNT=$(echo "$ALL_PATHS" | wc -l | tr -d ' ')
  print_success "Discovered $SUBMODULE_COUNT submodule repo path(s) (including nested)"
fi

##############################################################################
# STEP 3: BUNDLE ALL DISCOVERED SUBMODULE REPOS
##############################################################################

print_header "Step 3: Bundling Submodule Repos (All Levels)"

if [ -z "$ALL_PATHS" ]; then
  print_info "No submodule repos to bundle"
else
  log_message "================================================================="
  log_message "SUBMODULE REPOS TO BUNDLE ($SUBMODULE_COUNT total - including nested)"
  log_message "================================================================="

  idx=0
  ok=0

  while IFS= read -r fullpath; do
    [ -z "$fullpath" ] && continue
    idx=$((idx+1))

    repo_dir=$(dirname "$fullpath")
    repo_name=$(basename "$fullpath")

    if [ "$repo_dir" != "." ]; then
      mkdir -p "${EXPORT_FOLDER}/${repo_dir}"
    fi

    out_bundle="${repo_name}.bundle"
    if [ "$repo_dir" != "." ]; then
      out_path="${EXPORT_FOLDER}/${repo_dir}/${out_bundle}"
    else
      out_path="${EXPORT_FOLDER}/${out_bundle}"
    fi

    print_info "[$idx/$SUBMODULE_COUNT] Bundling: $fullpath"

    if [ ! -e "$REPO_PATH/$fullpath/.git" ] || ! is_git_repo_dir "$REPO_PATH/$fullpath"; then
      print_warning "  Not initialized / missing on disk: $fullpath (skipping)"
      {
        echo ""
        echo "Submodule Repo #$idx: $fullpath"
        echo "Status: NOT INITIALIZED / MISSING (skipped)"
        echo ""
      } >> "$LOG_FILE"
      continue
    fi

    cd "$REPO_PATH/$fullpath"
    git config --local protocol.file.allow always

    bundle_repo_to_path "$fullpath" "$out_path"
    checkout_default_branch "$fullpath" >/dev/null 2>&1 || true

    sub_branches=$(count_local_heads)
    sub_tags=$(git tag 2>/dev/null | wc -l | tr -d ' ')
    sub_commits=$(git rev-list --all --count 2>/dev/null || echo 0)

    if git bundle verify "$out_path" >/dev/null 2>&1; then
      print_success "  Bundled (branches: $sub_branches, tags: $sub_tags, commits: $sub_commits)"
      verify_status="VERIFIED"
      ok=$((ok+1))
    else
      print_error "  Verification failed"
      verify_status="FAILED"
    fi

    sha=$(sha256sum "$out_path" | awk '{print $1}')
    size=$(du -h "$out_path" | awk '{print $1}')
    url=$(git config --get remote.origin.url 2>/dev/null || echo "N/A")

    {
      echo ""
      echo "Submodule Repo #$idx: $fullpath"
      echo "-----------------------------------------------------------------"
      echo "Bundle File: $out_bundle"
      echo "Verification: $verify_status"
      echo "SHA256: $sha"
      echo "File Size: $size"
      echo "Branches: $sub_branches"
      echo "Tags: $sub_tags"
      echo "Total Commits: $sub_commits"
      echo "Remote URL: $url"
      echo "Path in Export: ./${repo_dir}/${out_bundle}"
      echo ""
    } >> "$LOG_FILE"

    cd "$REPO_PATH"
  done < <(echo "$ALL_PATHS")

  print_success "Bundled $ok/$SUBMODULE_COUNT submodule repo path(s)"
fi

##############################################################################
# STEP 4: METADATA
##############################################################################

print_header "Step 4: Creating Metadata File"

METADATA_FILE="${EXPORT_FOLDER}/metadata.txt"

{
  echo "================================================================="
  echo "Git Bundle Metadata"
  echo "================================================================="
  echo "Export Timestamp: $TIMESTAMP"
  echo "Ran by: $(whoami)"
  echo "Source Path: $REPO_PATH"
  echo "Remote Address: $REMOTE_GIT_ADDRESS"
  echo "Super Repository: $REPO_NAME"
  echo "Submodule Repos Bundled: ${SUBMODULE_COUNT:-0}"
  echo "================================================================="
  echo ""
  echo "FOLDER STRUCTURE:"
  echo "-----------------------------------------------------------------"
} > "$METADATA_FILE"

cd "$EXPORT_FOLDER"
find . -name "*.bundle" -type f | sort >> "$METADATA_FILE"
cd "$SCRIPT_DIR"

{
  echo ""
  echo "================================================================="
  echo "IMPORT INSTRUCTIONS:"
  echo "================================================================="
  echo "1. Transfer this entire folder to the destination network"
  echo "2. Run export_all.sh in the same directory as this folder"
  echo "3. The script will recreate the repository structure"
  echo ""
  echo "Note: The corresponding export folder will be named:"
  echo "      ${TIMESTAMP}_export"
  echo "================================================================="
} >> "$METADATA_FILE"

print_success "Metadata file created: $METADATA_FILE"

##############################################################################
# FINAL SUMMARY
##############################################################################

print_header "Bundling Complete!"

SCRIPT_END_TIME=$(date +%s)
ELAPSED=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

TOTAL_SIZE=$(du -sh "$EXPORT_FOLDER" | awk '{print $1}')

print_success "Export folder: $(basename "$EXPORT_FOLDER")"
print_success "Total size: $TOTAL_SIZE"
print_success "Super repository: 1 bundle created"
print_success "Submodule repos bundled: ${SUBMODULE_COUNT:-0}"
print_success "Time taken: ${MINS}m ${SECS}s"

log_message "================================================================="
log_message "SUMMARY"
log_message "================================================================="
log_message "Total Export Size: $TOTAL_SIZE"
log_message "Super Repository Bundles: 1"
log_message "Submodule Repo Bundles: ${SUBMODULE_COUNT:-0}"
log_message "Time Taken: ${MINS}m ${SECS}s"
log_message "Script Completed: $(date +%Y%m%d_%H%M)"
log_message "================================================================="

print_success "All done!"