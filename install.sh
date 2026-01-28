#!/bin/ash

# --- Configuration ---
DEFAULT_CRON_SCHEDULE="0 4 * * *"
CRON_SCRIPT="upd-tailscale.sh"
INSTALL_DIR="$HOME/scripts"
INSTALL_PATH="$INSTALL_DIR/$CRON_SCRIPT"
# ---------------------

set -e
echo "=== OpenWrt Small Tailscale Installer ==="

echo "[1/7] Checking OpenWrt Version..."

if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    # Clean quotes from version string
    VERSION_STR="${DISTRIB_RELEASE//\"/}"
    # Extract Major version
    MAJOR=$(echo "$VERSION_STR" | cut -d. -f1)

    case $MAJOR in
        ''|*[!0-9]*) 
            echo "Warning: Could not parse version number. Proceeding with standard installation." 
            ;;
        *)
            echo "Detected Major Version: $MAJOR"

            if [ "$MAJOR" -ge 25 ]; then
                # Version 25.12+ (Future support for apk)
                echo "--------------------------------------------------------"
                echo "NOTICE: OpenWrt 25.12 detected."
                echo "The package system has changed to 'apk' in this version."
                echo "Support for this environment is pending validation."
                echo "Aborting installation to prevent system issues."
                echo "--------------------------------------------------------"
                exit 0

            elif [ "$MAJOR" -eq 24 ]; then
                # Version 24.10 (Install ethtool)
                echo "Version 24.10 detected. Verifying ethtool..."
                if ! opkg list-installed | grep -q "ethtool"; then
                    echo "Installing ethtool..."
                    opkg update && opkg install ethtool
                fi

            else
                # Version 23.05 or older (22, 23)
                echo "-----------------------------------------------------------------"
                echo "TIPS: For optimal performance, please use OpenWrt 24.10 or later."
                echo "-----------------------------------------------------------------"
            fi
            ;;
    esac
else
    echo "Warning: /etc/openwrt_release not found. Proceeding with standard installation."
fi


echo "[2/7] Detecting architecture..."
ARCH=$(opkg print-architecture | awk 'END {print $2}')
REPO_URL="https://myurar1a.github.io/openwrt-tailscale-small/${ARCH}"

# Checking repository using wget
# --spider checks for existence, -q is quiet
if ! wget -q --spider --no-check-certificate "${REPO_URL}/Packages.gz"; then
    echo "Error: Repository not found for architecture '${ARCH}'."
    echo "URL: ${REPO_URL}"
    echo "Please check if your device architecture is supported in the GitHub repository."
    exit 1
fi
echo "Target: $ARCH"


echo "[3/7] Installing Public Key..."
TMP_KEY="/tmp/myurar1a-repo.pub"
RAW_URL="https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-small/refs/heads/main"
PUBKEY_NAME="myurar1a-repo.pub"

if wget -q --no-check-certificate -O "$TMP_KEY" "$RAW_URL/cert/$PUBKEY_NAME"; then
    opkg-key add "$TMP_KEY"
    echo "Public key installed via opkg-key"
    rm "$TMP_KEY"
else
    echo "Error: Failed to download public key."
    exit 1
fi


echo "[4/7] Configuring repository..."
FEED_CONF="/etc/opkg/customfeeds.conf"
if ! grep -q "custom_tailscale" "$FEED_CONF"; then
    echo "src/gz custom_tailscale ${REPO_URL}" >> "$FEED_CONF"
fi


echo "[5/7] Installing Tailscale..."
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


echo "[6/7] Setup Auto-Update Script..."
printf "Do you want to install the auto-update script? [y/N]: "
read INSTALL_UPDATER

if [ "$INSTALL_UPDATER" = "y" ] || [ "$INSTALL_UPDATER" = "Y" ]; then
    # Create directory if it doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "Creating directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi

    # Download the specific update script using wget
    UPDATER_URL="$RAW_URL/upd-tailscale.sh"
    
    if wget -q --no-check-certificate -O "$INSTALL_PATH" "$UPDATER_URL"; then
        chmod +x "$INSTALL_PATH"
        echo "Script installed to $INSTALL_PATH"
    else
        echo "Error: Failed to download update script."
        exit 1
    fi

    # --- Cron Schedule Section ---
    echo "[7/7] Scheduling Cron job..."
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
fi

echo ""
echo "=== Installation Complete! ==="
echo ""

echo "[8/7] Configuring Network & Firewall..."
printf "Do you want to configure the 'tailscale' interface and firewall zone automatically? [y/N]: "
read CONFIG_FW

if [ "$CONFIG_FW" = "y" ] || [ "$CONFIG_FW" = "Y" ]; then
    echo "Configuring network interface..."
    
    # 1. Interface Config (Safe to overwrite)
    uci set network.tailscale=interface
    uci set network.tailscale.proto='none'
    uci set network.tailscale.device='tailscale0'
    # Optional global setting mentioned in your reference
    uci set network.globals.packet_steering='1'

    # 2. Firewall Config
    # Check if zone exists to avoid duplicates
    if uci show firewall | grep -q "name='tailscale'"; then
        echo "Firewall zone 'tailscale' already exists. Skipping firewall rules to prevent duplicates."
    else
        echo "Creating firewall zone and forwarding rules..."
        
        # Add Zone
        uci add firewall zone >/dev/null
        uci set firewall.@zone[-1].name='tailscale'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci add_list firewall.@zone[-1].network='tailscale'
        
        # Add Forwarding: Tailscale -> LAN
        uci add firewall forwarding >/dev/null
        uci set firewall.@forwarding[-1].src='tailscale'
        uci set firewall.@forwarding[-1].dest='lan'
        
        # Add Forwarding: LAN -> Tailscale
        uci add firewall forwarding >/dev/null
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].dest='tailscale'
    fi

    # Commit and Reload
    uci commit network
    uci commit firewall
    echo "Reloading network and firewall..."
    /etc/init.d/network reload
    /etc/init.d/firewall reload
    echo "Configuration applied."
else
    echo "Skipping network configuration."
fi

echo "[9/7] Tailscale Initial Setup..."
printf "Do you want to run 'tailscale up' now to authenticate? [y/N]: "
read RUN_UP

if [ "$RUN_UP" = "y" ] || [ "$RUN_UP" = "Y" ]; then
    echo "Running 'tailscale up'..."
    tailscale up
else
    echo "Skipping authentication."
    echo "You can run 'tailscale up' manually later."
fi
