# Lightweight Tailscale for OpenWrt
Automated build of a stripped-down, UPX-compressed [Tailscale](https://tailscale.com/) package for OpenWrt devices with limited storage.

## Features

- **Always Up-to-Date**: Automatically detects new releases from the [official Tailscale repository](https://github.com/tailscale/tailscale) and triggers a build immediately.
- **Optimized for OpenWrt**:
  - Built as both `.ipk` packages for installation via Opkg and `.apk` packages for installation via Apk.
  - **Small Size**: Package size is reduced to around 5MB.
  - **Multicall Binary**: Combines `tailscale` and `tailscaled` CLI into a single binary to save space.
- **Official Build Standards**:
  - Built using Tailscale's official `build_dist.sh` script, with the required feature tags added and the `--extra-small --box` flags.
  - Compressed using `upx --best --lzma` as recommended in the official documentation.

## Supported Architectures

- **x86** (i386)
- **x86_64** (amd64)
- **ARM64** (aarch64)
- **ARM** (arm_cortex-a9, etc.)
- **MIPS** (mips, mipsel)
- **RISC-V64** (riscv64)
- **PPC64** (powerpc64_e5500)

---

## Installation (Recommended)

Run the following command on your OpenWrt router.  
This script handles dependencies, repository setup, installation, and auto-update configuration.

```sh
sh -c "$(wget --no-check-certificate -qO- https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-lite/refs/heads/main/install.sh)"
```

### What this installer does:
1. Detects your router's OpenWrt version and architecture.
2. Checks the installation.
3. Adds this repository to Opkg feeds.
4. Installs the `tailscale` package.
5. Installs an auto-update script to `~/scripts/upd-tailscale.sh`.
6. Sets up a Cron job to check for updates.
7. Sets up network and firewall configuration.
8. Runs 'tailscale up'.

---

## Auto-Update Mechanism

The installer sets up a cron job that runs `~/scripts/upd-tailscale.sh` at 4 AM.

- **Check**: Compares the installed version with the latest version in the repository.
- **Safe Update**: If a new version is found, it performs a `remove` -> `install` cycle.
  - This prevents "No space left on device" errors on devices with small flash storage.
  - Configuration files are preserved during this process.

---

## Manual Installation (Advanced)

If you prefer to configure it manually:

### For OpenWrt 25.12+ (Apk)
1. **Add Signature**:
   ```sh
   wget -q --no-check-certificate -O "/etc/apk/keys/myurar1a-repo.rsa.pub" "https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-lite/refs/heads/main/cert/apk_key.rsa.pub"
   ```

2. **Add Repository**:
   ```sh
   echo "https://myurar1a.github.io/openwrt-tailscale-lite" >> "/etc/apk/repositories.d/custom_tailscale.list"
   ```

3. **Install**:
   ```sh
   apk update
   apk add tailscale
   ```

### For OpenWrt 24.10- (Opkg)
1. **Add Signature**:
   ```sh
   wget -q --no-check-certificate -O "/tmp/usign_key.pub" "https://raw.githubusercontent.com/myurar1a/openwrt-tailscale-lite/refs/heads/main/cert/usign_key.pub"
   opkg-key add "/tmp/usign_key.pub"
   rm "/tmp/usign_key.pub"
   ```

2. **Add Repository**:
   ```sh
   echo "src/gz custom_tailscale https://myurar1a.github.io/openwrt-tailscale-lite/$(opkg print-architecture | awk 'END {print $2}')" >> /etc/opkg/customfeeds.conf
   ```

3. **Install**:
   ```sh
   opkg update
   opkg install tailscale
   ```

---

## References

This project is based on the following official documentation:

- **Tailscale Docs**: [Smaller binaries for embedded devices](https://tailscale.com/kb/1207/small-tailscale)
- **OpenWrt Wiki**: [Tailscale - Installation on storage constrained devices](https://openwrt.org/docs/guide-user/services/vpn/tailscale/start#installation_on_storage_constrained_devices)

## Disclaimer

This is an unofficial build. Use at your own risk.
Original software source code: [tailscale/tailscale](https://github.com/tailscale/tailscale)
