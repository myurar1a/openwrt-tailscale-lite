#!/bin/ash

# --- Configuration ---
DEFAULT_CRON_SCHEDULE="0 4 * * *"
CRON_SCRIPT="upd-tailscale.sh"
INSTALL_DIR="$HOME/scripts"
INSTALL_PATH="$INSTALL_DIR/$CRON_SCRIPT"
# ---------------------

set -e
echo "=== OpenWrt Small Tailscale Installer ==="

echo "[1/9] Checking OpenWrt Version..."

if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    # Clean quotes from version string (e.g., "24.10.0" -> 24.10.0)
    VERSION_STR="${DISTRIB_RELEASE//\"/}"
    # Extract Major version (e.g., 23, 24, 25)
    MAJOR=$(echo "$VERSION_STR" | cut -d. -f1)

    # Check if MAJOR is a number
    case $MAJOR in
        ''|*[!0-9]*) 
            echo "Warning: Could not parse version number. Proceeding with standard installation." 
            ;;
        *)
            echo "Detected Major Version: $MAJOR"

            if [ "$MAJOR" -ge 25 ]; then
                # Version 25+ (Future support for apk)
                echo "--------------------------------------------------------"
                echo "NOTICE: OpenWrt 25.12 detected."
                echo "The package system has changed to 'apk' in this version."
                echo "Support for this environment is pending validation."
                echo "Aborting installation to prevent system issues."
                echo "--------------------------------------------------------"
                exit 0

            elif [ "$MAJOR" -eq 24 ]; then
                # Version 24 (Install ethtool)
                echo "Version 24.10 detected. Verifying ethtool..."
                if ! opkg list-installed | grep -q "ethtool"; then
                    echo "Installing ethtool..."
                    opkg update && opkg install ethtool
                fi

            else
                # Version 23 or older (22, 23)
                echo "-----------------------------------------------------------------"
                echo "TIPS: For optimal performance, please use OpenWrt 24.10 or later."
                echo "-----------------------------------------------------------------"
            fi
            ;;
    esac
else
    echo "Warning: /etc/openwrt_release not found. Proceeding with standard installation."
fi


echo "[2/8] Checking dependencies..."
if ! opkg list-installed | grep -q "curl"; then
    opkg update && opkg install curl
fi
if ! opkg list-installed | grep -q "ca-bundle"; then
    opkg update && opkg install ca-bundle
fi
if ! opkg list-installed | grep -q "kmod-tun"; then
    opkg update && opkg install kmod-tun
fi


echo "[3/8] Detecting architecture..."
ARCH=$(opkg print-architecture | awk 'END {print $2}')
REPO_URL="https://myurar1a.github.io/openwrt-tailscale-small/${ARCH}"

# Checking repository...
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${REPO_URL}/Packages.gz")

if [ "$HTTP_CODE" != "200" ]; then
    echo "Error: Repository not found for architecture '${ARCH}'."
    echo "URL: ${REPO_URL}"
    echo "Please check if your device architecture is supported in the GitHub repository."
    exit 1
fi
echo "Target: $ARCH"


echo "[4/8] Installing Public Key..."
KEY_DIR="/etc/opkg/keys"
if [ ! -d "$KEY_DIR" ]; then
    mkdir -p "$KEY_DIR"
fi

# Download public key
RAW_URL="https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-small/refs/heads/main"
PUBKEY_NAME="myurar1a-repo.pub"
if curl -sL "$RAW_URL/cert/$PUBKEY_NAME" -o "$KEY_DIR/$PUBKEY_NAME"; then
    echo "Public key installed to $KEY_DIR/$PUBKEY_NAME"
else
    echo "Error: Failed to download public key."
    exit 1
fi


echo "[5/8] Configuring repository..."
FEED_CONF="/etc/opkg/customfeeds.conf"
if ! grep -q "custom_tailscale" "$FEED_CONF"; then
    echo "src/gz custom_tailscale ${REPO_URL}" >> "$FEED_CONF"
fi


echo "[6/8] Installing Tailscale..."
if ! opkg update; then
    echo "Error: 'opkg update' failed. Signature verification might have failed."
    echo "Please check if the repository is correctly signed."
    exit 1
fi

INSTALLED=$(opkg list-installed tailscale | awk '{print $3}')
if [ -n "$INSTALLED" ]; then
    echo "Tailscale is already installed ($INSTALLED)."
    printf "Re-install to ensure latest version? [y/N]: "
    read ANSWER
    if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
        opkg remove tailscale
        opkg install tailscale
    fi
else
    opkg install tailscale
fi


echo "[7/8] Setup Auto-Update Script..."
printf "Do you want to install the auto-update script? [y/N]: "
read INSTALL_UPDATER

if [ "$INSTALL_UPDATER" = "y" ] || [ "$INSTALL_UPDATER" = "Y" ]; then
    # Create directory if it doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "Creating directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi

    curl -sL "$RAW_URL/install.sh" -o "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "Script installed to $INSTALL_PATH"

    # --- Cron Schedule Section ---
    echo "[8/8] Scheduling Cron job..."
    printf "Do you want to schedule a Cron job for auto-updates? [y/N]: "
    read SETUP_CRON

    if [ "$SETUP_CRON" = "y" ] || [ "$SETUP_CRON" = "Y" ]; then
        if crontab -l 2>/dev/null | grep -q "$INSTALL_PATH"; then
            echo "Cron job already exists for this script."
        else
            FINAL_SCHEDULE="$DEFAULT_CRON_SCHEDULE"
            
            printf "Default schedule is '$DEFAULT_CRON_SCHEDULE' (4:00 AM). Use custom schedule? [y/N]: "
            read CUSTOM_OPT
            if [ "$CUSTOM_OPT" = "y" ] || [ "$CUSTOM_OPT" = "Y" ]; then
                printf "Enter cron schedule (e.g., '30 2 * * *'): "
                read USER_SCHEDULE
                if [ -n "$USER_SCHEDULE" ]; then
                    FINAL_SCHEDULE="$USER_SCHEDULE"
                else
                    echo "Input empty, using default."
                fi
            fi

            (crontab -l 2>/dev/null; echo "$FINAL_SCHEDULE $INSTALL_PATH") | crontab -
            echo "Cron job added with schedule: $FINAL_SCHEDULE"
            /etc/init.d/cron restart
        fi
    else
        echo "Skipping Cron job setup."
    fi

else
    echo "Skipping auto-update script installation."
    echo "[8/8] Skipping Cron job setup (script not installed)."
fi

echo ""
echo "=== Installation Complete! ==="
echo ""

echo "[9/8] Tailscale Initial Setup..."
printf "Do you want to run 'tailscale up' now to authenticate? [y/N]: "
read RUN_UP

if [ "$RUN_UP" = "y" ] || [ "$RUN_UP" = "Y" ]; then
    echo "Running 'tailscale up'..."
    tailscale up
else
    echo "Skipping authentication."
    echo "You can run 'tailscale up' manually later."
fi
