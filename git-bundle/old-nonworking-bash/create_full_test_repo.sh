#!/bin/bash

##############################################################################
# create_full_test_repo.sh
#
# Author: Nima Shafie
#
# Creates a comprehensive test repository with:
# - Multiple branches and tags at ALL levels
# - Root-level submodules
# - Nested submodules at various depths
# - Branch-specific submodule differences (root + nested)
#
# Windows/MSYS fix:
# - Always remove submodules using a safe sequence:
#   deinit + git rm + .gitmodules cleanup + rm -rf
# - Final step does clean submodule init on ALL branches to avoid stale dirs.
##############################################################################

set -e

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEST_DIR="${SCRIPT_DIR}/test"

echo "============================================================"
echo "Creating Comprehensive Test Repository"
echo "============================================================"
echo ""
echo "This will create:"
echo "  - Super repository with multiple branches/tags"
echo "  - Root-level submodule differences across branches"
echo "  - Nested and deeply nested submodules"
echo ""
echo "Branch-specific submodule differences:"
echo "  Super repo:"
echo "    main    -> services/user-service, services/payment-service"
echo "    develop -> services/user-service, services/notification-service"
echo ""
echo "  user-service (nested):"
echo "    main    -> lib/database (contains utils/logger)"
echo "    develop -> lib/database + lib/feature-flags"
echo ""
echo "Test location: ${TEST_DIR}"
echo ""

# Clean up if exists
rm -rf "${TEST_DIR}" 2>/dev/null || true
mkdir -p "${TEST_DIR}"
cd "${TEST_DIR}"

##############################################################################
# HELPERS
##############################################################################

# Make Git behave more predictably on Windows
git_windows_sane_defaults() {
    git config --local protocol.file.allow always >/dev/null 2>&1 || true
    git config --local core.longpaths true >/dev/null 2>&1 || true
    # Do NOT force autocrlf here; leave user's environment intact.
}

