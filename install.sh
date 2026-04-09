#!/bin/ash

# --- Configuration ---
DEFAULT_CRON_SCHEDULE="0 4 * * *"
CRON_SCRIPT="upd-tailscale.sh"
INSTALL_DIR="$HOME/scripts"
INSTALL_PATH="$INSTALL_DIR/$CRON_SCRIPT"
RAW_URL="https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-small/refs/heads/main"

# --- UI Colors & Formatting ---
# OpenWrt ash supports echo -e for colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[36m' # Cyan for headers
C_GREY='\033[90m'

# --- UI Helper Functions ---

print_header() {
    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE} $1 ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"
}

print_info() {
    echo -e "${C_BOLD}>>${C_RESET} $1"
}

print_success() {
    echo -e "${C_GREEN}✔ Success:${C_RESET} $1"
}

print_warn() {
    echo -e "${C_YELLOW}⚠ Warning:${C_RESET} $1"
}

print_error() {
    echo -e "${C_RED}✘ Error:${C_RESET} $1"
}

# Prompt function: Returns 0 for YES, 1 for NO
# Default is YES (Enter key)
ask_yes_no() {
    local prompt="$1"
    echo ""
    # Print the question in Green/Bold to stand out
    echo -e "${C_GREEN}[?] $prompt ${C_RESET}${C_GREY}[Y/n]${C_RESET}"
    printf "> "
    read response
    
    case "$response" in
        [yY][eE][sS]|[yY]|"") return 0 ;;
        *) return 1 ;;
    esac
}

# --- Execution Functions ---

# Action selector shown only when Tailscale is already installed
ask_already_action() {
    echo ""
    echo -e " ${C_BOLD}Tailscale is already installed. Select action:${C_RESET}"
    echo -e "   ${C_BOLD}1)${C_RESET} Re-install / Update"
    echo -e "   ${C_BOLD}2)${C_RESET} Uninstall"
    echo -e "   ${C_BOLD}3)${C_RESET} Skip to Step 8 (Auto-Update Script Setup)"
    echo -e "   ${C_BOLD}4)${C_RESET} Exit"
    printf "> "
    read ALREADY_ACTION
}

do_uninstall() {
    print_header "Uninstalling Tailscale"

    # Stop and disable the Tailscale service
    print_info "Stopping Tailscale service..."
    tailscale down 2>/dev/null || true
    /etc/init.d/tailscale stop 2>/dev/null || true
    /etc/init.d/tailscale disable 2>/dev/null || true

    # Remove package
    print_info "Removing Tailscale package..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk del tailscale 2>/dev/null && print_success "Package removed." || print_warn "Package not found, skipping."
    else
        opkg remove tailscale 2>/dev/null && print_success "Package removed." || print_warn "Package not found, skipping."
    fi

    # Remove cron job
    if crontab -l 2>/dev/null | grep -q "$INSTALL_PATH"; then
        print_info "Removing cron job..."
        crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" | crontab -
        /etc/init.d/cron restart
        print_success "Cron job removed."
    else
        print_info "No cron job found, skipping."
    fi

    # Remove auto-update script
    if [ -f "$INSTALL_PATH" ]; then
        print_info "Removing auto-update script..."
        rm -f "$INSTALL_PATH"
        print_success "Script removed: $INSTALL_PATH"
    else
        print_info "Auto-update script not found, skipping."
    fi

    # Remove repository config and public key
    if [ "$PKG_MANAGER" = "apk" ]; then
        rm -f /etc/apk/keys/myurar1a-repo.rsa.pub
        rm -f /etc/apk/repositories.d/custom_tailscale.list
    else
        sed -i '/custom_tailscale/d' /etc/opkg/customfeeds.conf 2>/dev/null || true
    fi
    print_success "Repository config and key removed."

    # Remove network and firewall UCI config
    if ask_yes_no "Remove 'tailscale' interface and firewall zone from UCI config?"; then
        print_info "Removing network interface..."
        uci delete network.tailscale 2>/dev/null || print_warn "Interface 'tailscale' not found in UCI, skipping."
        uci delete network.globals.packet_steering 2>/dev/null || true

        print_info "Removing firewall rules..."
        # Remove forwarding rules referencing tailscale (iterate in reverse to keep indices valid)
        for idx in $(uci show firewall | grep -E "forwarding\.[0-9]+\.src='tailscale'|forwarding\.[0-9]+\.dest='tailscale'" | grep -o '@forwarding\[[0-9]*\]' | sort -t'[' -k2 -rn | uniq); do
            uci delete firewall.$idx 2>/dev/null || true
        done
        # Remove firewall zone named tailscale
        for idx in $(uci show firewall | grep "zone\.[0-9]*.name='tailscale'" | grep -o '@zone\[[0-9]*\]' | sort -t'[' -k2 -rn | uniq); do
            uci delete firewall.$idx 2>/dev/null || true
        done

        uci commit network
        uci commit firewall
        /etc/init.d/network reload
        /etc/init.d/firewall reload
        print_success "Network and firewall configuration removed."
    else
        print_info "Skipping UCI config removal."
    fi

    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}   Uninstall Complete!   ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo ""
}

