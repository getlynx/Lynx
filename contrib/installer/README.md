# Lynx Installer Scripts

This directory contains two scripts for deploying Lynx cryptocurrency nodes. Both scripts support an optional `--chain=<name>` parameter to target a specific chain's binaries from GitHub releases.

Documentation: https://docs.getlynx.io/

## Scripts

### install.sh

The node builder script. It automates the full lifecycle of a Lynx node on AMD and ARM-based systems — from initial setup to ongoing maintenance.

**What it does:**

- Installs system dependencies and configures the environment
- Downloads the correct pre-built Lynx binary from GitHub releases (matched by OS, version, and architecture)
- Creates systemd services for the Lynx daemon and a wallet backup timer
- Configures firewall rules and SSH security
- Monitors blockchain sync status and restarts the daemon as needed (good for low RAM deployments)
- Adds shell aliases and an informative MOTD with node statistics

**Usage:**

```bash
# One-line install (default Lynx chain)
bash <(curl -sL install.getlynx.io)
```
```bash
# Install a specific chain
bash <(curl -sL install.getlynx.io) --chain=mychain
```
```bash
# Update an existing node to the latest binary
bash <(curl -sL install.getlynx.io) update
```
```bash
# Update with a specific chain
bash <(curl -sL install.getlynx.io) update --chain=mychain
```

**Supported platforms:**

| OS Family | Distributions | Architectures |
|-----------|--------------|---------------|
| Debian | Debian, Ubuntu | AMD x86_64, ARM (aarch64) |
| RedHat | Rocky, AlmaLinux, CentOS, Fedora | AMD x86_64, ARM (aarch64) |

**Operation modes:**

| Mode | Trigger | Description |
|------|---------|-------------|
| Initial Setup | First run (no existing services) | Full installation of all components |
| Maintenance | Systemd timer (every 12 minutes) | Checks sync status, restarts daemon if needed |
| Update | `install.sh update` | Updates system packages and downloads the latest binary |

---

### iso-builder.sh

Creates a customized Raspberry Pi OS image with Lynx pre-installed. The resulting `.img.xz` file can be flashed to an SD card for a plug-and-play Lynx node.

**What it does:**

- Downloads the latest Raspberry Pi OS Lite 64-bit ARM image (or uses a provided URL)
- Mounts the image and injects an `rc.local` script
- On first boot, the Pi automatically downloads and runs `install.sh`
- Compresses the final image for distribution

**Usage:**

```bash
# Build with default chain (lynx) and latest Raspberry Pi OS
./iso-builder.sh

# Build with a specific chain
./iso-builder.sh --chain=mychain

# Build with a specific base image
./iso-builder.sh "https://downloads.raspberrypi.org/raspios_lite_arm64/images/..."

# Both options together
./iso-builder.sh --chain=mychain "https://downloads.raspberrypi.org/raspios_lite_arm64/images/..."
```

**Output:** `YYYY-MM-DD-<chain>-RPI-ISO.img.xz`

**Requirements:**

- Linux system (Debian/Ubuntu recommended)
- Root privileges
- At least 8GB free disk space
- Internet connection

---

## Differences Between the Scripts

| | install.sh | iso-builder.sh |
|---|-----------|---------------|
| **Purpose** | Installs and maintains a Lynx node | Builds a Raspberry Pi image that runs install.sh on first boot |
| **Runs on** | Any supported AMD or ARM system | Linux build machine (produces an image for Raspberry Pi) |
| **When to use** | Deploying a node on an existing server or device | Creating SD card images for Raspberry Pi distribution |
| **Chain default** | No default (matches all binaries if omitted) | Defaults to `lynx` |
| **Ongoing** | Yes — re-runs every 12 minutes via systemd timer | One-time build process |

## The --chain Parameter

Both scripts accept `--chain=<name>` to target a specific chain's binaries. The chain name is matched case-insensitively against binary filenames in the latest GitHub release.

- **install.sh**: If `--chain` is specified and no matching binary exists, the script exits gracefully with a message directing the user to the Lynx Discord server for assistance.
- **iso-builder.sh**: Defaults to `--chain=lynx` if not specified. The chain name is baked into the generated image so that `install.sh` receives it automatically on first boot.

If a binary for the specified chain has not been built and uploaded to the GitHub releases page, the installation will not proceed — no partial or broken state is left behind.

## Support

- Documentation: https://docs.getlynx.io/
- Discord: https://discord.gg/6jUaNeV2Uy
- Issues: https://github.com/getlynx/Lynx/issues