# Properly remove a submodule from the current repo at path $1.
# This prevents "unable to rmdir ... Directory not empty" issues on Windows.
remove_submodule_safely() {
    local SUB_PATH="$1"

    echo "  - Removing submodule safely: $SUB_PATH"

    # Best effort: deinit clears .git/config entries and submodule state
    git submodule deinit -f -- "$SUB_PATH" >/dev/null 2>&1 || true

    # Remove from index (gitlink) - this is the important part
    git rm -f --cached -- "$SUB_PATH" >/dev/null 2>&1 || true
    git rm -f -- "$SUB_PATH" >/dev/null 2>&1 || true

    # Remove the section from .gitmodules if it exists
    if [ -f .gitmodules ]; then
        # Find the submodule name associated with this path
        # Parse: [submodule "NAME"] then path = SUB_PATH
        local NAME
        NAME=$(awk -v p="$SUB_PATH" '
            $0 ~ /^\[submodule "/ { gsub(/^\[submodule "|"\]$/, "", $0); name=$0 }
            $0 ~ /^[[:space:]]*path[[:space:]]*=[[:space:]]*/ {
                path=$0
                sub(/^[[:space:]]*path[[:space:]]*=[[:space:]]*/, "", path)
                if (path==p) { print name; exit }
            }
        ' .gitmodules 2>/dev/null || true)

        if [ -n "$NAME" ]; then
            git config -f .gitmodules --remove-section "submodule.$NAME" >/dev/null 2>&1 || true
        fi

        # If .gitmodules is now empty or only whitespace, remove it
        if [ -f .gitmodules ]; then
            if ! grep -q '[^[:space:]]' .gitmodules; then
                rm -f .gitmodules >/dev/null 2>&1 || true
            fi
        fi
    fi

    # Kill leftover working dir (Windows often leaves it behind)
    rm -rf "$SUB_PATH" >/dev/null 2>&1 || true

    # Also clean possible leftover submodule metadata
    rm -rf ".git/modules/$SUB_PATH" >/dev/null 2>&1 || true

    # Stage .gitmodules changes if present
    if [ -f .gitmodules ]; then
        git add .gitmodules >/dev/null 2>&1 || true
    fi
}

##############################################################################
# 1. CREATE BASE REPOSITORIES WITH BRANCHES & TAGS
##############################################################################

echo ""
echo "============================================================"
echo "Step 1: Creating Base Repositories"
echo "============================================================"

# ----- BASE 1: user-service (root-level submodule) -----
echo ""
echo "[1/7] Creating user-service (root-level submodule)..."
mkdir full-test-base-user-service
cd full-test-base-user-service
git init
git_windows_sane_defaults

cat > user.py << 'EOF'
class User:
    version = "1.0.0"
    def login(self): return "logged in"
EOF
git add . && git commit -m "Initial user service v1.0"
git tag v1.0.0

git checkout -b develop
cat > user.py << 'EOF'
class User:
    version = "1.5.0"
    def login(self): return "logged in"
    def logout(self): return "logged out"
EOF
git add . && git commit -m "Add logout feature"
git tag v1.5.0

git checkout -b feature/oauth
cat > oauth.py << 'EOF'
def oauth_login(): return "oauth"
EOF
git add . && git commit -m "Add OAuth support"

git checkout develop
git checkout -b release/2.0
cat > user.py << 'EOF'
class User:
    version = "2.0.0"
    def login(self): return "logged in v2"
    def logout(self): return "logged out"
EOF
git add . && git commit -m "Release v2.0"
git tag v2.0.0

git checkout main
USER_SERVICE_PATH=$(pwd)
echo "OK user-service: 4 branches (main, develop, feature/oauth, release/2.0), 3 tags"

# ----- BASE 2: payment-service (root-level submodule for main) -----
cd "${TEST_DIR}"
echo ""
echo "[2/7] Creating payment-service (root-level submodule for main)..."
mkdir full-test-base-payment-service
cd full-test-base-payment-service
git init
git_windows_sane_defaults

cat > payment.py << 'EOF'
class Payment:
    version = "1.0.0"
    def process(self): return "processed"
EOF
git add . && git commit -m "Initial payment service v1.0"
git tag v1.0.0

git checkout -b develop
cat > payment.py << 'EOF'
class Payment:
    version = "1.2.0"
    def process(self): return "processed"
    def refund(self): return "refunded"
EOF
git add . && git commit -m "Add refund feature"
git tag v1.2.0

git checkout -b feature/stripe
cat > stripe.py << 'EOF'
def stripe_payment(): return "stripe"
EOF
git add . && git commit -m "Add Stripe integration"

git checkout -b hotfix/1.0.1 main
cat > payment.py << 'EOF'
class Payment:
    version = "1.0.1"
    def process(self): return "processed (fixed)"
EOF
git add . && git commit -m "Hotfix v1.0.1"
git tag v1.0.1

git checkout main
PAYMENT_SERVICE_PATH=$(pwd)
echo "OK payment-service: 4 branches (main, develop, feature/stripe, hotfix/1.0.1), 3 tags"

# ----- BASE 3: database-lib (nested in user-service) -----
cd "${TEST_DIR}"
echo ""
echo "[3/7] Creating database-lib (nested level 2)..."
mkdir full-test-base-database-lib
cd full-test-base-database-lib
git init
git_windows_sane_defaults

cat > db.py << 'EOF'
class Database:
    version = "1.0"
    def connect(self): return "connected"
EOF
git add . && git commit -m "Initial database library"
git tag v1.0

git checkout -b develop
cat > db.py << 'EOF'
class Database:
    version = "2.0"
    def connect(self): return "connected"
    def disconnect(self): return "disconnected"
EOF
git add . && git commit -m "Add disconnect"
git tag v2.0

git checkout -b feature/pool
cat > pool.py << 'EOF'
class ConnectionPool: pass
EOF
git add . && git commit -m "Add connection pool"

git checkout main
DATABASE_LIB_PATH=$(pwd)
echo "OK database-lib: 3 branches (main, develop, feature/pool), 2 tags"

# ----- BASE 4: cache-lib (nested in payment-service) -----
cd "${TEST_DIR}"
echo ""
echo "[4/7] Creating cache-lib (nested level 2)..."
mkdir full-test-base-cache-lib
cd full-test-base-cache-lib
git init
git_windows_sane_defaults

cat > cache.py << 'EOF'
class Cache:
    version = "1.0"
    def set(self, k, v): pass
    def get(self, k): pass
EOF
git add . && git commit -m "Initial cache library"
git tag v1.0

git checkout -b develop
cat > cache.py << 'EOF'
class Cache:
    version = "1.5"
    def set(self, k, v): pass
    def get(self, k): pass
    def delete(self, k): pass
EOF
git add . && git commit -m "Add delete method"
git tag v1.5

git checkout -b feature/redis
cat > redis.py << 'EOF'
def redis_cache(): return "redis"
EOF
git add . && git commit -m "Add Redis backend"

git checkout main
CACHE_LIB_PATH=$(pwd)
echo "OK cache-lib: 3 branches (main, develop, feature/redis), 2 tags"

# ----- BASE 5: logger-lib (deeply nested in database-lib) -----
cd "${TEST_DIR}"
echo ""
echo "[5/7] Creating logger-lib (nested level 3)..."
mkdir full-test-base-logger-lib
cd full-test-base-logger-lib
git init
git_windows_sane_defaults

cat > logger.py << 'EOF'
class Logger:
    def log(self, msg): print(msg)
EOF
git add . && git commit -m "Initial logger"
git tag v1.0

git checkout -b develop
cat > logger.py << 'EOF'
class Logger:
    def log(self, msg): print(msg)
    def error(self, msg): print("ERROR:", msg)
EOF
git add . && git commit -m "Add error logging"
git tag v2.0

git checkout -b feature/json
cat > logger.py << 'EOF'
import json
class Logger:
    def log(self, msg): print(json.dumps(msg))
    def error(self, msg): print("ERROR:", msg)
EOF
git add . && git commit -m "Add JSON logging"

git checkout main
LOGGER_LIB_PATH=$(pwd)
echo "OK logger-lib: 3 branches (main, develop, feature/json), 2 tags"

# ----- BASE 6: notification-service (root-level submodule for develop) -----
cd "${TEST_DIR}"
echo ""
echo "[6/7] Creating notification-service (root-level submodule for develop)..."
mkdir full-test-base-notification-service
cd full-test-base-notification-service
git init
git_windows_sane_defaults

cat > notify.py << 'EOF'
class Notify:
    version = "1.0.0"
    def send(self): return "sent"
EOF
git add . && git commit -m "Initial notification service v1.0"
git tag v1.0.0

git checkout -b develop
cat > notify.py << 'EOF'
class Notify:
    version = "1.2.0"
    def send(self): return "sent"
    def schedule(self): return "scheduled"
EOF
git add . && git commit -m "Add schedule support"
git tag v1.2.0

git checkout -b feature/sms
cat > sms.py << 'EOF'
def sms_send(): return "sms"
EOF
git add . && git commit -m "Add SMS support"

git checkout main
NOTIFICATION_SERVICE_PATH=$(pwd)
echo "OK notification-service: 3 branches (main, develop, feature/sms), 2 tags"

# ----- BASE 7: feature-flags-lib (nested in user-service develop only) -----
cd "${TEST_DIR}"
echo ""
echo "[7/7] Creating feature-flags-lib (nested in user-service develop only)..."
mkdir full-test-base-feature-flags-lib
cd full-test-base-feature-flags-lib
git init
git_windows_sane_defaults

cat > flags.py << 'EOF'
class Flags:
    enabled = False
EOF
git add . && git commit -m "Initial feature flags lib"
git tag v1.0.0

git checkout -b develop
cat > flags.py << 'EOF'
class Flags:
    enabled = True
EOF
git add . && git commit -m "Enable flags by default in develop"
git tag v1.1.0

git checkout main
FEATURE_FLAGS_PATH=$(pwd)
echo "OK feature-flags-lib: 2 branches (main, develop), 2 tags"

##############################################################################
# 2. CREATE NESTED SUBMODULE STRUCTURE
##############################################################################

echo ""
echo "============================================================"
echo "Step 2: Creating Nested Submodule Structure"
echo "============================================================"

# Add logger-lib to database-lib (level 3 nesting)
cd "$DATABASE_LIB_PATH"
git checkout main >/dev/null 2>&1
git_windows_sane_defaults
mkdir -p utils
git -c protocol.file.allow=always submodule add "file://$LOGGER_LIB_PATH" utils/logger
git commit -m "Add logger as nested submodule"

# Merge into other branches
git checkout develop >/dev/null 2>&1
git merge main -m "Merge logger submodule"
git checkout feature/pool >/dev/null 2>&1
git merge develop -m "Merge logger submodule"
git checkout main >/dev/null 2>&1

echo "OK database-lib now contains logger-lib (level 3 nesting)"

# Add database-lib to user-service (level 2 nesting)
cd "$USER_SERVICE_PATH"
git checkout main >/dev/null 2>&1
git_windows_sane_defaults
mkdir -p lib
git -c protocol.file.allow=always submodule add "file://$DATABASE_LIB_PATH" lib/database
git commit -m "Add database-lib as nested submodule"

# Merge into other branches
git checkout develop >/dev/null 2>&1
git merge main -m "Merge database submodule"
git checkout feature/oauth >/dev/null 2>&1
git merge develop -m "Merge database submodule"
git checkout main >/dev/null 2>&1

echo "OK user-service now contains database-lib (which contains logger-lib)"

# Add feature-flags-lib to user-service develop ONLY
cd "$USER_SERVICE_PATH"
git checkout develop >/dev/null 2>&1
git_windows_sane_defaults
mkdir -p lib
git -c protocol.file.allow=always submodule add "file://$FEATURE_FLAGS_PATH" lib/feature-flags
git commit -m "Add feature-flags-lib as nested submodule (develop only)"
git checkout main >/dev/null 2>&1

echo "OK user-service develop now contains extra nested submodule: lib/feature-flags"

# Add cache-lib to payment-service (level 2 nesting)
cd "$PAYMENT_SERVICE_PATH"
git checkout main >/dev/null 2>&1
git_windows_sane_defaults
mkdir -p lib
git -c protocol.file.allow=always submodule add "file://$CACHE_LIB_PATH" lib/cache
git commit -m "Add cache-lib as nested submodule"

# Merge into other branches
git checkout develop >/dev/null 2>&1
git merge main -m "Merge cache submodule"
git checkout feature/stripe >/dev/null 2>&1
git merge develop -m "Merge cache submodule"
git checkout main >/dev/null 2>&1

echo "OK payment-service now contains cache-lib"

##############################################################################
# 3. CREATE SUPER REPOSITORY
##############################################################################

echo ""
echo "============================================================"
echo "Step 3: Creating Super Repository"
echo "============================================================"

cd "${TEST_DIR}"
mkdir full-test-repo
cd full-test-repo
git init
git_windows_sane_defaults

cat > README.md << 'EOF'
# Full Test Application
Version: 1.0.0
A comprehensive microservices application for testing git bundles.
EOF

cat > .gitignore << 'EOF'
*.pyc
__pycache__/
.env
EOF

git add . && git commit -m "Initial commit v1.0"
git tag v1.0.0

echo ""
echo "Adding root-level submodules on main..."

mkdir -p services

# Add user-service at root level
git -c protocol.file.allow=always submodule add "file://$USER_SERVICE_PATH" services/user-service
git commit -m "Add user-service (main)"

# Add payment-service at root level (main only)
git -c protocol.file.allow=always submodule add "file://$PAYMENT_SERVICE_PATH" services/payment-service
git commit -m "Add payment-service (main)"
git tag v1.5.0

echo ""
echo "Creating branches in super repository..."

# Create develop branch
git checkout -b develop

cat > README.md << 'EOF'
# Full Test Application
Version: 2.0.0-dev
A comprehensive microservices application for testing git bundles.
## Development Version
New features in development.
EOF
git add README.md && git commit -m "Update to v2.0-dev"
git tag v2.0.0-dev

echo ""
echo "Modifying root-level submodules on develop (branch-specific)..."
echo "  - Removing services/payment-service"
echo "  - Adding services/notification-service"

# IMPORTANT: Properly remove payment-service submodule to avoid Windows leftover dir warning
remove_submodule_safely "services/payment-service"
git commit -m "Remove payment-service on develop (branch-specific)" || true

# Add notification-service on develop
git -c protocol.file.allow=always submodule add "file://$NOTIFICATION_SERVICE_PATH" services/notification-service
git commit -m "Add notification-service on develop (branch-specific)"

# Create feature branch from develop
echo ""
echo "Creating feature branch..."
git checkout -b feature/api-gateway
cat > gateway.py << 'EOF'
class APIGateway:
    def route(self): return "routed"
EOF
git add gateway.py && git commit -m "Add API gateway"

# Create release branch from develop
echo ""
echo "Creating release branch..."
git checkout develop
git checkout -b release/2.0
cat > README.md << 'EOF'
# Full Test Application
Version: 2.0.0
A comprehensive microservices application for testing git bundles.
## Production Release
Ready for deployment.
EOF
git add README.md && git commit -m "Release v2.0"
git tag v2.0.0

git checkout main

SUPER_PATH=$(pwd)
echo "OK Super repository created with 4 branches, 4 tags"

##############################################################################
# FINAL STEP: Initialize submodules cleanly on ALL branches (Windows-safe)
##############################################################################

echo ""
echo "============================================================"
echo "Final Step: Initializing submodules on ALL branches"
echo "============================================================"

cd "$SUPER_PATH"

ALL_BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads | sort)
ORIG_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# List gitlink paths (submodules) for a branch from the tree
list_gitlinks_for_branch() {
    local BR="$1"
    git ls-tree -r --full-name "$BR" | awk '$1=="160000" {print $4}'
}

# Remove submodule working dirs that are NOT expected on this branch
cleanup_unexpected_submodule_dirs() {
    local BR="$1"
    local EXPECTED
    EXPECTED="$(list_gitlinks_for_branch "$BR" | sort)"

    local ON_DISK
    ON_DISK=$(find . -mindepth 2 -maxdepth 6 -name ".git" -print 2>/dev/null | sed 's|^\./||' | sed 's|/\.git$||' | sort || true)

    [ -z "$ON_DISK" ] && return

    while IFS= read -r p; do
        [ -z "$p" ] && continue
        if ! echo "$EXPECTED" | grep -Fxq "$p"; then
            echo "  - Removing leftover submodule dir not in '$BR': $p"
            rm -rf "$p" 2>/dev/null || true
            rm -rf ".git/modules/$p" 2>/dev/null || true
        fi
    done <<< "$ON_DISK"
}

while IFS= read -r BR; do
    [ -z "$BR" ] && continue
    echo ""
    echo "Initializing submodules on branch: $BR"

    git checkout "$BR" >/dev/null 2>&1

    # Deinit everything first to avoid cross-branch contamination
    git submodule deinit -f --all >/dev/null 2>&1 || true

    # Remove leftover submodule working dirs that don't belong on this branch
    cleanup_unexpected_submodule_dirs "$BR"

    # Sync + init only what's expected for this branch
    git -c protocol.file.allow=always submodule sync --recursive >/dev/null 2>&1 || true
    git -c protocol.file.allow=always submodule update --init --recursive --jobs 4 >/dev/null 2>&1 || true
done <<< "$ALL_BRANCHES"

git checkout "$ORIG_BRANCH" >/dev/null 2>&1 || true

echo ""
echo "OK Submodules initialized on all branches (clean)"

##############################################################################
# SUMMARY / CONFIRMATION
##############################################################################

echo ""
echo "============================================================"
echo "Full Test Repository Created Successfully"
echo "============================================================"
echo ""
echo "REPOSITORY STRUCTURE:"
echo "------------------------------------------------------------"
echo "full-test-repo/                          <- Super Repository"
echo "  branches: main, develop, feature/api-gateway, release/2.0"
echo "  tags: v1.0.0, v1.5.0, v2.0.0-dev, v2.0.0"
echo ""
echo "Branch-specific root-level submodules:"
echo "  main:"
echo "    services/user-service"
echo "    services/payment-service"
echo "  develop:"
echo "    services/user-service"
echo "    services/notification-service"
echo ""
echo "Nested submodule difference in user-service:"
echo "  main:"
echo "    lib/database (contains utils/logger)"
echo "  develop:"
echo "    lib/database (contains utils/logger)"
echo "    lib/feature-flags (develop only)"
echo ""
echo "Repository Location: $SUPER_PATH"
echo ""
echo "============================================================"
echo "CONFIRMATION OUTPUT (THIS IS WHAT bundle_all.sh MUST CAPTURE)"
echo "============================================================"
echo ""

echo "Super repo branches:"
git -C "$SUPER_PATH" branch

echo ""
echo "Super repo submodules by branch (from git tree):"
for BR in $(git -C "$SUPER_PATH" for-each-ref --format='%(refname:short)' refs/heads | sort); do
    echo ""
    echo "Branch: $BR"
    git -C "$SUPER_PATH" ls-tree -r --full-name "$BR" | awk '$1=="160000" {print "  " $4}'
done

echo ""
echo "Confirm user-service nested submodules by branch:"
for BR in main develop; do
    echo ""
    echo "user-service branch: $BR"
    git -C "$USER_SERVICE_PATH" ls-tree -r --full-name "$BR" | awk '$1=="160000" {print "  " $4}'
done

echo ""
echo "Next steps:"
echo "  1) Set REPO_PATH in bundle_all.sh to:"
echo "       REPO_PATH=\"$SUPER_PATH\""
echo "  2) Run:"
echo "       ./bundle_all.sh"
echo "  3) Transfer *_import folder and run:"
echo "       ./export_all.sh"
echo ""
echo "============================================================"
echo ""