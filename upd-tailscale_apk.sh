#!/bin/ash

# --- Configuration ---
PACKAGE="tailscale"
LOG_TAG="tailscale-autoupdate"
UP_FLAGS="--accept-routes"
# ---------------------

# 1. Update package list
apk update > /dev/null 2>&1

# 2. Get version information
INSTALLED_VER=$(apk info -v $PACKAGE 2>/dev/null | sed "s/^$PACKAGE-//")

# Do nothing if not installed
if [ -z "$INSTALLED_VER" ]; then
    exit 0
fi

# 3. Check for upgrade availability
UPGRADABLE=$(apk list -u $PACKAGE 2>/dev/null | grep "^$PACKAGE-")

if [ -n "$UPGRADABLE" ]; then
    CANDIDATE_VER=$(echo "$UPGRADABLE" | awk '{print $1}' | sed "s/^$PACKAGE-//")
    logger -t "$LOG_TAG" "New version found: $CANDIDATE_VER (Current: $INSTALLED_VER). Starting update..."

    # 4. Safe update (Remove -> Install to avoid Flash space shortage)
    apk del $PACKAGE >/dev/null 2>&1
    apk add $PACKAGE >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        logger -t "$LOG_TAG" "Update successful to $CANDIDATE_VER"
        /etc/init.d/tailscale restart
    else
        logger -t "$LOG_TAG" "Update failed! Attempting to reinstall previous version..."
        # Rollback attempt (if cached)
        apk add $PACKAGE >/dev/null 2>&1
    fi
else
    # Exit silently if no update (no log output)
    :
fi
