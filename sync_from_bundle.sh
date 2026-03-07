#!/bin/bash

##############################################################################
# sync_from_bundle.sh
#
# Author: Nima Shafie
# 
# Purpose: Update an existing Git repository with bundles from a newer source,
#          treating the bundle as the source of truth and overwriting any
#          local changes or conflicts.
#
# Usage: ./sync_from_bundle.sh
#
# Requirements: git
#
# IMPORTANT: This script will OVERWRITE local changes! The bundle is treated
#            as the authoritative source. Any uncommitted changes or commits
#            not in the bundle will be LOST.
##############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

##############################################################################
# USER CONFIGURATION - EDIT THESE VARIABLES
##############################################################################

# Path to the EXISTING repository you want to update
EXISTING_REPO_PATH=""

# Path to the import folder (the folder created by bundle_all.sh)
# Leave empty to auto-detect (finds the most recent *_import folder by timestamp in name)
# Example: "20260126_2140_import" or leave "" for auto-detect
IMPORT_FOLDER=""

# Default branch to force checkout (typically 'main' or 'master')
DEFAULT_BRANCH="main"

# Backup option: Create a backup of the existing repo before syncing?
CREATE_BACKUP=true

##############################################################################
# SCRIPT CONFIGURATION - Generally no need to edit below
##############################################################################

# Store the original working directory (where the script is run from)
SCRIPT_DIR="$(pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track script start time
SCRIPT_START_TIME=$(date +%s)

##############################################################################
# FUNCTIONS
##############################################################################

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERR]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

##############################################################################
# VALIDATION
##############################################################################

print_header "Git Sync Script - Update Repository from Bundles"

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install git and try again."
    exit 1
fi

# Validate or auto-detect EXISTING_REPO_PATH
if [ -z "$EXISTING_REPO_PATH" ]; then
    print_error "EXISTING_REPO_PATH is not set"
    print_info "Please edit the EXISTING_REPO_PATH variable in this script."
    print_info "Example: REPO_PATH=\"\$HOME/Desktop/my-repository\""
    exit 1
fi

