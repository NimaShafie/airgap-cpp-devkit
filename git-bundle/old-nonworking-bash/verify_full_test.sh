#!/bin/bash

##############################################################################
# verify_full_test.sh
#
# Author: Nima Shafie
#
# Verifies that all branches, tags, and commits were transferred correctly
# from the full-test-repo to the exported version
#
# Fixes:
#  - Use git-based repo detection (works when .git is a FILE, e.g. submodules)
#  - Ignore a bogus local branch named "origin" if it exists (safety)
##############################################################################

set -e

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}OK $1${NC}"
}

print_error() {
    echo -e "${RED}ERR $1${NC}"
}

print_info() {
    echo -e "${YELLOW}INFO $1${NC}"
}

# Sanity checks (fail early with clear message)
if ! command -v git >/dev/null 2>&1; then
    print_error "git not found in PATH"
    print_info "Run this script from Git Bash (MINGW64) where git is available"
    exit 1
fi

if ! command -v wc >/dev/null 2>&1; then
    print_error "wc not found in PATH"
    print_info "Run this script from Git Bash (MINGW64) where coreutils are available"
    exit 1
fi

# Find the most recent export
EXPORT_DIR="$(find "${SCRIPT_DIR}" -maxdepth 2 -type d -name "full-test-repo" 2>/dev/null | grep "_export" | sort -r | head -n 1 || true)"

if [ -z "$EXPORT_DIR" ]; then
    print_error "Could not find exported full-test-repo"
    print_info "Make sure you've run export_all.sh first"
    exit 1
fi

print_header "Verifying Full Test Repository Transfer"
echo ""
print_info "Original: ${SCRIPT_DIR}/test/full-test-repo"
print_info "Exported: $EXPORT_DIR"
echo ""

ISSUES=0

# Determine if a path is a git repo (works for normal repos AND submodules where .git is a file)
is_git_repo() {
    local P="$1"
    git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Count local branches, excluding a bogus local branch named "origin" if present
count_local_branches_sanitized() {
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | grep -v '^origin$' | wc -l | tr -d ' '
}

# Function to check repo
check_repo() {
    local NAME="$1"
    local REPO_PATH="$2"
    local EXPECTED_BRANCHES="$3"
    local EXPECTED_TAGS="$4"

    echo ""
    print_header "Checking: $NAME"

    if ! is_git_repo "$REPO_PATH"; then
        print_error "Not a git repository: $REPO_PATH"
        ISSUES=$((ISSUES + 1))
        return
    fi

    cd "$REPO_PATH"

    # Branch count (exclude any stray local branch named "origin")
    local BRANCH_COUNT
    BRANCH_COUNT="$(count_local_branches_sanitized)"
    echo "Branches: $BRANCH_COUNT (expected: $EXPECTED_BRANCHES)"

    # Show branches, but hide "origin" if it exists
    git branch | grep -vE '^[* ] origin$' | sed 's/^/  /' || true

    if git show-ref --verify --quiet refs/heads/origin; then
        echo "  (note: local branch 'origin' exists but is ignored for verification)"
    fi

    if [ "$BRANCH_COUNT" -eq "$EXPECTED_BRANCHES" ]; then
        print_success "Branch count correct"
    else
        print_error "Branch count mismatch (expected $EXPECTED_BRANCHES, got $BRANCH_COUNT)"
        ISSUES=$((ISSUES + 1))
    fi

    # Tag count
    local TAG_COUNT
    TAG_COUNT="$(git tag | wc -l | tr -d ' ')"
    echo ""
    echo "Tags: $TAG_COUNT (expected: $EXPECTED_TAGS)"
    git tag | sed 's/^/  /' || true

    if [ "$TAG_COUNT" -eq "$EXPECTED_TAGS" ]; then
        print_success "Tag count correct"
    else
        print_error "Tag count mismatch (expected $EXPECTED_TAGS, got $TAG_COUNT)"
        ISSUES=$((ISSUES + 1))
    fi

    # Remotes (should be empty for air-gapped)
    local REMOTE_COUNT
    REMOTE_COUNT="$(git remote | wc -l | tr -d ' ')"
    echo ""
    echo "Remotes: $REMOTE_COUNT (expected: 0 for air-gapped)"

    if [ "$REMOTE_COUNT" -eq 0 ]; then
        print_success "No remotes (air-gapped setup correct)"
    else
        print_error "Found remotes (should be none for air-gapped)"
        git remote -v || true
        ISSUES=$((ISSUES + 1))
    fi
}

# Check all repositories
check_repo "Super Repository" "$EXPORT_DIR" 4 4
check_repo "user-service (ROOT LEVEL)" "$EXPORT_DIR/services/user-service" 4 3
check_repo "payment-service (ROOT LEVEL)" "$EXPORT_DIR/services/payment-service" 4 3
check_repo "database-lib (NESTED L2)" "$EXPORT_DIR/services/user-service/lib/database" 3 2
check_repo "cache-lib (NESTED L2)" "$EXPORT_DIR/services/payment-service/lib/cache" 3 2
check_repo "logger-lib (NESTED L3)" "$EXPORT_DIR/services/user-service/lib/database/utils/logger" 3 2

# Final summary
echo ""
print_header "Verification Summary"
echo ""

if [ "$ISSUES" -eq 0 ]; then
    print_success "ALL CHECKS PASSED"
    echo ""
    echo "OK All branches transferred correctly"
    echo "OK All tags transferred correctly"
    echo "OK All repositories are air-gapped (no remotes)"
else
    print_error "FOUND $ISSUES ISSUE(S)"
    echo ""
    print_info "Review the output above to see what failed"
    echo ""
    echo "Common issues:"
    echo "  - Missing submodules in export"
    echo "    -> bundle_all.sh skipped bundling because submodules were not initialized"
    echo "  - Root-level repos only have main"
    echo "    -> bundling did not include all branches or export didn't recreate refs"
fi

echo ""