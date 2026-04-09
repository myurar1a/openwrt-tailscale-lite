#!/bin/ash

# --- Configuration ---
PACKAGE="tailscale"
LOG_TAG="tailscale-autoupdate"
UP_FLAGS="--accept-routes"
# ---------------------

# 1. Update package list
opkg update > /dev/null 2>&1

# 2. Get version information
INSTALLED_VER=$(opkg list-installed $PACKAGE | awk '{print $3}')
CANDIDATE_VER=$(opkg list $PACKAGE | awk '{print $3}' | head -n 1)

# Do nothing if not installed
if [ -z "$INSTALLED_VER" ]; then
    exit 0
fi

# 3. Compare versions
if [ "$INSTALLED_VER" != "$CANDIDATE_VER" ] && [ -n "$CANDIDATE_VER" ]; then
    logger -t "$LOG_TAG" "New version found: $CANDIDATE_VER (Current: $INSTALLED_VER). Starting update..."

    # 4. Safe update (Remove -> Install to avoid Flash space shortage)
    opkg remove $PACKAGE
    opkg install $PACKAGE

    if [ $? -eq 0 ]; then
        logger -t "$LOG_TAG" "Update successful to $CANDIDATE_VER"
        /etc/init.d/tailscale restart
    else
        logger -t "$LOG_TAG" "Update failed! Attempting to reinstall previous version..."
        # Rollback attempt (if cached)
        opkg install $PACKAGE
    fi
else
    # Exit silently if no update (no log output)
    :
fi
