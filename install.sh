#!/bin/ash

# --- Configuration ---
DEFAULT_CRON_SCHEDULE="0 4 * * *"
CRON_SCRIPT="upd-tailscale.sh"
INSTALL_DIR="$HOME/scripts"
INSTALL_PATH="$INSTALL_DIR/$CRON_SCRIPT"

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

# --- Package Manager Detection ---
# apkコマンドの有無でパッケージマネージャーを判定
PKG_MANAGER="opkg"

# --- Step 1 ---
print_header "[1/7] Checking OpenWrt Version"

if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    # Clean quotes from version string
    VERSION_STR="${DISTRIB_RELEASE//\"/}"
    MAJOR=$(echo "$VERSION_STR" | cut -d. -f1)

    case $MAJOR in
        ''|*[!0-9]*) 
            print_warn "Could not parse version number. Proceeding with standard installation." 
            ;;
        *)
            print_info "Detected OpenWrt Version: ${C_BOLD}$VERSION_STR${C_RESET}"

            if [ "$MAJOR" -ge 25 ] || [ "$PKG_MANAGER" = "apk" ]; then
                # Version 25.12+ (apk based)
                print_success "OpenWrt 25.12 detected."
                PKG_MANAGER="apk"
            elif [ "$MAJOR" -eq 24 ]; then
                # Version 24.10
                print_success "OpenWrt 24.10 detected."
                PKG_MANAGER="opkg"
            else
                # Version 23.05 or older (22, 23)
                print_warn "Old version OpenWrt detected. OpenWrt 24.10+ is recommended for best performance."
                PKG_MANAGER="opkg"
            fi
            ;;
    esac
else
    print_warn "/etc/openwrt_release not found. Proceeding carefully."
fi


# --- Step 2 ---
print_header "[2/7] Detecting Architecture"

# パッケージマネージャーに応じてアーキテクチャとチェック用ファイルを切り替え
if [ "$PKG_MANAGER" = "apk" ]; then
    ARCH=$(apk --print-arch)
    CHECK_FILE="APKINDEX.tar.gz"
else
    ARCH=$(opkg print-architecture | awk 'END {print $2}')
    CHECK_FILE="Packages.gz"
fi

REPO_URL="https://myurar1a.github.io/openwrt-tailscale-small/${ARCH}"

print_info "Architecture: ${C_BOLD}${ARCH}${C_RESET}"
print_info "Checking repository availability..."

if ! wget -q --spider --no-check-certificate "${REPO_URL}/${CHECK_FILE}"; then
    print_error "Repository not found for architecture '${ARCH}'."
    echo "   URL: ${REPO_URL}/${CHECK_FILE}"
    exit 1
fi
print_success "Repository found."


# --- Step 3 ---
print_header "[3/7] Installing Public Key"
TMP_KEY="/tmp/myurar1a-repo.pub"
RAW_URL="https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-small/refs/heads/main"
USIGN_PUBKEY_NAME="usign_key.pub"
APK_PUBKEY_NAME="apk_key.rsa.pub"

if wget -q --no-check-certificate -O "$TMP_KEY" "$RAW_URL/cert/$PUBKEY_NAME"; then
    if [ "$PKG_MANAGER" = "apk" ]; then
        # apk用の公開鍵の配置
        mkdir -p /etc/apk/keys
        cp "$TMP_KEY" "/etc/apk/keys/$PUBKEY_NAME"
        rm "$TMP_KEY"
        print_success "Public key installed to /etc/apk/keys/"
    else
        # opkg用の公開鍵のインストール
        opkg-key add "$TMP_KEY"
        rm "$TMP_KEY"
        print_success "Public key installed."
    fi
else
    print_error "Failed to download public key."
    exit 1
fi


# --- Step 4 ---
print_header "[4/7] Configuring Repository"
if [ "$PKG_MANAGER" = "apk" ]; then
    # apk用のリポジトリ設定
    FEED_CONF="/etc/apk/repositories.d/custom_tailscale.list"
    mkdir -p /etc/apk/repositories.d
    if [ ! -f "$FEED_CONF" ] || ! grep -q "$REPO_URL" "$FEED_CONF"; then
        echo "$REPO_URL" >> "$FEED_CONF"
        print_success "Repository added to $FEED_CONF"
    else
        print_info "Repository already configured."
    fi
else
    # opkg用のリポジトリ設定
    FEED_CONF="/etc/opkg/customfeeds.conf"
    if ! grep -q "custom_tailscale" "$FEED_CONF"; then
        echo "src/gz custom_tailscale ${REPO_URL}" >> "$FEED_CONF"
        print_success "Repository added to customfeeds.conf"
    else
        print_info "Repository already configured."
    fi
fi


# --- Step 5 ---
print_header "[5/7] Installing Tailscale"
print_info "Updating package lists..."

if [ "$PKG_MANAGER" = "apk" ]; then
    # apkインストール
    if ! apk update >/dev/null 2>&1; then
        print_error "'apk update' failed. Check internet connection or repo signature."
        exit 1
    fi

    # インストール済みの確認
    INSTALLED=$(apk info -e tailscale 2>/dev/null)
    if [ -n "$INSTALLED" ]; then
        print_warn "Tailscale is already installed ($INSTALLED)."
        if ask_yes_no "Re-install/Update to ensure latest version?"; then
            echo ""
            echo ">> apk del tailscale"
            apk del tailscale
            echo ""
            echo ">> apk add tailscale"
            apk add tailscale
            print_success "Tailscale re-installed."
        else
            print_error "Installation Canceled."
            exit 1
        fi
    else
        print_info "Installing Tailscale package..."
        echo ""
        echo ">> apk add tailscale"
        apk add tailscale
        print_success "Tailscale installed."
    fi
else
    # opkgインストール
    if ! opkg update >/dev/null 2>&1; then
        print_error "'opkg update' failed. Check internet connection or repo signature."
        exit 1
    fi

    # インストール済みの確認
    INSTALLED=$(opkg list-installed tailscale | awk '{print $3}')
    if [ -n "$INSTALLED" ]; then
        print_warn "Tailscale is already installed ($INSTALLED)."
        if ask_yes_no "Re-install/Update to ensure latest version?"; then
            echo ""
            echo ">> opkg remove tailscale"
            opkg remove tailscale
            echo ""
            echo ">> opkg install tailscale"
            opkg install tailscale
            print_success "Tailscale re-installed."
        else
            print_error "Installation Canceled."
            exit 1
        fi
    else
        print_info "Installing Tailscale package..."
        echo ""
        echo ">> opkg install tailscale"
        opkg install tailscale
        print_success "Tailscale installed."
    fi
fi


# --- Step 6 ---
print_header "[6/7] Auto-Update Script Setup"

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
        printf "   Use custom schedule? [y/N]: "
        read CUSTOM_OPT
        if [ "$CUSTOM_OPT" = "y" ] || [ "$CUSTOM_OPT" = "Y" ]; then
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


# --- Step 7 (Network) ---
print_header "[7/7] Network & Firewall Configuration"

if ask_yes_no "Configure 'tailscale' interface and firewall zone automatically?"; then
    print_info "Applying network settings..."
    
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
if [ -n "$MAJOR" ] && [ "$MAJOR" -eq 24 ]; then
    print_header "Option: Performance Optimization (OpenWrt 24.10)"
    echo "OpenWrt 24.10 supports UDP transport layer offloading (UDP-GRO/GSO),"
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