# ---------------------

set -e

# Clear screen for a fresh start
clear

echo -e "${C_BOLD}${C_BLUE}"
echo "   OpenWrt Tailscale Installer   "
echo "   (Simple & Automated Setup)    "
echo -e "${C_RESET}"
echo -e " * Press ${C_BOLD}ENTER${C_RESET} to accept default values (Yes)."
echo -e " * Press ${C_BOLD}Ctrl+C${C_RESET} to abort at any time."


# --- Step 1 ---
print_header "[1/8] Checking OpenWrt Version"

if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    # Clean quotes from version string
    VERSION_STR="${DISTRIB_RELEASE//\"/}"
    ARCH="${DISTRIB_ARCH//\"/}"

    if [ "$VERSION_STR" = "SNAPSHOT" ]; then
        print_success "Detected OpenWrt Version: ${C_BOLD}$VERSION_STR${C_RESET}"
        PKG_MANAGER="apk"
    else
        MAJOR=$(echo "$VERSION_STR" | cut -d. -f1)
        case $MAJOR in
            ''|*[!0-9]*) 
                print_warn "Could not parse version number. Proceeding with standard installation." 
                ;;
            *)
                print_success "Detected OpenWrt Version: ${C_BOLD}$VERSION_STR${C_RESET}"
                if [ "$MAJOR" -ge 25 ]; then
                    # Version 25.12 or newer
                    PKG_MANAGER="apk"
                elif [ "$MAJOR" -eq 24 ]; then
                    # Version 24.10
                    PKG_MANAGER="opkg"
                else
                    # Version 23.05 or older (22, 23)
                    print_warn "Old version OpenWrt detected. OpenWrt 24.10+ is recommended for best performance."
                    PKG_MANAGER="opkg"
                fi
                ;;
        esac
    fi
else
    print_error "/etc/openwrt_release not found. Please execute on OpenWrt."
    exit 1
fi


# --- Step 2 ---
print_header "[2/8] Check installed list"

if [ "$PKG_MANAGER" = "apk" ]; then
    if apk info -e tailscale >/dev/null 2>&1; then
        print_warn "Tailscale is already installed."
        ask_already_action
        case "$ALREADY_ACTION" in
            1)
                print_info "Removing existing installation..."
                echo ""
                echo ">> apk del tailscale"
                apk del tailscale
                ;;
            2)
                do_uninstall
                exit 0
                ;;
            3)
                print_info "Skipping to Step 8..."
                SKIP_INSTALL=true
                ;;
            *)
                print_info "Exiting installer."
                exit 0
                ;;

        esac
    else
        print_info "Tailscale is not installed. Proceeding with installation..."
    fi
else
    INSTALLED=$(opkg list-installed tailscale | awk '{print $3}')
    if [ -n "$INSTALLED" ]; then
        print_warn "Tailscale is already installed ($INSTALLED)."
        ask_already_action
        case "$ALREADY_ACTION" in
            1)
                print_info "Removing existing installation..."
                echo ""
                echo ">> opkg remove tailscale"
                opkg remove tailscale
                ;;
            2)
                do_uninstall
                exit 0
                ;;
            3)
                print_info "Skipping to Step 8..."
                SKIP_INSTALL=true
                ;;
            *)
                print_info "Exiting installer."
                exit 0
                ;;
        esac
    else
        print_info "Tailscale is not installed. Proceeding with installation..."
    fi