# Make path absolute if relative
if [[ "$EXISTING_REPO_PATH" != /* ]]; then
    EXISTING_REPO_PATH="${SCRIPT_DIR}/${EXISTING_REPO_PATH}"
fi

if [ ! -d "$EXISTING_REPO_PATH" ]; then
    print_error "Repository path does not exist: $EXISTING_REPO_PATH"
    exit 1
fi

if [ ! -d "$EXISTING_REPO_PATH/.git" ]; then
    print_error "Path is not a Git repository: $EXISTING_REPO_PATH"
    exit 1
fi

print_success "Found existing repository: $EXISTING_REPO_PATH"

# Auto-detect or validate import folder
if [ -z "$IMPORT_FOLDER" ]; then
    print_info "Auto-detecting import folder..."
    
    IMPORT_FOLDER=$(find "$SCRIPT_DIR" -maxdepth 1 -type d -name "*_import" | sort -r | head -n 1)
    
    if [ -z "$IMPORT_FOLDER" ]; then
        print_error "No *_import folder found in current directory."
        print_info "Please either:"
        echo "  1. Place this script in the same directory as the import folder, or"
        echo "  2. Edit the IMPORT_FOLDER variable in this script"
        exit 1
    fi
    
    print_success "Found import folder: $(basename $IMPORT_FOLDER)"
else
    if [ ! -d "$IMPORT_FOLDER" ]; then
        print_error "Import folder does not exist: $IMPORT_FOLDER"
        exit 1
    fi
fi

# Make IMPORT_FOLDER absolute
if [[ "$IMPORT_FOLDER" != /* ]]; then
    IMPORT_FOLDER="${SCRIPT_DIR}/${IMPORT_FOLDER}"
fi

##############################################################################
# CREATE BACKUP
##############################################################################

if [ "$CREATE_BACKUP" = true ]; then
    print_header "Step 1: Creating Backup"
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    REPO_BASENAME=$(basename "$EXISTING_REPO_PATH")
    BACKUP_PATH="${SCRIPT_DIR}/${REPO_BASENAME}_backup_${TIMESTAMP}"
    
    print_info "Creating backup at: $BACKUP_PATH"
    print_warning "This may take a moment for large repositories..."
    
    cp -r "$EXISTING_REPO_PATH" "$BACKUP_PATH"
    
    print_success "Backup created: $(basename $BACKUP_PATH)"
    print_info "Location: git-bundles/$(basename $BACKUP_PATH)"
else
    print_header "Step 1: Backup"
    print_warning "Backup disabled - proceeding without backup"
fi

##############################################################################
# FIND SUPER REPOSITORY BUNDLE
##############################################################################

print_header "Step 2: Locating Super Repository Bundle"

cd "$IMPORT_FOLDER"

# Get all bundles in the root directory
ROOT_BUNDLES=$(find . -maxdepth 1 -name "*.bundle" -type f)

if [ -z "$ROOT_BUNDLES" ]; then
    print_error "No bundles found in $IMPORT_FOLDER"
    exit 1
fi

# Find the super repo bundle (check metadata or use largest)
BUNDLE_COUNT=$(echo "$ROOT_BUNDLES" | wc -l)

if [ "$BUNDLE_COUNT" -eq 1 ]; then
    SUPER_BUNDLE="$ROOT_BUNDLES"
else
    if [ -f "metadata.txt" ]; then
        SUPER_REPO_NAME=$(grep "Super Repository:" metadata.txt | awk '{print $3}')
        if [ -n "$SUPER_REPO_NAME" ]; then
            SUPER_BUNDLE="./${SUPER_REPO_NAME}.bundle"
        else
            SUPER_BUNDLE=$(ls -S *.bundle 2>/dev/null | head -n 1)
            SUPER_BUNDLE="./$SUPER_BUNDLE"
        fi
    else
        SUPER_BUNDLE=$(ls -S *.bundle 2>/dev/null | head -n 1)
        SUPER_BUNDLE="./$SUPER_BUNDLE"
    fi
fi

cd "$SCRIPT_DIR"

SUPER_BUNDLE="${IMPORT_FOLDER}/${SUPER_BUNDLE#./}"

if [ ! -f "$SUPER_BUNDLE" ]; then
    print_error "Could not locate super repository bundle"
    exit 1
fi

print_success "Found super repository bundle: $(basename $SUPER_BUNDLE)"

##############################################################################
# SYNC SUPER REPOSITORY
##############################################################################

print_header "Step 3: Syncing Super Repository"

cd "$EXISTING_REPO_PATH"

print_info "Current repository state:"
git log --oneline -3 2>/dev/null || echo "  (no commits)"

# Add the bundle as a temporary remote
print_info "Fetching from bundle..."
git fetch "$SUPER_BUNDLE" 'refs/heads/*:refs/remotes/bundle/*' --force 2>/dev/null

# Determine which branch to sync (priority: main -> develop -> master -> first available)
if git show-ref --verify --quiet "refs/remotes/bundle/main"; then
    SYNC_BRANCH="main"
elif git show-ref --verify --quiet "refs/remotes/bundle/develop"; then
    SYNC_BRANCH="develop"
elif git show-ref --verify --quiet "refs/remotes/bundle/master"; then
    SYNC_BRANCH="master"
else
    # Get the first available branch from the bundle
    SYNC_BRANCH=$(git branch -r | grep 'bundle/' | head -n 1 | sed 's|.*bundle/||')
fi

print_info "Syncing to branch: $SYNC_BRANCH"

# Save any uncommitted changes (will be discarded)
if ! git diff-index --quiet HEAD 2>/dev/null; then
    print_warning "Uncommitted changes detected - they will be discarded"
fi

# Force reset to the bundle's branch (treating bundle as source of truth)
print_info "Resetting to bundle state (bundle is source of truth)..."
git reset --hard "bundle/$SYNC_BRANCH"

# Checkout the branch
if git show-ref --verify --quiet "refs/heads/$SYNC_BRANCH"; then
    git checkout "$SYNC_BRANCH"
else
    git checkout -b "$SYNC_BRANCH"
fi

# Remove the temporary remote references
git branch -r | grep 'bundle/' | xargs -r git branch -rd 2>/dev/null || true

print_success "Super repository synced successfully"
print_info "New state:"
git log --oneline -3

cd "$SCRIPT_DIR"

##############################################################################
# DISCOVER AND SYNC SUBMODULES
##############################################################################

print_header "Step 4: Discovering Submodule Bundles"

# Find all submodule bundles
SUBMODULE_BUNDLES=$(find "$IMPORT_FOLDER" -mindepth 2 -name "*.bundle" -type f | sort || true)

# Sort by path length (shallowest first)
SUBMODULE_BUNDLES=$(echo "$SUBMODULE_BUNDLES" | awk '{ print length, $0 }' | sort -n | cut -d" " -f2-)

if [ -z "$SUBMODULE_BUNDLES" ]; then
    print_warning "No submodule bundles found"
    SUBMODULE_COUNT=0
else
    SUBMODULE_COUNT=$(echo "$SUBMODULE_BUNDLES" | wc -l)
    print_success "Found $SUBMODULE_COUNT submodule bundle(s)"
fi

##############################################################################
# SYNC SUBMODULES
##############################################################################

print_header "Step 5: Syncing Submodules"

cd "$EXISTING_REPO_PATH"

if [ "$SUBMODULE_COUNT" -eq 0 ]; then
    print_info "No submodule bundles to sync"
else
    SUBMODULE_NUM=0
    while IFS= read -r BUNDLE_FULL_PATH; do
        SUBMODULE_NUM=$((SUBMODULE_NUM + 1))
        
        # Get the relative path from import folder
        BUNDLE_REL_PATH="${BUNDLE_FULL_PATH#$IMPORT_FOLDER/}"
        BUNDLE_REL_DIR=$(dirname "$BUNDLE_REL_PATH")
        BUNDLE_NAME=$(basename "$BUNDLE_REL_PATH" .bundle)
        
        # The submodule path
        if [ "$BUNDLE_REL_DIR" = "." ]; then
            SUBMODULE_PATH="$BUNDLE_NAME"
        else
            SUBMODULE_PATH="${BUNDLE_REL_DIR}/${BUNDLE_NAME}"
        fi
        
        print_info "[$SUBMODULE_NUM/$SUBMODULE_COUNT] Syncing: $SUBMODULE_PATH"
        
        # Check if submodule directory exists
        if [ ! -d "$SUBMODULE_PATH" ]; then
            print_info "  Cloning new submodule..."
            
            # Create parent directory if needed
            SUBMODULE_PARENT=$(dirname "$SUBMODULE_PATH")
            if [ "$SUBMODULE_PARENT" != "." ] && [ ! -d "$SUBMODULE_PARENT" ]; then
                mkdir -p "$SUBMODULE_PARENT"
            fi
            
            git clone --quiet "$BUNDLE_FULL_PATH" "$SUBMODULE_PATH" 2>&1 | grep -v "^Receiving\|^Resolving" || true
            print_success "  ✓ Cloned"
        elif [ ! -d "$SUBMODULE_PATH/.git" ]; then
            print_warning "  Directory exists but is not a git repository, skipping"
            continue
        else
            print_info "  Updating..."
            
            cd "$SUBMODULE_PATH"
            
            # Fetch from bundle
            git fetch "$BUNDLE_FULL_PATH" 'refs/heads/*:refs/remotes/bundle/*' --force 2>/dev/null
            
            # Determine branch to sync (priority: main -> develop -> master -> first available)
            if git show-ref --verify --quiet "refs/remotes/bundle/main"; then
                SUB_SYNC_BRANCH="main"
            elif git show-ref --verify --quiet "refs/remotes/bundle/develop"; then
                SUB_SYNC_BRANCH="develop"
            elif git show-ref --verify --quiet "refs/remotes/bundle/master"; then
                SUB_SYNC_BRANCH="master"
            else
                SUB_SYNC_BRANCH=$(git branch -r | grep 'bundle/' | head -n 1 | sed 's|.*bundle/||')
            fi
            
            # Discard any local changes and force reset
            git reset --hard "bundle/$SUB_SYNC_BRANCH" &>/dev/null
            
            # Checkout branch
            if git show-ref --verify --quiet "refs/heads/$SUB_SYNC_BRANCH"; then
                git checkout "$SUB_SYNC_BRANCH" &>/dev/null
            else
                git checkout -b "$SUB_SYNC_BRANCH" &>/dev/null
            fi
            
            # Clean up bundle remote refs
            git branch -r | grep 'bundle/' | xargs -r git branch -rd 2>/dev/null || true
            
            print_success "  ✓ Updated"
            
            cd "$EXISTING_REPO_PATH"
        fi
        
        # Remove remote (air-gapped)
        if [ -d "$SUBMODULE_PATH/.git" ]; then
            cd "$SUBMODULE_PATH"
            git remote remove origin 2>/dev/null || true
            cd "$EXISTING_REPO_PATH"
        fi
        
    done < <(echo "$SUBMODULE_BUNDLES")
    
    print_success "All submodules synced"
fi

cd "$SCRIPT_DIR"

##############################################################################
# FINAL SUMMARY
##############################################################################

print_header "Sync Complete!"

# Calculate elapsed time
SCRIPT_END_TIME=$(date +%s)
ELAPSED_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
MINUTES=$((ELAPSED_TIME / 60))
SECONDS=$((ELAPSED_TIME % 60))

echo ""
print_success "Repository: $EXISTING_REPO_PATH"
print_success "Super repository: Synced to bundle state"
print_success "Submodules: $SUBMODULE_COUNT processed"
print_success "Time taken: ${MINUTES}m ${SECONDS}s"
echo ""

if [ "$CREATE_BACKUP" = true ]; then
    print_info "Backup location (in git-bundles folder):"
    echo "  $(basename $BACKUP_PATH)"
    echo ""
fi

print_warning "IMPORTANT NOTES:"
echo "  1. All local changes have been OVERWRITTEN by the bundle"
echo "  2. The bundle is now the source of truth for this repository"
echo "  3. Any commits not in the bundle have been LOST"
if [ "$CREATE_BACKUP" = true ]; then
    echo "  4. Your backup is in the git-bundles folder if you need to recover"
fi
echo ""

print_info "Verification commands:"
echo "  cd $EXISTING_REPO_PATH"
echo "  git log --oneline -10"
echo "  git status"
echo "  git submodule status --recursive"
echo ""

print_success "All done!"