fi


if [ -z "$SKIP_INSTALL" ]; then # start of SKIP_INSTALL block
# --- Step 3 ---
print_header "[3/8] Check Repository"
print_info "Checking repository availability..."
REPO_URL="https://myurar1a.github.io/openwrt-tailscale-small"

if [ "$PKG_MANAGER" = "apk" ]; then
    CHECK_FILE="APKINDEX.tar.gz"
else
    CHECK_FILE="Packages.gz"
fi

if ! wget -q --spider --no-check-certificate "${REPO_URL}/${ARCH}/${CHECK_FILE}"; then
    print_error "Repository not found for architecture '${ARCH}'."
    echo "   URL: ${REPO_URL}/${ARCH}/${CHECK_FILE}"
    exit 1
fi
print_success "Repository found."


# --- Step 4 ---
print_header "[4/8] Installing Public Key"
USIGN_PUBKEY_NAME="usign_key.pub"

if [ "$PKG_MANAGER" = "apk" ]; then
    # apk用の公開鍵の配置
    mkdir -p /etc/apk/keys
    if wget -q --no-check-certificate -O "/etc/apk/keys/myurar1a-repo.rsa.pub" "$RAW_URL/cert/apk_key.rsa.pub"; then
        print_success "Public key installed to /etc/apk/keys/"
    else
        print_error "Failed to download public key."
        exit 1
    fi
else
    # opkg用の公開鍵のインストール
    if wget -q --no-check-certificate -O "/tmp/$USIGN_PUBKEY_NAME" "$RAW_URL/cert/$USIGN_PUBKEY_NAME"; then
        opkg-key add "/tmp/$USIGN_PUBKEY_NAME"
        rm "/tmp/$USIGN_PUBKEY_NAME"
        print_success "Public key installed."
    else
        print_error "Failed to download public key."
        exit 1
    fi
fi


# --- Step 5 ---
print_header "[5/8] Configuring Repository"
if [ "$PKG_MANAGER" = "apk" ]; then
    FEED_CONF="/etc/apk/repositories.d/custom_tailscale.list"
    mkdir -p /etc/apk/repositories.d
    if [ ! -f "$FEED_CONF" ] || ! grep -q "$REPO_URL" "$FEED_CONF"; then
        echo "$REPO_URL" >> "$FEED_CONF"
        print_success "Repository added to $FEED_CONF"
    else
        print_info "Repository already configured."
    fi
else
    FEED_CONF="/etc/opkg/customfeeds.conf"
    if ! grep -q "custom_tailscale" "$FEED_CONF"; then
        echo "src/gz custom_tailscale ${REPO_URL}/${ARCH}" >> "$FEED_CONF"
        print_success "Repository added to customfeeds.conf"
    else
        print_info "Repository already configured."
    fi
fi


# --- Step 6 ---
print_header "[6/8] Installing Tailscale"
print_info "Updating package lists..."

if [ "$PKG_MANAGER" = "apk" ]; then
    if ! apk update >/dev/null 2>&1; then
        print_error "'apk update' failed. Check internet connection."
        exit 1
    fi
    print_info "Installing dependencies..."
    echo ""
    echo ">> apk add ca-bundle kmod-tun libc"
    apk apk add ca-bundle kmod-tun libc
    echo ""
    print_info "Installing Tailscale package..."
    echo ""
    echo ">> apk add tailscale"
    apk add tailscale
    print_success "Tailscale installed."
else
    if ! opkg update >/dev/null 2>&1; then
        print_error "'opkg update' failed. Check internet connection."
        exit 1
    fi
    print_info "Installing Tailscale package..."
    echo ""
    echo ">> opkg install tailscale"
    opkg install tailscale
    print_success "Tailscale installed."
fi
fi # end of SKIP_INSTALL block


# --- Step 7 ---
print_header "[7/8] Auto-Update Script Setup"

if ask_yes_no "Install auto-update script and schedule Cron job?"; then
    # Create directory if it doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
    fi

    # Download script
    if [ "$PKG_MANAGER" = "apk" ]; then
        UPDATER_URL="$RAW_URL/upd-tailscale_apk.sh"
    else
        UPDATER_URL="$RAW_URL/upd-tailscale_opkg.sh"
    fi

    if wget -q --no-check-certificate -O "$INSTALL_PATH" "$UPDATER_URL"; then
        chmod +x "$INSTALL_PATH"
        print_success "Script downloaded to $INSTALL_PATH"
    else
        print_error "Failed to download update script."
        exit 1
    fi

    # Cron Setup
    if crontab -l 2>/dev/null | grep -q "$INSTALL_PATH"; then
        print_info "Cron job already exists."
    else
        FINAL_SCHEDULE="$DEFAULT_CRON_SCHEDULE"
        
        # Optional: Custom schedule
        echo -e "   Default schedule: ${C_BOLD}$DEFAULT_CRON_SCHEDULE${C_RESET} (4:00 AM)"
        if ask_yes_no "Use default schedule? (No: Custom)"; then
            print_info "Using default schedule."
        else
            printf "   Enter cron schedule (e.g., '30 2 * * *'): "
            read USER_SCHEDULE
            [ -n "$USER_SCHEDULE" ] && FINAL_SCHEDULE="$USER_SCHEDULE"
        fi

        (crontab -l 2>/dev/null; echo "$FINAL_SCHEDULE $INSTALL_PATH") | crontab -
        /etc/init.d/cron restart
        print_success "Cron job added: $FINAL_SCHEDULE"
    fi
else
    print_info "Skipping auto-update setup."
fi


# --- Step 8 (Network) ---
print_header "[8/8] Network & Firewall Configuration"

if ask_yes_no "Configure 'tailscale' interface and firewall zone automatically?"; then
    print_info "Applying network settings..."
    
    # 1. Interface Config (Safe to overwrite)
    uci set network.tailscale=interface
    uci set network.tailscale.proto='none'
    uci set network.tailscale.device='tailscale0'
    # Optional global setting mentioned in official reference
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

    uci commit network
    uci commit firewall

    echo "Reloading network and firewall..."
    /etc/init.d/network reload
    /etc/init.d/firewall reload
    print_success "Network configuration applied."
else
    print_info "Skipping network configuration."
fi

# --- Performance Optimization (Conditional) ---
if [ -n "$MAJOR" ] && [ "$MAJOR" -ge 24 ]; then
    print_header "Option: Performance Optimization (OpenWrt 24.10+)"
    echo "OpenWrt 24.10+ supports UDP transport layer offloading (UDP-GRO/GSO),"
    echo "which can significantly improve Tailscale throughput."
    echo ""
    echo "To enable this, 'ethtool' is required, along with specific hardware configuration."
    echo "Please refer to the following documents for setup:"
    echo "1. https://tailscale.com/kb/1320/performance-best-practices#linux-optimizations-for-subnet-routers-and-exit-nodes"
    echo "2. https://openwrt.org/docs/guide-user/services/vpn/tailscale/start#throughput_improvements_via_transport_layer_offloading_in_openwrt_2410"
    
    if ask_yes_no "Install 'ethtool' now?"; then
        if [ "$PKG_MANAGER" = "apk" ]; then
            apk update >/dev/null 2>&1 && apk add ethtool
        else
            opkg update >/dev/null 2>&1 && opkg install ethtool
        fi
        print_success "ethtool installed."
    else
        print_info "Skipping ethtool installation."
    fi
fi


# --- Final Step ---
print_header "Tailscale Initial Setup"

if ask_yes_no "Run 'tailscale up' now to authenticate?"; then
    echo ""
    echo -e "${C_BOLD}>>> Starting Tailscale Authentication...${C_RESET}"
    echo "    Please copy the URL below if prompted."
    echo ""
    tailscale up
    
    echo ""
    print_success "Tailscale is now up!"
    echo "If you need to enable specific features (flags) later,"
    echo "please use the 'tailscale set [flags]' command."
    echo ""
    echo "For more details, please refer to the official documentation:"
    echo "https://tailscale.com/kb/1080/cli#set"
else
    print_info "Skipping authentication. Run 'tailscale up' manually later."
fi

echo ""
echo -e "${C_BLUE}========================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}   Installation & Setup Complete!   ${C_RESET}"
echo -e "${C_BLUE}========================================================${C_RESET}"
echo ""
