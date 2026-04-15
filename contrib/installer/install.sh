#!/bin/bash

# Set strict PATH for security
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

set -euo pipefail

# Parse command-line arguments
chain_name=""
update_mode=""
rebuild_mode=""
for arg in "$@"; do
    case "$arg" in
        --chain=*) chain_name="${arg#--chain=}" ;;
        update)    update_mode="update" ;;
        rebuild)   rebuild_mode="rebuild" ;;
    esac
done

# Derive chain-specific names (default to lynx if no chain specified)
effective_chain_raw="${chain_name:-lynx}"
chain_lower=$(echo "$effective_chain_raw" | tr '[:upper:]' '[:lower:]')
effective_chain="$(echo "$chain_lower" | sed 's/./\U&/')"
daemon_name="${chain_lower}d"
cli_name="${chain_lower}-cli"
tx_name="${chain_lower}-tx"
service_name="${chain_lower}.service"
conf_name="${chain_lower}.conf"

# Base URL for fetching external helper scripts at runtime
SCRIPT_BASE_URL="https://raw.githubusercontent.com/getlynx/Lynx/main/contrib/installer"

# Set assumevalid flag only for the default chain
if [ "$chain_lower" = "lynx" ]; then
    assumevalid_flag=" -assumevalid=485bea987c62039d365a9458b6df2e3ef679054f2bd6e016877f783652912cfb"
else
    assumevalid_flag=""
fi

################################################################################
# LYNX SPARK INSTALLER
################################################################################
#
# PURPOSE:
#   Spark is a single-daemon deployment for the Lynx Data Storage Network.
#   This script automates the full lifecycle of a Spark on AMD and ARM-based
#   systems (Raspberry Pi, ARM64 servers, etc.) — from initial setup to
#   ongoing maintenance. Multiple chains can run in parallel on the same host.
#
#   Spark runs one daemon per chain. Use 'chain' (or 'c') to switch between
#   installed chains. For managing multiple daemons from a single console,
#   see Beacon (https://github.com/getlynx/Beacon).
#
# AUTHOR: Lynx Development Team
# VERSION: 4.0
# LAST UPDATED: 2026-04-01
# DOCUMENTATION: https://docs.getlynx.io/
#
################################################################################
#
# FUNCTIONALITY OVERVIEW:
#   This script performs the following operations in sequence:
#
#   1. SYSTEM SETUP:
#      - Creates systemd timer (install.timer) to run every 12 minutes
#      - Sets up 4GB swap file if current swap is less than 3GB
#      - Installs respective daemon ARM/AMD binaries if not present
#      - Creates systemd service ({chain}.service) for the daemon
#      - Creates wallet backup service running every 60 minutes
#      - Configures firewall rules and SSH security settings
#
#   2. SPARK CONSOLE:
#      - Adds convenient aliases to ~/.bashrc for common operations
#      - Displays real-time daemon statistics on login
#      - Shows staking performance metrics from wallet RPC
#      - Displays 24-hour and 7-day yield rates based on network block time
#      - Tracks immature stake rewards awaiting maturity
#      - Provides quick access to wallet commands, system monitoring, and logs
#
#   3. DAEMON MAINTENANCE:
#      - Ensures daemon is running
#      - Monitors blockchain synchronization status
#      - Automatically restarts daemon during sync
#      - Disables timer once sync is complete
#
#   4. ENHANCED FEATURES:
#      - Smart OS detection with consolidated logic (Debian/RedHat families)
#      - OS-specific service management (sshd vs ssh)
#      - Intelligent locale configuration (skips if already configured)
#      - Robust error handling and logging
#      - Efficient package management and system updates
#      - SSH port management with OS-aware restart commands
#
################################################################################
#
# SPARK CONSOLE COMMANDS (type 'h' to see all):
#   WALLET COMMANDS:
#     gba    - Get wallet balances
#     gna    - Generate new address
#     lag    - List address groupings
#     sta    - Send to address (sender pays the fee)
#     swe    - Sweep a wallet (send all funds, recipient pays fee)
#     bac    - Manual wallet backup
#     lba    - List backup directory contents
#     wdi    - Change to daemon working directory
#
#   DAEMON COMMANDS:
#     lyv    - Show daemon version
#     lyc    - View/edit daemon config file (-e to edit)
#     lyl    - View daemon debug log (default 30 lines, -f for follow)
#     lyr    - Restart daemon (-d to purge debug log)
#     gbi    - Get blockchain info
#     hel    - Show daemon help (with keyword search)
#
#   SYSTEM COMMANDS:
#     lss    - Check daemon service status
#     jou    - View install logs (default 30 lines, -f for follow)
#     upd    - Install or update daemon to latest release
#     reb    - Update services, timers, firewall, and aliases
#     usp    - Change SSH port
#     ipt    - List iptables rules (verbose)
#
#   USEFUL COMMANDS:
#     h      - Show Spark console and daemon statistics
#     htop   - Monitor system resources
#
#   HIDDEN/ADVANCED COMMANDS:
#     fire   - Edit firewall script
#     shh    - Edit SSH authorized keys
#     pas    - Toggle password authentication (on/off)
#
################################################################################
#
# SYSTEM REQUIREMENTS:
#   - AMD or ARM architecture (aarch64 or arm*)
#   - Debian/Ubuntu-based or RHEL system (Rocky, AlmaLinux, CentOS, Fedora)
#   - Root privileges
#   - Internet connection
#   - curl
#   - Minimum 4GB RAM recommended
#
# DEPENDENCIES (installed automatically):
#   - systemd
#   - curl, unzip, nano, htop, iptables
#   - fallocate, mkswap, swapon
#   - systemd-cat (for system logging)
#   - awk (for JSON parsing - no jq required)
#
################################################################################
#
# INSTALLATION:
#   Install a new Spark (default Lynx chain):
#   bash <(curl -sL install.getlynx.io)
#
#   Install a Spark for a specific chain:
#   bash <(curl -sL install.getlynx.io) --chain=mychain
#
#   Update an existing Spark daemon:
#   bash <(curl -sL install.getlynx.io) update
#
#   Rebuild Spark (update services, timers, firewall, aliases):
#   reb
#
################################################################################
#
# OPERATION MODES:
#   - INITIAL SETUP: Creates all necessary files and services
#   - MAINTENANCE: Runs every 12 minutes via systemd timer
#   - SYNC MONITORING: Checks blockchain sync status and manages daemon
#   - UPDATE: Updates daemon to latest release (use 'update' argument)
#   - REBUILD: Updates services, timers, and aliases (use 'rebuild' argument)
#   - CHAIN FILTER: Specify --chain=<name> to download binaries for a specific
#     chain. If no binary matches, the script exits gracefully.
#
# LOGGING:
#   - All operations are logged to systemd journal
#   - View logs: journalctl -t install.sh -f
#   - Logging is reduced after 6 hours of uptime to prevent spam
#
################################################################################
#
# SECURITY FEATURES:
#   - All file operations use proper permissions
#   - Systemd services run with appropriate security contexts
#   - Swap file has restricted permissions (600)
#   - Strict bash settings (set -euo pipefail)
#   - Firewall configuration with iptables
#   - Boot firewall secures SSH while daemon starts
#   - SSH security hardening options
#   - Password authentication toggle functionality
#
################################################################################
#
# TROUBLESHOOTING:
#   - Check service status: lss (or systemctl status lynx)
#   - View debug logs: lyl -f (or tail -f $WorkingDirectory/debug.log)
#   - Check install logs: jou -f (or journalctl -t install.sh -f)
#   - Restart daemon: lyr (or systemctl restart lynx)
#   - Manual sync check: gbi (or lynx-cli getblockchaininfo)
#   - Check firewall rules: ipt (or iptables -L -vn)
#   - View SSH config: shh (or nano /root/.ssh/authorized_keys)
#
################################################################################
#
# NETWORK PORTS:
#   - Daemon P2P port: 22566 (configurable in lynx.conf)
#   - RPC port: 8332 (configurable in lynx.conf)
#   - SSH port: configurable via usp command (default varies by system)
#
# FILES CREATED:
#   - /etc/systemd/system/{chain}-install.service
#   - /etc/systemd/system/{chain}-install.timer
#   - /etc/systemd/system/lynx.service
#   - /etc/systemd/system/lynx-wallet-backup.service
#   - /etc/systemd/system/lynx-wallet-backup.timer
#   - /etc/systemd/system/lynx-patch-firewall.service
#   - /etc/systemd/system/lynx-patch-firewall.timer
#   - /usr/local/bin/{chain}-backup.sh
#   - /usr/local/bin/chain (chain selector)
#   - /usr/local/bin/c (symlink to chain)
#   - /usr/local/bin/spark-current-chain.sh (sourced helper)
#   - /etc/spark/chains.conf (chain registry)
#   - /run/spark/current-chain (current selection, tmpfs)
#   - /swapfile (if needed)
#   - ~/.bashrc (Spark console aliases)
#
################################################################################
#
# DATA DIRECTORY SETUP
#
# PURPOSE:
#   Ensures the Lynx data directory exists with proper permissions and creates
#   a symbolic link for backward compatibility with legacy configurations.
#
# OPERATIONS:
#   - Creates $WorkingDirectory directory if it doesn't exist
#   - Sets proper ownership (root:root) and permissions (755)
#   - Creates symlink /root/.lynx -> $WorkingDirectory for compatibility
#
################################################################################

# Journal logging function using systemd-cat
log() {
    echo "$1" | systemd-cat -t install.sh 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] install.sh: $1" >&2
}

# Check if running as root
isRootUser() {
    if [ "$EUID" -ne 0 ]; then
        log "This script must be run as root. Please use sudo or run as root user."
        exit 1
    fi
}

# Set the timezone to America/New_York
setTimeZone() {
    local tz="America/New_York"
    log "Setting system timezone to $tz"
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone "$tz" || log "Failed to set system timezone with timedatectl"
        log "System timezone set to $tz"
    else
        # Fallback for older systems: symlink /etc/localtime
        if [ -f "/usr/share/zoneinfo/$tz" ]; then
            ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime || log "Failed to symlink /etc/localtime to $tz"
            log "System timezone set to $tz (via /etc/localtime symlink)"
        else
            log "Timezone file for $tz not found. Please set timezone manually."
        fi
    fi
}

# Update and upgrade system packages, install required tools
packageInstallAndUpdate() {
    if [ "$os_family" = "debian" ]; then
        log "Updating package lists and upgrading Debian/Ubuntu system..."
        apt-get update -y >/dev/null 2>&1 || log "Failed to update package lists"
        log "Upgrading installed packages..."
        apt-get upgrade -y >/dev/null 2>&1 || log "Failed to upgrade packages"
        log "Performing distribution upgrade..."
        apt-get dist-upgrade -y >/dev/null 2>&1 || log "Failed to perform distribution upgrade"
        log "Installing required packages (unzip, nano, htop, iptables, curl)..."
        apt-get install -y unzip nano htop iptables curl >/dev/null 2>&1 || log "Failed to install required packages"
    elif [ "$os_family" = "redhat" ]; then
        log "Updating RedHat/Rocky/AlmaLinux system..."
        if command -v dnf >/dev/null 2>&1; then
            log "Refreshing package cache with dnf..."
            dnf makecache -y >/dev/null 2>&1 || log "Failed to refresh package cache"
            log "Upgrading packages with dnf..."
            dnf upgrade -y >/dev/null 2>&1 || log "Failed to upgrade packages"
            log "Installing EPEL repository for htop..."
            dnf install -y epel-release >/dev/null 2>&1 || log "Failed to install epel-release"
            log "Installing required packages with dnf (unzip, nano, htop, iptables, curl)..."
            dnf install -y unzip nano htop iptables curl >/dev/null 2>&1 || log "Failed to install required packages"
        else
            log "Refreshing package cache with yum..."
            yum makecache -y >/dev/null 2>&1 || log "Failed to refresh package cache"
            log "Upgrading packages with yum..."
            yum upgrade -y >/dev/null 2>&1 || log "Failed to upgrade packages"
            log "Installing EPEL repository for htop..."
            yum install -y epel-release >/dev/null 2>&1 || log "Failed to install epel-release"
            log "Installing required packages with yum (unzip, nano, htop, iptables, curl)..."
            yum install -y unzip nano htop iptables curl >/dev/null 2>&1 || log "Failed to install required packages"
        fi
    else
        log "Unsupported OS family: $os_family"
    fi
    log "System update completed successfully"
}

# Set the working directory variable for use throughout the script
WorkingDirectory=/var/lib/${chain_lower}

# Derive a unique loopback IP for this chain's RPC (range 127.0.0.2-254, reserving .1 for system)
rpc_octet=$(printf '%s' "$chain_lower" | cksum | awk '{print ($1 % 253) + 2}')

# Collision guard: scan existing chain conf files for rpcbind= and bump if taken
# by a different chain. Retry up to 253 times (full range).
_collision_tries=0
while [ "$_collision_tries" -lt 253 ]; do
    _taken_by=""
    for _conf_file in /var/lib/*/[a-z]*.conf; do
        [ -f "$_conf_file" ] || continue
        if grep -q "^rpcbind=127\\.0\\.0\\.${rpc_octet}$" "$_conf_file" 2>/dev/null; then
            # Extract chain name from path: /var/lib/<chain>/<chain>.conf
            _conf_chain=$(basename "$(dirname "$_conf_file")")
            if [ "$_conf_chain" != "$chain_lower" ]; then
                _taken_by="$_conf_chain"
                break
            fi
        fi
    done
    if [ -z "$_taken_by" ]; then
        break
    fi
    log "RPC octet $rpc_octet already used by $_taken_by — incrementing."
    rpc_octet=$(( (rpc_octet % 253) + 2 ))
    _collision_tries=$(( _collision_tries + 1 ))
done
unset _collision_tries _taken_by _conf_file _conf_chain

rpc_host="127.0.0.${rpc_octet}"
cli_flags="-datadir=$WorkingDirectory -rpcconnect=$rpc_host"

echo "Please wait while the script runs..."

# Create the data directory with proper permissions
mkdir -p $WorkingDirectory
chown root:root $WorkingDirectory
chmod 755 $WorkingDirectory

# Create symbolic link for backward compatibility with legacy configurations
if [ ! -e /root/.${chain_lower} ]; then
    ln -sf $WorkingDirectory /root/.${chain_lower}
fi

# Get system uptime in seconds for conditional logging
uptime_seconds=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)
# Threshold for conditional logging (6 hours = 21600 seconds)
log_threshold_seconds=21600

# Create a nicely formatted command list bashrc file
createCommandListConsole() {
    local chain_upper=$(echo "${effective_chain}" | tr '[:lower:]' '[:upper:]')
    cat <<'CMDEOF' | sed "s|WorkingDirectory=/var/lib/lynx|WorkingDirectory=${WorkingDirectory}|g; s|lynx-cli|${cli_name} ${cli_flags}|g; s|lynx\.conf|${conf_name}|g" | sed "/http/!{ s|LYNX|${chain_upper}|g; s|Lynx|${effective_chain}|g; }" | sed "s|ORIGINALCHAIN|Lynx|g; s|originalchain|lynx|g"
# Function to display Lynx aliases in a nicely formatted MOTD
executeHelpCommand() {
    echo ""
    echo ""
    WorkingDirectory=/var/lib/lynx
    # Count stakes won in the last 24 hours using wallet RPC
    # Get timestamp from 24 hours ago
    since_timestamp=$(date -d '24 hours ago' +%s)


    # Count stakes from debug.log file for last 24 hours
    # Get cutoff time in ISO format (YYYY-MM-DDTHH:MM:SSZ)
    since_iso=$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)

    # Count CheckStake entries in debug.log from last 24 hours
    # Uses grep to find stake entries, then awk to filter by timestamp
    stakes_won=$(grep "CheckStake(): New proof-of-stake block found" "$WorkingDirectory/debug.log" 2>/dev/null | awk -v cutoff="$since_iso" '
        {
            # Extract timestamp from beginning of line (format: YYYY-MM-DDTHH:MM:SSZ)
            timestamp = substr($0, 1, 20) "Z"
            if (timestamp >= cutoff) {
                count++
            }
        }
        END { print count+0 }')

    # Default to 0 if command fails or returns empty
    if [ -z "$stakes_won" ] || [ "$stakes_won" = "" ]; then
        stakes_won="0"
    fi

    # Calculate total blocks in last 24 hours based on average block time
    # Lynx has a 5-minute (300 second) average block time
    # 24 hours = 1440 minutes / 5 minutes per block = 288 blocks
    total_blocks=288

    # Calculate percent yield (stakes won / total blocks * 100)
    if [ "$total_blocks" -gt 0 ]; then
        # Use awk for floating point arithmetic with 3 decimal places
        percent_yield=$(awk "BEGIN {printf \"%.3f\", $stakes_won * 100 / $total_blocks}" 2>/dev/null || echo "0.000")
    else
        percent_yield="0.000"
    fi

    # Count stakes won in the last 7 days using debug.log
    # Get cutoff time in ISO format (YYYY-MM-DDTHH:MM:SSZ) for 7 days ago
    since_iso_7d=$(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ)

    # Count CheckStake entries in debug.log from last 7 days
    # Uses grep to find stake entries, then awk to filter by timestamp
    stakes_won_7d=$(grep "CheckStake(): New proof-of-stake block found" "$WorkingDirectory/debug.log" 2>/dev/null | awk -v cutoff="$since_iso_7d" '
        {
            # Extract timestamp from beginning of line (format: YYYY-MM-DDTHH:MM:SSZ)
            timestamp = substr($0, 1, 20) "Z"
            if (timestamp >= cutoff) {
                count++
            }
        }
        END { print count+0 }')

    # Default to 0 if command fails or returns empty
    if [ -z "$stakes_won_7d" ] || [ "$stakes_won_7d" = "" ]; then
        stakes_won_7d="0"
    fi

    # Calculate total blocks in last 7 days based on average block time
    # Lynx has a 5-minute (300 second) average block time
    # 7 days = 10080 minutes / 5 minutes per block = 2016 blocks
    total_blocks_7d=2016

    # Calculate percent yield for 7 days (stakes won / total blocks * 100)
    if [ "$total_blocks_7d" -gt 0 ]; then
        # Use awk for floating point arithmetic with 3 decimal places
        percent_yield_7d=$(awk "BEGIN {printf \"%.3f\", $stakes_won_7d * 100 / $total_blocks_7d}" 2>/dev/null || echo "0.000")
    else
        percent_yield_7d="0.000"
    fi

    # Count immature UTXOs (confirmations < 31 from unspent outputs)
    # Using listunspent to identify UTXO that are still maturing
    immature_utxos=$(lynx-cli listunspent 2>/dev/null | awk '/"confirmations":/ {gsub(/[^0-9]/, "", $2); conf = $2 + 0; if (conf < 31 && conf > 0) count++} END {print count+0}')
    if [ -z "$immature_utxos" ] || [ "$immature_utxos" = "" ]; then
        immature_utxos="0"
    fi

    # Get current wallet balance
    wallet_balance=$(lynx-cli getbalance 2>/dev/null || echo "0")
    if [ -z "$wallet_balance" ]; then
        wallet_balance="0"
    fi

    # Get Lynx version for display
    lynx_version=$(lynx-cli -version 2>/dev/null | head -1 || echo "Unknown")
    if [ -z "$lynx_version" ]; then
        lynx_version="Unknown"
    fi

    local title="Lynx Spark for the ORIGINALCHAIN Data Storage Network"
    local width=64
    local pad=$(( (width - ${#title}) / 2 ))
    printf "%*s%s\n" "$pad" "" "$title"
    echo ""
    echo "  NODE STATUS:"
    echo "    🎯 Stakes won in last 24 hours: $stakes_won"
    echo "    📊 24-hour yield rate (stakes/blocks): ${percent_yield}%"
    echo "    🎯 Stakes won in last 7 days: $stakes_won_7d"
    echo "    📊 7-day yield rate (stakes/blocks): ${percent_yield_7d}%"
    echo "    🔄 Immature transactions (< 31 confirmations): $immature_utxos"
    echo "    💰 Current wallet balance: $wallet_balance"
    echo ""
    echo "  DAEMON COMMANDS:"
    echo "    lyl [lines] [-f]       - View daemon debug log (default 30)"
    echo "    lyv                    - Show daemon version"
    echo "    lyr [-d]               - Restart daemon (-d to purge debug)"
    echo "    lyc [-e]               - View/edit daemon conf (-e to edit)"
    echo "    gbi                    - Get blockchain info"
    echo "    hel [keyword]          - Show daemon help (keyword search)"
    echo ""
    echo "  WALLET COMMANDS:"
    echo "    gba                    - Get wallet balances"
    echo "    gna                    - Generate new address"
    echo "    lag                    - List address groupings"
    echo "    sta [address] [amount] - Send to address (sender pays fee)"
    echo "    swe [address]          - Sweep a wallet (receiver pays fee)"
    echo "    bac                    - Manual wallet backup"
    echo "    lba                    - List backup directory contents"
    echo "    pri                    - Show wallet value in USD"
    echo ""
    echo "  SYSTEM COMMANDS:"
    echo "    lss                    - Check systemd service status"
    echo "    jou [lines] [-f]       - View install logs (default 30)"
    echo "    upd                    - Install or update daemon to latest release"
    echo "    reb                    - Update services, timers, firewall, and aliases"
    echo "    usp [port]             - Change SSH port"
    echo "    wdi                    - Change to daemon working directory"
    echo "    ipt                    - List iptables rules"
    echo ""
    echo "  USEFUL COMMANDS:"
    echo "    htop                   - Monitor system resources"
    echo "    h                      - Show this help message again"
    echo ""
    echo "  📚 Complete project documentation: https://docs.getlynx.io/"
    echo "  💾 Store files permanently: https://clevver.org/"
    echo "  🔍 Blockchain explorer: https://explorer.getlynx.io/"
    echo "  📈 Trade Lynx: https://freixlite.com/market/LYNX/LTC"
    echo "  🔢 Lynx Version: $lynx_version"
    echo ""
    echo ""
}

# Function to display wallet value and LYNX price information
executePriceCommand() {
    echo ""
    WorkingDirectory=/var/lib/lynx

    # Get current wallet balance
    wallet_balance=$(lynx-cli getbalance 2>/dev/null || echo "0")
    if [ -z "$wallet_balance" ]; then
        wallet_balance="0"
    fi

    # Fetch LYNX price from API with random endpoint selection and fallback
    price_usd=""
    api_endpoints=(
        "https://api-one.ewm-cx.info/api/v1/price/getPriceByCoin?symbol=LYNX"
        "https://api-two.ewm-cx.net/api/v1/price/getPriceByCoin?symbol=LYNX"
    )

    # Randomly select which endpoint to try first (0 or 1)
    first_index=$((RANDOM % 2))
    second_index=$((1 - first_index))

    # Try the randomly selected endpoint first
    api_response=$(curl -s --max-time 3 "${api_endpoints[$first_index]}" 2>/dev/null)
    if [ -n "$api_response" ]; then
        # Extract priceUSD from JSON using awk (no jq dependency)
        extracted_price=$(echo "$api_response" | awk -F'"priceUSD":"' '{print $2}' | awk -F'"' '{print $1}')
        # Only use the extracted price if it's not empty
        if [ -n "$extracted_price" ] && [ "$extracted_price" != "" ]; then
            price_usd="$extracted_price"
        fi
    fi

    # If first endpoint failed or returned invalid price, try the backup endpoint
    if [ -z "$price_usd" ] || [ "$price_usd" = "" ]; then
        api_response=$(curl -s --max-time 3 "${api_endpoints[$second_index]}" 2>/dev/null)
        if [ -n "$api_response" ]; then
            # Extract priceUSD from JSON using awk (no jq dependency)
            extracted_price=$(echo "$api_response" | awk -F'"priceUSD":"' '{print $2}' | awk -F'"' '{print $1}')
            # Only use the extracted price if it's not empty
            if [ -n "$extracted_price" ] && [ "$extracted_price" != "" ]; then
                price_usd="$extracted_price"
            fi
        fi
    fi

    # Default to 0 if both endpoints failed
    if [ -z "$price_usd" ] || [ "$price_usd" = "" ]; then
        price_usd="0.00000000"
    fi

    # Count stakes won in the last 24 hours
    # Gracefully handle missing debug.log or no staking data
    since_iso=$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    if [ -f "$WorkingDirectory/debug.log" ]; then
        stakes_won_24h=$(grep "CheckStake(): New proof-of-stake block found" "$WorkingDirectory/debug.log" 2>/dev/null | awk -v cutoff="$since_iso" '
            {
                # Extract timestamp from beginning of line (format: YYYY-MM-DDTHH:MM:SSZ)
                timestamp = substr($0, 1, 20) "Z"
                if (timestamp >= cutoff) {
                    count++
                }
            }
            END { print count+0 }')
    else
        stakes_won_24h="0"
    fi
    # Ensure we have a valid number (default to 0 if empty or invalid)
    if [ -z "$stakes_won_24h" ] || [ "$stakes_won_24h" = "" ] || ! [[ "$stakes_won_24h" =~ ^[0-9]+$ ]]; then
        stakes_won_24h="0"
    fi

    # Count stakes won in the last 7 days
    # Gracefully handle missing debug.log or no staking data
    since_iso_7d=$(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    if [ -f "$WorkingDirectory/debug.log" ]; then
        stakes_won_7d=$(grep "CheckStake(): New proof-of-stake block found" "$WorkingDirectory/debug.log" 2>/dev/null | awk -v cutoff="$since_iso_7d" '
            {
                # Extract timestamp from beginning of line (format: YYYY-MM-DDTHH:MM:SSZ)
                timestamp = substr($0, 1, 20) "Z"
                if (timestamp >= cutoff) {
                    count++
                }
            }
            END { print count+0 }')
    else
        stakes_won_7d="0"
    fi
    # Ensure we have a valid number (default to 0 if empty or invalid)
    if [ -z "$stakes_won_7d" ] || [ "$stakes_won_7d" = "" ] || ! [[ "$stakes_won_7d" =~ ^[0-9]+$ ]]; then
        stakes_won_7d="0"
    fi

    # Function to format USD with 2 decimals and comma separators
    format_usd() {
        local value=$1
        # Format to 2 decimal places first
        local formatted=$(awk "BEGIN {printf \"%.2f\", $value}" 2>/dev/null || echo "0.00")
        # Split into integer and decimal parts
        local int_part=$(echo "$formatted" | cut -d. -f1)
        local dec_part=$(echo "$formatted" | cut -d. -f2)
        # Add comma separators to integer part only
        local int_with_commas=$(echo "$int_part" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta')
        # Combine integer and decimal parts
        echo "${int_with_commas}.${dec_part}"
    }

    # Calculate wallet value in USD
    wallet_value_raw=$(awk "BEGIN {printf \"%.2f\", $wallet_balance * $price_usd}" 2>/dev/null || echo "0.00")
    wallet_value_usd=$(format_usd "$wallet_value_raw")

    # Calculate staking yield in USD (each stake = 1 LYNX)
    staking_yield_24h_raw=$(awk "BEGIN {printf \"%.2f\", $stakes_won_24h * $price_usd}" 2>/dev/null || echo "0.00")
    staking_yield_24h_usd=$(format_usd "$staking_yield_24h_raw")

    staking_yield_7d_raw=$(awk "BEGIN {printf \"%.2f\", $stakes_won_7d * $price_usd}" 2>/dev/null || echo "0.00")
    staking_yield_7d_usd=$(format_usd "$staking_yield_7d_raw")

    # Calculate estimated monthly yield (7-day * 4)
    # Ensure safe arithmetic by defaulting to 0 if calculation fails
    estimated_monthly_stakes=$((stakes_won_7d * 4)) 2>/dev/null || estimated_monthly_stakes=0
    staking_yield_monthly_raw=$(awk "BEGIN {printf \"%.2f\", $staking_yield_7d_raw * 4}" 2>/dev/null || echo "0.00")
    staking_yield_monthly_usd=$(format_usd "$staking_yield_monthly_raw")

    # Calculate prices for different LYNX amounts
    price_1_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 1 * $price_usd}" 2>/dev/null || echo "0.00")
    price_1_lynx=$(format_usd "$price_1_lynx_raw")

    price_10_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 10 * $price_usd}" 2>/dev/null || echo "0.00")
    price_10_lynx=$(format_usd "$price_10_lynx_raw")

    price_100_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 100 * $price_usd}" 2>/dev/null || echo "0.00")
    price_100_lynx=$(format_usd "$price_100_lynx_raw")

    price_1000_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 1000 * $price_usd}" 2>/dev/null || echo "0.00")
    price_1000_lynx=$(format_usd "$price_1000_lynx_raw")

    price_10000_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 10000 * $price_usd}" 2>/dev/null || echo "0.00")
    price_10000_lynx=$(format_usd "$price_10000_lynx_raw")

    price_100000_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 100000 * $price_usd}" 2>/dev/null || echo "0.00")
    price_100000_lynx=$(format_usd "$price_100000_lynx_raw")

    price_1000000_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 1000000 * $price_usd}" 2>/dev/null || echo "0.00")
    price_1000000_lynx=$(format_usd "$price_1000000_lynx_raw")

    price_10000000_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 10000000 * $price_usd}" 2>/dev/null || echo "0.00")
    price_10000000_lynx=$(format_usd "$price_10000000_lynx_raw")

    price_100000000_lynx_raw=$(awk "BEGIN {printf \"%.2f\", 100000000 * $price_usd}" 2>/dev/null || echo "0.00")
    price_100000000_lynx=$(format_usd "$price_100000000_lynx_raw")

    echo "  PRICE INFORMATION:"
    echo "    💵 Wallet value (USD): \$$wallet_value_usd"
    echo ""
    echo "    🎯 Staking Yield (USD):"
    echo "        24-hour yield:     \$$staking_yield_24h_usd ($stakes_won_24h stakes)"
    echo "        7-day yield:       \$$staking_yield_7d_usd ($stakes_won_7d stakes)"
    echo "        Estimated monthly: \$$staking_yield_monthly_usd (~$estimated_monthly_stakes stakes)"
    echo ""
    echo "    💲 LYNX Price List (USD):"
    echo "        1 LYNX:            \$$price_1_lynx"
    echo "        10 LYNX:           \$$price_10_lynx"
    echo "        100 LYNX:          \$$price_100_lynx"
    echo "        1,000 LYNX:        \$$price_1000_lynx"
    echo "        10,000 LYNX:       \$$price_10000_lynx"
    echo "        100,000 LYNX:      \$$price_100000_lynx"
    echo "        1,000,000 LYNX:    \$$price_1000000_lynx"
    echo "        10,000,000 LYNX:   \$$price_10000000_lynx"
    echo "        100,000,000 LYNX:  \$$price_100000000_lynx"
    echo ""
}

# Function to update SSH port
update_ssh_port() { 
    if [ -z "$1" ]; then 
        # Display current SSH port
        local current_port
        current_port=$(grep "^#*Port" /etc/ssh/sshd_config | head -1 | sed 's/^#*Port[[:space:]]*//')
        if [ -z "$current_port" ]; then
            current_port="22"
        fi
        echo "Current SSH port: $current_port"
        echo ""
        echo "Usage: usp <new_port>"
        echo "Example: usp 2222"
        return 0
    fi
    #
    local new_port="$1"
    local current_port
    #
    # Validate port number
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo "ERROR: Invalid port number. Must be between 1 and 65535."
        return 1
    fi
    #
    # Check for port conflicts in firewall script
    local existing_ports
    existing_ports=$(grep -o "dport [0-9]*" /usr/local/bin/firewall.sh | grep -o "[0-9]*" | sort -u)
    #
    if echo "$existing_ports" | grep -q "^${new_port}$"; then
        echo "ERROR: Port $new_port is already in use in the firewall configuration."
        echo "Current ports in firewall: $existing_ports"
        echo "Please choose a different port number."
        return 1
    fi
    #
    # Get current SSH port
    current_port=$(grep "^#*Port" /etc/ssh/sshd_config | head -1 | sed 's/^#*Port[[:space:]]*//')
    if [ -z "$current_port" ]; then
        current_port="22"
    fi
    #
    echo "Current SSH port: $current_port"
    echo "New SSH port: $new_port"
    echo ""
    echo "WARNING: This will change the SSH port and reboot the device!"
    echo ""
    read -p "Do you want to continue? (y/N): " confirm
    #
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        return 1
    fi
    #
    echo "Updating sshd_config..."
    sed -i "s/^#*Port.*/Port $new_port/" /etc/ssh/sshd_config
    #
    echo "Updating firewall script..."
    sed -i "/# SSH_PORT_START/,/# SSH_PORT_END/s/iptables -A INPUT -p tcp --dport [0-9]* -j ACCEPT/iptables -A INPUT -p tcp --dport $new_port -j ACCEPT/" /usr/local/bin/firewall.sh
    #
    echo "Applying firewall rules..."
    /usr/local/bin/firewall.sh
    sleep 2
    /usr/local/bin/firewall.sh
    #
    echo "Restarting SSH daemon..."
    # Fallback: try both service names
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        echo "SSH daemon restarted successfully"
    else
        echo "ERROR: Failed to restart SSH daemon"
        return 1
    fi
    #
    echo ""
    echo "SSH port updated successfully to $new_port"
    echo "Connect to the new port: ssh -p $new_port root@$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
}
CMDEOF
}

# Add useful aliases and MOTD to /root/.bashrc
# Uses a single shared block that sources the chain-selector helper.
# Aliases reference $SPARK_* vars so they work for whichever chain is selected.
# The block is idempotent: written once and left alone on subsequent installs.
addAliasesToBashrcFile() {
    local BASHRC="/root/.bashrc"
    local BLOCK_START="# BEGIN spark-aliases"
    local BLOCK_END="# END spark-aliases"

    # Remove any legacy alias block to avoid duplicates
    local LEGACY_START="# === LYNX ALIASES START ==="
    local LEGACY_END="# === LYNX ALIASES END ==="
    if [ -f "$BASHRC" ] && grep -q "$LEGACY_START" "$BASHRC"; then
        sed -i "/$LEGACY_START/,/$LEGACY_END/d" "$BASHRC"
    fi

    # Remove any existing spark-aliases block to update it
    if [ -f "$BASHRC" ] && grep -q "$BLOCK_START" "$BASHRC"; then
        sed -i "/$BLOCK_START/,/$BLOCK_END/d" "$BASHRC"
    fi

    # Write the single shared alias block
    cat <<'SPARKEOF' >> "$BASHRC"
# BEGIN spark-aliases
#
# Bail out immediately for non-interactive shells (SFTP, scp, rsync, etc.)
case $- in
    *i*) ;;
    *) return ;;
esac
#
# Source the chain-selector helper to set SPARK_* variables
if [ -f /usr/local/bin/spark-current-chain.sh ]; then
    . /usr/local/bin/spark-current-chain.sh
fi
#
# Wrapper functions for chain/c so the current shell picks up the new SPARK_* vars
# (The script at /usr/local/bin/chain writes the file; we re-source to update env.)
chain() { /usr/local/bin/chain "$@"; . /usr/local/bin/spark-current-chain.sh; }
c()     { /usr/local/bin/chain "$@"; . /usr/local/bin/spark-current-chain.sh; }
#
# Helper: ensure a chain is selected before running an alias
_spark_require_chain() {
    if [ -z "${SPARK_CHAIN:-}" ]; then
        echo "No chain selected. Run 'chain' or 'c' to pick one."
        return 1
    fi
    return 0
}
#
# WALLET COMMANDS
gba() { _spark_require_chain && $SPARK_CLI getbalances; }
gb() { gba; }
gna() { _spark_require_chain && $SPARK_CLI getnewaddress; }
gn() { gna; }
lag() { _spark_require_chain && $SPARK_CLI listaddressgroupings; }
la() { lag; }
sta() { _spark_require_chain && $SPARK_CLI sendtoaddress "$1" "$2"; }
sa() { sta "$@"; }
swe() { _spark_require_chain && $SPARK_CLI sendtoaddress "$1" "$($SPARK_CLI getbalance)" "" "" true; }
sw() { swe "$@"; }
ca() { _spark_require_chain && $SPARK_CLI capacity; }
bac() { _spark_require_chain && /usr/local/bin/${SPARK_CHAIN}-backup.sh; }
lba() { _spark_require_chain && cd /var/lib/${SPARK_CHAIN}-backup && ls -lh; }
#
# DAEMON COMMANDS
lyv() { _spark_require_chain && $SPARK_CLI -version; }
lv() { lyv; }
gbi() { _spark_require_chain && $SPARK_CLI getblockchaininfo; }
gi() { gbi; }
lyl() { _spark_require_chain || return 1; if [ "$1" = "-f" ]; then tail -f "$SPARK_DATADIR/debug.log"; elif [ "${2:-}" = "-f" ]; then tail -n ${1:-30} -f "$SPARK_DATADIR/debug.log"; else tail -n ${1:-30} "$SPARK_DATADIR/debug.log"; fi; }
lyc() { _spark_require_chain || return 1; if [ "$1" = "-e" ]; then nano "$SPARK_CONF" && read -p "Restart daemon to apply config changes? (y/N): " confirm && if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then lyr; else echo "Daemon not restarted."; fi; else cat "$SPARK_CONF"; fi; }
lc() { lyc "$@"; }
lyr() { _spark_require_chain || return 1; if [ "$1" = "-d" ]; then echo "If you delete the debug log, the Staking results in Node Status will reset."; read -p "Do you want to continue? (y/N): " confirm; if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then systemctl stop $SPARK_CHAIN && rm -rf "$SPARK_DATADIR/debug.log" && systemctl start $SPARK_CHAIN; else echo "Operation cancelled."; fi; else systemctl restart $SPARK_CHAIN; fi; }
lr() { lyr "$@"; }
hel() { _spark_require_chain || return 1; if [ -n "$1" ]; then $SPARK_CLI help | grep -i "$1"; else $SPARK_CLI help; fi; }
he() { hel "$@"; }
lss() { _spark_require_chain && systemctl status $SPARK_CHAIN; }
nss() { systemctl status nginx; }
#
# DIRECTORY COMMANDS
wdi() { _spark_require_chain && cd $SPARK_DATADIR && ls -lh; }
wd() { wdi; }
#
# SYSTEM COMMANDS
ipt() { iptables -L -vn; }
fire() { nano /usr/local/bin/firewall.sh && echo "Applying firewall changes..." && read -p "Execute firewall script to apply changes? (y/N): " confirm && if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then /usr/local/bin/firewall.sh && echo "Firewall rules updated successfully!"; else echo "Firewall script not executed."; fi; }
usp() { update_ssh_port "$1"; }
jou() { if [ "$1" = "-f" ]; then journalctl -t install.sh -f; elif [ "${2:-}" = "-f" ]; then journalctl -t install.sh -n ${1:-30} -f; else journalctl -t install.sh -n ${1:-30}; fi; }
jo() { jou "$@"; }
shh() { nano /root/.ssh/authorized_keys && read -p "Restart SSH daemon to apply changes? (y/N): " confirm && if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null && echo "SSH daemon restarted successfully"; else echo "SSH daemon not restarted. Changes will take effect after manual restart."; fi; }
pas() { local ssh_config="/etc/ssh/sshd_config"; local new_setting; if [ "$1" = "off" ]; then if grep -v "^#" /root/.ssh/authorized_keys | grep -q "ssh-"; then new_setting="PasswordAuthentication no"; else echo "ERROR: Cannot disable password auth - no authorized keys found"; return 1; fi; elif [ "$1" = "on" ]; then new_setting="PasswordAuthentication yes"; else grep "^#*PasswordAuthentication" "$ssh_config"; return 0; fi; sed -i '/^#*PasswordAuthentication/d' "$ssh_config"; echo "$new_setting" >> "$ssh_config"; if [ "$1" = "off" ]; then echo "Password authentication disabled"; else echo "Password authentication enabled"; fi; systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; }
upd() { _spark_require_chain && bash <(curl -sL install.getlynx.io) --chain=$SPARK_CHAIN; }
reb() { _spark_require_chain && bash <(curl -sL install.getlynx.io) rebuild --chain=$SPARK_CHAIN; }
#
h() { executeHelpCommand; }
pri() { executePriceCommand; }
#
# Function to display aliases in a nicely formatted MOTD (uses SPARK_* vars)
executeHelpCommand() {
    _spark_require_chain || return 1
    echo ""
    echo ""
    local chain_upper
    chain_upper=$(echo "$SPARK_CHAIN" | tr '[:lower:]' '[:upper:]')
    local chain_cap
    chain_cap=$(echo "$SPARK_CHAIN" | sed 's/./\U&/')

    # Count stakes won in the last 24 hours from debug.log
    local since_iso
    since_iso=$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    local stakes_won=0
    if [ -f "$SPARK_DATADIR/debug.log" ] && [ -n "$since_iso" ]; then
        stakes_won=$(grep "CheckStake(): New proof-of-stake block found" "$SPARK_DATADIR/debug.log" 2>/dev/null | awk -v cutoff="$since_iso" '{timestamp = substr($0, 1, 20) "Z"; if (timestamp >= cutoff) count++} END {print count+0}')
    fi
    [ -z "$stakes_won" ] && stakes_won="0"

    local total_blocks=288
    local percent_yield
    percent_yield=$(awk "BEGIN {printf \"%.3f\", $stakes_won * 100 / $total_blocks}" 2>/dev/null || echo "0.000")

    # Count stakes won in the last 7 days
    local since_iso_7d
    since_iso_7d=$(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    local stakes_won_7d=0
    if [ -f "$SPARK_DATADIR/debug.log" ] && [ -n "$since_iso_7d" ]; then
        stakes_won_7d=$(grep "CheckStake(): New proof-of-stake block found" "$SPARK_DATADIR/debug.log" 2>/dev/null | awk -v cutoff="$since_iso_7d" '{timestamp = substr($0, 1, 20) "Z"; if (timestamp >= cutoff) count++} END {print count+0}')
    fi
    [ -z "$stakes_won_7d" ] && stakes_won_7d="0"

    local total_blocks_7d=2016
    local percent_yield_7d
    percent_yield_7d=$(awk "BEGIN {printf \"%.3f\", $stakes_won_7d * 100 / $total_blocks_7d}" 2>/dev/null || echo "0.000")

    # Count immature UTXOs
    local immature_utxos
    immature_utxos=$($SPARK_CLI listunspent 2>/dev/null | awk '/"confirmations":/ {gsub(/[^0-9]/, "", $2); conf = $2 + 0; if (conf < 31 && conf > 0) count++} END {print count+0}')
    [ -z "$immature_utxos" ] && immature_utxos="0"

    local wallet_balance
    wallet_balance=$($SPARK_CLI getbalance 2>/dev/null || echo "0")
    [ -z "$wallet_balance" ] && wallet_balance="0"

    local version_info
    version_info=$($SPARK_CLI -version 2>/dev/null | head -1 || echo "Unknown")
    [ -z "$version_info" ] && version_info="Unknown"

    local title="${chain_cap} Spark for the Lynx Data Storage Network"
    local width=64
    local pad=$(( (width - ${#title}) / 2 ))
    printf "%*s%s\n" "$pad" "" "$title"
    echo ""
    echo "  NODE STATUS:"
    echo "    🎯 Stakes won in last 24 hours: $stakes_won"
    echo "    📊 24-hour yield rate (stakes/blocks): ${percent_yield}%"
    echo "    🎯 Stakes won in last 7 days: $stakes_won_7d"
    echo "    📊 7-day yield rate (stakes/blocks): ${percent_yield_7d}%"
    echo "    🔄 Immature transactions (< 31 confirmations): $immature_utxos"
    echo "    💰 Current wallet balance: $wallet_balance"
    echo ""
    echo "  DAEMON COMMANDS:"
    echo "    lyl [lines] [-f]       - View daemon debug log (default 30)"
    echo "    lyv                    - Show daemon version"
    echo "    lyr [-d]               - Restart daemon (-d to purge debug)"
    echo "    lyc [-e]               - View/edit daemon conf (-e to edit)"
    echo "    gbi                    - Get blockchain info"
    echo "    hel [keyword]          - Show daemon help (keyword search)"
    echo ""
    echo "  WALLET COMMANDS:"
    echo "    gba                    - Get wallet balances"
    echo "    gna                    - Generate new address"
    echo "    lag                    - List address groupings"
    echo "    sta [address] [amount] - Send to address (sender pays fee)"
    echo "    swe [address]          - Sweep a wallet (receiver pays fee)"
    echo "    bac                    - Manual wallet backup"
    echo "    lba                    - List backup directory contents"
    echo "    pri                    - Show wallet value in USD"
    echo ""
    echo "  SYSTEM COMMANDS:"
    echo "    lss                    - Check systemd service status"
    echo "    jou [lines] [-f]       - View install logs (default 30)"
    echo "    upd                    - Install or update daemon to latest release"
    echo "    reb                    - Update services, timers, firewall, and aliases"
    echo "    usp [port]             - Change SSH port"
    echo "    wdi                    - Change to daemon working directory"
    echo "    ipt                    - List iptables rules"
    echo "    chain / c              - Switch between installed chains"
    echo ""
    echo "  USEFUL COMMANDS:"
    echo "    htop                   - Monitor system resources"
    echo "    h                      - Show this help message again"
    echo ""
    echo "  📚 Complete project documentation: https://docs.getlynx.io/"
    echo "  💾 Store files permanently: https://clevver.org/"
    echo "  🔍 Blockchain explorer: https://explorer.getlynx.io/"
    echo "  📈 Trade Lynx: https://freixlite.com/market/LYNX/LTC"
    echo "  🔢 Version: $version_info"
    echo ""
    echo ""
}
#
# Function to display wallet value and price information
executePriceCommand() {
    _spark_require_chain || return 1
    echo ""

    local wallet_balance
    wallet_balance=$($SPARK_CLI getbalance 2>/dev/null || echo "0")
    [ -z "$wallet_balance" ] && wallet_balance="0"

    # Fetch LYNX price from API with random endpoint selection and fallback
    local price_usd=""
    local api_endpoints=(
        "https://api-one.ewm-cx.info/api/v1/price/getPriceByCoin?symbol=LYNX"
        "https://api-two.ewm-cx.net/api/v1/price/getPriceByCoin?symbol=LYNX"
    )
    local first_index=$((RANDOM % 2))
    local second_index=$((1 - first_index))
    local api_response extracted_price

    api_response=$(curl -s --max-time 3 "${api_endpoints[$first_index]}" 2>/dev/null)
    if [ -n "$api_response" ]; then
        extracted_price=$(echo "$api_response" | awk -F'"priceUSD":"' '{print $2}' | awk -F'"' '{print $1}')
        [ -n "$extracted_price" ] && price_usd="$extracted_price"
    fi
    if [ -z "$price_usd" ]; then
        api_response=$(curl -s --max-time 3 "${api_endpoints[$second_index]}" 2>/dev/null)
        if [ -n "$api_response" ]; then
            extracted_price=$(echo "$api_response" | awk -F'"priceUSD":"' '{print $2}' | awk -F'"' '{print $1}')
            [ -n "$extracted_price" ] && price_usd="$extracted_price"
        fi
    fi
    [ -z "$price_usd" ] && price_usd="0.00000000"

    # Count stakes from debug.log
    local since_iso since_iso_7d stakes_won_24h=0 stakes_won_7d=0
    since_iso=$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    since_iso_7d=$(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
    if [ -f "$SPARK_DATADIR/debug.log" ]; then
        stakes_won_24h=$(grep "CheckStake(): New proof-of-stake block found" "$SPARK_DATADIR/debug.log" 2>/dev/null | awk -v cutoff="$since_iso" '{timestamp = substr($0, 1, 20) "Z"; if (timestamp >= cutoff) count++} END {print count+0}')
        stakes_won_7d=$(grep "CheckStake(): New proof-of-stake block found" "$SPARK_DATADIR/debug.log" 2>/dev/null | awk -v cutoff="$since_iso_7d" '{timestamp = substr($0, 1, 20) "Z"; if (timestamp >= cutoff) count++} END {print count+0}')
    fi
    [[ "$stakes_won_24h" =~ ^[0-9]+$ ]] || stakes_won_24h=0
    [[ "$stakes_won_7d" =~ ^[0-9]+$ ]] || stakes_won_7d=0

    # Format USD helper
    _format_usd() {
        local formatted int_part dec_part int_with_commas
        formatted=$(awk "BEGIN {printf \"%.2f\", $1}" 2>/dev/null || echo "0.00")
        int_part=$(echo "$formatted" | cut -d. -f1)
        dec_part=$(echo "$formatted" | cut -d. -f2)
        int_with_commas=$(echo "$int_part" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta')
        echo "${int_with_commas}.${dec_part}"
    }

    local wallet_value_raw wallet_value_usd
    wallet_value_raw=$(awk "BEGIN {printf \"%.2f\", $wallet_balance * $price_usd}" 2>/dev/null || echo "0.00")
    wallet_value_usd=$(_format_usd "$wallet_value_raw")

    local staking_yield_24h_raw staking_yield_24h_usd
    staking_yield_24h_raw=$(awk "BEGIN {printf \"%.2f\", $stakes_won_24h * $price_usd}" 2>/dev/null || echo "0.00")
    staking_yield_24h_usd=$(_format_usd "$staking_yield_24h_raw")

    local staking_yield_7d_raw staking_yield_7d_usd
    staking_yield_7d_raw=$(awk "BEGIN {printf \"%.2f\", $stakes_won_7d * $price_usd}" 2>/dev/null || echo "0.00")
    staking_yield_7d_usd=$(_format_usd "$staking_yield_7d_raw")

    local estimated_monthly_stakes staking_yield_monthly_raw staking_yield_monthly_usd
    estimated_monthly_stakes=$((stakes_won_7d * 4)) 2>/dev/null || estimated_monthly_stakes=0
    staking_yield_monthly_raw=$(awk "BEGIN {printf \"%.2f\", $staking_yield_7d_raw * 4}" 2>/dev/null || echo "0.00")
    staking_yield_monthly_usd=$(_format_usd "$staking_yield_monthly_raw")

    echo "  PRICE INFORMATION:"
    echo "    💵 Wallet value (USD): \$$wallet_value_usd"
    echo ""
    echo "    🎯 Staking Yield (USD):"
    echo "        24-hour yield:     \$$staking_yield_24h_usd ($stakes_won_24h stakes)"
    echo "        7-day yield:       \$$staking_yield_7d_usd ($stakes_won_7d stakes)"
    echo "        Estimated monthly: \$$staking_yield_monthly_usd (~$estimated_monthly_stakes stakes)"
    echo ""

    local amounts=(1 10 100 1000 10000 100000 1000000 10000000 100000000)
    local labels=("1 LYNX" "10 LYNX" "100 LYNX" "1,000 LYNX" "10,000 LYNX" "100,000 LYNX" "1,000,000 LYNX" "10,000,000 LYNX" "100,000,000 LYNX")
    echo "    💲 LYNX Price List (USD):"
    local i=0
    for amt in "${amounts[@]}"; do
        local raw val
        raw=$(awk "BEGIN {printf \"%.2f\", $amt * $price_usd}" 2>/dev/null || echo "0.00")
        val=$(_format_usd "$raw")
        printf "        %-22s \$%s\n" "${labels[$i]}:" "$val"
        i=$((i + 1))
    done
    echo ""
}
#
# Function to update SSH port
update_ssh_port() {
    if [ -z "$1" ]; then
        local current_port
        current_port=$(grep "^#*Port" /etc/ssh/sshd_config | head -1 | sed 's/^#*Port[[:space:]]*//')
        [ -z "$current_port" ] && current_port="22"
        echo "Current SSH port: $current_port"
        echo ""
        echo "Usage: usp <new_port>"
        echo "Example: usp 2222"
        return 0
    fi
    local new_port="$1"
    local current_port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo "ERROR: Invalid port number. Must be between 1 and 65535."
        return 1
    fi
    current_port=$(grep "^#*Port" /etc/ssh/sshd_config | head -1 | sed 's/^#*Port[[:space:]]*//')
    [ -z "$current_port" ] && current_port="22"
    if [ "$new_port" = "$current_port" ]; then
        echo "SSH is already on port $new_port."
        return 0
    fi
    echo "Current SSH port: $current_port"
    echo "New SSH port: $new_port"
    echo ""
    echo "WARNING: This will change the SSH port and reboot the device!"
    echo ""
    read -p "Do you want to continue? (y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Operation cancelled." && return 1
    echo "Updating sshd_config..."
    sed -i "s/^#*Port.*/Port $new_port/" /etc/ssh/sshd_config
    echo "Updating SPARK firewall rules..."
    (
        flock -w 10 200 || { echo "ERROR: Could not acquire firewall lock."; return 1; }
        # Swap the SSH ACCEPT rule in the SPARK parent chain
        iptables -D SPARK -p tcp --dport "$current_port" -j ACCEPT 2>/dev/null || true
        iptables -C SPARK -p tcp --dport "$new_port" -j ACCEPT 2>/dev/null || \
            iptables -I SPARK 3 -p tcp --dport "$new_port" -j ACCEPT
    ) 200>/var/lock/spark-iptables
    echo "Restarting SSH daemon..."
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        echo "SSH daemon restarted successfully"
    else
        echo "ERROR: Failed to restart SSH daemon"
        return 1
    fi
    echo ""
    echo "SSH port updated successfully to $new_port"
    echo "Connect to the new port: ssh -p $new_port root@$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
}
#
# Login-time notice: show which chain is selected (or prompt if none)
if [ -n "${SPARK_CHAIN:-}" ]; then
    executeHelpCommand
else
    echo ""
    echo "  No chain selected. Run 'chain' or 'c' to pick one."
    echo ""
fi
cd /root
#
# END spark-aliases
SPARKEOF
}

# Function to clean up multiple consecutive empty lines in bashrc
truncateFileSpace() {
    local BASHRC="/root/.bashrc"

    # Only proceed if the file exists
    if [ ! -f "$BASHRC" ]; then
        return
    fi

    # Use sed to replace multiple consecutive empty lines with single empty lines
    # This pattern matches 2 or more consecutive empty lines and replaces them with 1
    sed -i '/^$/N;/^\n$/D' "$BASHRC"

    log "Cleaned up multiple empty lines in $BASHRC"
}

# Register this chain in /etc/spark/chains.conf and install chain selector
# Creates: /etc/spark/chains.conf, /usr/local/bin/chain, /usr/local/bin/c (symlink),
#          /usr/local/bin/spark-current-chain.sh
registerChainAndInstallSelector() {
    # --- Chain registry ---
    mkdir -p /etc/spark
    local registry="/etc/spark/chains.conf"
    touch "$registry"
    if ! grep -qx "$chain_lower" "$registry" 2>/dev/null; then
        echo "$chain_lower" >> "$registry"
        log "Registered $chain_lower in $registry."
    fi

    # --- Ensure /run/spark exists (tmpfs, cleared on reboot) ---
    mkdir -p /run/spark

    # --- Install /usr/local/bin/chain selector ---
    cat <<'CHAINEOF' > /usr/local/bin/chain
#!/bin/bash
# chain — Spark chain selector
# Usage: chain [<name|number>|--show|--clear]

REGISTRY="/etc/spark/chains.conf"
CURRENT="/run/spark/current-chain"

if [ ! -f "$REGISTRY" ] || [ ! -s "$REGISTRY" ]; then
    echo "No chains registered in $REGISTRY."
    exit 1
fi

# Read registry into an array
mapfile -t chains < "$REGISTRY"

# Resolve the RPC octet for a given chain name (mirrors install.sh logic)
_get_rpc_ip() {
    local cname="$1"
    local octet
    octet=$(printf '%s' "$cname" | cksum | awk '{print ($1 % 253) + 2}')
    # Collision resolution: scan conf files like install.sh does
    local tries=0
    while [ "$tries" -lt 253 ]; do
        local taken=""
        for cf in /var/lib/*/[a-z]*.conf; do
            [ -f "$cf" ] || continue
            if grep -q "^rpcbind=127\\.0\\.0\\.${octet}$" "$cf" 2>/dev/null; then
                local cc
                cc=$(basename "$(dirname "$cf")")
                if [ "$cc" != "$cname" ]; then
                    taken="$cc"
                    break
                fi
            fi
        done
        [ -z "$taken" ] && break
        octet=$(( (octet % 253) + 2 ))
        tries=$(( tries + 1 ))
    done
    echo "127.0.0.${octet}"
}

# Display the numbered menu
_show_menu() {
    echo ""
    echo "  Installed chains:"
    echo ""
    local i=1
    for cname in "${chains[@]}"; do
        local rpc_ip
        rpc_ip=$(_get_rpc_ip "$cname")
        local marker=""
        if [ -f "$CURRENT" ] && [ "$(cat "$CURRENT" 2>/dev/null)" = "$cname" ]; then
            marker=" *"
        fi
        printf "    %d) %s (%s)%s\n" "$i" "$cname" "$rpc_ip" "$marker"
        i=$((i + 1))
    done
    echo ""
}

# Select a chain by name or number; write to current-chain file
_select_chain() {
    local input="$1"
    local selected=""

    # Try as a number first
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        local idx=$((input - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#chains[@]}" ]; then
            selected="${chains[$idx]}"
        else
            echo "Invalid number: $input (valid range: 1-${#chains[@]})"
            return 1
        fi
    else
        # Try as a name
        local name_lower
        name_lower=$(echo "$input" | tr '[:upper:]' '[:lower:]')
        for cname in "${chains[@]}"; do
            if [ "$cname" = "$name_lower" ]; then
                selected="$cname"
                break
            fi
        done
    fi

    if [ -z "$selected" ]; then
        echo "Unknown chain: $input"
        return 1
    fi

    mkdir -p /run/spark
    echo "$selected" > "$CURRENT"
    local rpc_ip
    rpc_ip=$(_get_rpc_ip "$selected")
    local display_name
    display_name="$(echo "$selected" | sed 's/./\U&/')"
    echo "  Switched to $display_name ($rpc_ip)"
    return 0
}

# --- Handle arguments ---
case "${1:-}" in
    --show)
        if [ -f "$CURRENT" ] && [ -s "$CURRENT" ]; then
            cat "$CURRENT"
        else
            echo "No chain selected."
            exit 1
        fi
        ;;
    --clear)
        rm -f "$CURRENT"
        echo "Chain selection cleared."
        ;;
    "")
        # No args: auto-select if one chain, otherwise interactive menu
        if [ "${#chains[@]}" -eq 1 ]; then
            _select_chain "${chains[0]}"
        else
            _show_menu
            if [ -t 0 ]; then
                read -p "  Select chain (number or name): " choice
                if [ -n "$choice" ]; then
                    _select_chain "$choice"
                fi
            else
                echo "Non-interactive shell — pass a chain name or number as argument."
                exit 1
            fi
        fi
        ;;
    *)
        # Direct switch by name or number
        _select_chain "$1"
        ;;
esac
CHAINEOF
    chmod +x /usr/local/bin/chain

    # Create 'c' shortcut symlink
    ln -sf /usr/local/bin/chain /usr/local/bin/c

    # --- Install /usr/local/bin/spark-current-chain.sh (sourced by aliases) ---
    cat <<'HELPEREOF' > /usr/local/bin/spark-current-chain.sh
#!/bin/bash
# spark-current-chain.sh — Sourced by .bashrc to export SPARK_* variables.
# Reads the currently selected chain from /run/spark/current-chain.
# If no chain is selected:
#   - Interactive shell: shows a notice (does NOT auto-prompt to avoid blocking)
#   - Non-interactive shell: silently skips

_SPARK_CURRENT_FILE="/run/spark/current-chain"
_SPARK_REGISTRY="/etc/spark/chains.conf"

# Auto-select if only one chain is registered and none is selected
if [ ! -f "$_SPARK_CURRENT_FILE" ] || [ ! -s "$_SPARK_CURRENT_FILE" ]; then
    if [ -f "$_SPARK_REGISTRY" ] && [ -s "$_SPARK_REGISTRY" ]; then
        _spark_count=$(wc -l < "$_SPARK_REGISTRY")
        if [ "$_spark_count" -eq 1 ]; then
            mkdir -p /run/spark
            head -1 "$_SPARK_REGISTRY" > "$_SPARK_CURRENT_FILE"
        fi
        unset _spark_count
    fi
fi

if [ -f "$_SPARK_CURRENT_FILE" ] && [ -s "$_SPARK_CURRENT_FILE" ]; then
    SPARK_CHAIN=$(cat "$_SPARK_CURRENT_FILE")
    SPARK_DATADIR="/var/lib/${SPARK_CHAIN}"
    SPARK_CONF="${SPARK_DATADIR}/${SPARK_CHAIN}.conf"
    SPARK_SERVICE="${SPARK_CHAIN}.service"

    # Derive RPC IP (mirrors install.sh cksum logic)
    _spark_octet=$(printf '%s' "$SPARK_CHAIN" | cksum | awk '{print ($1 % 253) + 2}')
    # Collision resolution
    _spark_tries=0
    while [ "$_spark_tries" -lt 253 ]; do
        _spark_taken=""
        for _spark_cf in /var/lib/*/[a-z]*.conf; do
            [ -f "$_spark_cf" ] || continue
            if grep -q "^rpcbind=127\\.0\\.0\\.${_spark_octet}$" "$_spark_cf" 2>/dev/null; then
                _spark_cc=$(basename "$(dirname "$_spark_cf")")
                if [ "$_spark_cc" != "$SPARK_CHAIN" ]; then
                    _spark_taken="$_spark_cc"
                    break
                fi
            fi
        done
        [ -z "$_spark_taken" ] && break
        _spark_octet=$(( (_spark_octet % 253) + 2 ))
        _spark_tries=$(( _spark_tries + 1 ))
    done
    SPARK_RPC_HOST="127.0.0.${_spark_octet}"
    SPARK_CLI="${SPARK_CHAIN}-cli -datadir=${SPARK_DATADIR} -rpcconnect=${SPARK_RPC_HOST}"
    unset _spark_octet _spark_tries _spark_taken _spark_cf _spark_cc

    export SPARK_CHAIN SPARK_DATADIR SPARK_CONF SPARK_SERVICE SPARK_RPC_HOST SPARK_CLI
else
    # No chain selected — clear vars
    unset SPARK_CHAIN SPARK_DATADIR SPARK_CONF SPARK_SERVICE SPARK_RPC_HOST SPARK_CLI 2>/dev/null
fi
unset _SPARK_CURRENT_FILE _SPARK_REGISTRY
HELPEREOF
    chmod +x /usr/local/bin/spark-current-chain.sh

    log "Installed chain selector (/usr/local/bin/chain, /usr/local/bin/c) and helper (/usr/local/bin/spark-current-chain.sh)."
}

# Create a one-shot service and timer that fetches and runs patch_rpc_conf.sh
# to set the per-chain loopback RPC address. The timer disables itself once done.
patchRpcConf() {
    local service_unit="${chain_lower}-patch-rpc-conf.service"
    local timer_unit="${chain_lower}-patch-rpc-conf.timer"
    local conf_path="$WorkingDirectory/$conf_name"

    # Create the systemd service unit (fetches and runs patch_rpc_conf.sh remotely)
    cat <<EOF > /etc/systemd/system/$service_unit
[Unit]
Description=Patch ${effective_chain} conf with per-chain RPC address
Documentation=https://getlynx.io/

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sfL $SCRIPT_BASE_URL/patch_rpc_conf.sh | bash -s'
Environment=CONF_PATH=$conf_path
Environment=RPC_HOST=$rpc_host
Environment=SERVICE_NAME=$service_name
Environment=TIMER_UNIT=$timer_unit
StandardOutput=journal
StandardError=journal
EOF

    # Create the systemd timer unit
    cat <<EOF > /etc/systemd/system/$timer_unit
[Unit]
Description=Run ${chain_lower}-patch-rpc-conf every 5 seconds until patched

[Timer]
OnBootSec=5sec
OnUnitActiveSec=5sec
AccuracySec=5sec
Unit=$service_unit
Persistent=false

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable "$timer_unit" >/dev/null 2>&1
    systemctl start "$timer_unit"
    log "Created and started $timer_unit to patch RPC settings in $conf_path."
}

# Create per-chain install.service and install.timer if not present
createInstallServiceUnit() {
    local install_service="${chain_lower}-install.service"
    local install_timer="${chain_lower}-install.timer"
    log "Checking for the existence of /etc/systemd/system/$install_service and /etc/systemd/system/$install_timer."
    if [ ! -f /etc/systemd/system/$install_service ] || [ ! -f /etc/systemd/system/$install_timer ]; then
        log "Creating /etc/systemd/system/$install_service and /etc/systemd/system/$install_timer."
        cat <<EOF > /etc/systemd/system/$install_service
[Unit]
Description=Run install.sh every 12 minutes for ${effective_chain}
Documentation=https://getlynx.io/

[Service]
Type=simple
ExecStart=/usr/local/bin/install.sh --chain=${chain_lower}
StandardOutput=journal
StandardError=journal
Environment=HOME=/root
WorkingDirectory=/root
EOF

        cat <<EOF > /etc/systemd/system/$install_timer
[Unit]
Description=Run install.sh every 12 minutes for ${effective_chain}
Documentation=https://getlynx.io/

[Timer]
OnBootSec=15sec
OnUnitActiveSec=12min
AccuracySec=5sec
Unit=$install_service
Persistent=false

[Install]
WantedBy=timers.target
EOF
        log "Executing daemon-reload for new /etc/systemd/system/$install_service and /etc/systemd/system/$install_timer."
        systemctl daemon-reload
        log "Enabled systemd for new /etc/systemd/system/$install_timer."
        systemctl enable $install_timer >/dev/null 2>&1
        log "Starting systemd for new /etc/systemd/system/$install_timer."
        systemctl start $install_timer
        log "/etc/systemd/system/$install_service and /etc/systemd/system/$install_timer created, enabled, and started."

        # Disable firewalld and SELinux on RHEL-based systems
        log "Checking for RHEL-based system to disable firewalld and SELinux."
        if [ "$os_family" = "redhat" ]; then
            log "Checking for firewalld to disable on RHEL-based system."
            # Disable firewalld if installed
            if systemctl list-unit-files | grep -q firewalld; then
                log "Disabling firewalld on RHEL-based system..."
                systemctl stop firewalld 2>/dev/null || log "firewalld was not running"
                systemctl disable firewalld 2>/dev/null || log "firewalld was not enabled"
                log "firewalld disabled"
            else
                log "firewalld is not installed - skipping"
            fi

            # Disable SELinux if running
            if command -v getenforce >/dev/null 2>&1; then
                current_selinux=$(getenforce 2>/dev/null)
                if [ "$current_selinux" = "Enforcing" ] || [ "$current_selinux" = "Permissive" ]; then
                    log "Disabling SELinux (currently: $current_selinux)..."
                    setenforce 0 2>/dev/null || log "Failed to set SELinux to permissive mode"
                    if [ -f "/etc/selinux/config" ]; then
                        sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
                        sed -i 's/SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
                        log "SELinux disabled in config. Will take effect after reboot."
                    else
                        log "SELinux config file not found - SELinux may not be properly installed"
                    fi
                else
                    log "SELinux is already disabled (current state: $current_selinux)"
                fi
            else
                log "SELinux is not installed - skipping"
            fi
        else
            log "Not a RHEL-based system - skipping"
        fi

        log "Installation of ${effective_chain} has begun. The install timer will manage ongoing maintenance."
        echo ""
        echo ""
        echo "Installation of ${effective_chain} has begun. No reboot required. Run 'h' to see the latest commands."
        echo ""
        echo ""
    else
        log "/etc/systemd/system/$install_service and /etc/systemd/system/$install_timer already exist. Skipping creation."
    fi
}

# Create one-shot services and timers that fetch and run the wallet-backup
# patch scripts. One timer (7s) ensures /usr/local/bin/backup.sh is installed;
# a second timer (8s) ensures the {chain}-wallet-backup service/timer pair is
# installed. Each timer self-disables once its target exists.
patchWalletBackup() {
    local backup_service_unit="${chain_lower}-wallet-backup.service"
    local backup_timer_unit="${chain_lower}-wallet-backup.timer"
    local script_service_unit="${chain_lower}-patch-wallet-backup-script.service"
    local script_timer_unit="${chain_lower}-patch-wallet-backup-script.timer"
    local timer_service_unit="${chain_lower}-patch-wallet-backup-timer.service"
    local timer_timer_unit="${chain_lower}-patch-wallet-backup-timer.timer"

    # Service that fetches and runs patch_wallet_backup_script.sh
    cat <<EOF > /etc/systemd/system/$script_service_unit
[Unit]
Description=Install ${effective_chain} wallet backup script
Documentation=https://getlynx.io/

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sfL $SCRIPT_BASE_URL/patch_wallet_backup_script.sh | bash -s'
Environment=CHAIN_LOWER=$chain_lower
Environment=EFFECTIVE_CHAIN=$effective_chain
Environment=CLI_NAME=$cli_name
Environment="CLI_FLAGS=$cli_flags"
Environment=CONF_NAME=$conf_name
Environment=WORKING_DIRECTORY=$WorkingDirectory
Environment=TIMER_UNIT=$script_timer_unit
StandardOutput=journal
StandardError=journal
EOF

    cat <<EOF > /etc/systemd/system/$script_timer_unit
[Unit]
Description=Run ${chain_lower}-patch-wallet-backup-script every 7 seconds until installed

[Timer]
OnBootSec=7sec
OnUnitActiveSec=7sec
AccuracySec=1sec
Unit=$script_service_unit
Persistent=false

[Install]
WantedBy=timers.target
EOF

    # Service that fetches and runs patch_wallet_backup_timer.sh
    cat <<EOF > /etc/systemd/system/$timer_service_unit
[Unit]
Description=Install ${effective_chain} wallet backup service and timer
Documentation=https://getlynx.io/

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sfL $SCRIPT_BASE_URL/patch_wallet_backup_timer.sh | bash -s'
Environment=CHAIN_LOWER=$chain_lower
Environment=EFFECTIVE_CHAIN=$effective_chain
Environment=SERVICE_NAME=$service_name
Environment=WORKING_DIRECTORY=$WorkingDirectory
Environment=BACKUP_SERVICE_UNIT=$backup_service_unit
Environment=BACKUP_TIMER_UNIT=$backup_timer_unit
Environment=TIMER_UNIT=$timer_timer_unit
StandardOutput=journal
StandardError=journal
EOF

    cat <<EOF > /etc/systemd/system/$timer_timer_unit
[Unit]
Description=Run ${chain_lower}-patch-wallet-backup-timer every 8 seconds until installed

[Timer]
OnBootSec=8sec
OnUnitActiveSec=8sec
AccuracySec=1sec
Unit=$timer_service_unit
Persistent=false

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable "$script_timer_unit" >/dev/null 2>&1
    systemctl start "$script_timer_unit"
    systemctl enable "$timer_timer_unit" >/dev/null 2>&1
    systemctl start "$timer_timer_unit"
    log "Created and started $script_timer_unit and $timer_timer_unit for wallet backup setup."
}

# Set up swap expansion as an external patch triggered after boot
patchSwap() {
    local service_unit="${chain_lower}-patch-swap.service"
    local timer_unit="${chain_lower}-patch-swap.timer"
    local attempt_file="/run/spark/${chain_lower}-patch-swap-attempts"

    cat <<EOF > /etc/systemd/system/$service_unit
[Unit]
Description=Expand swap to 4GB for ${effective_chain}
Documentation=https://getlynx.io/

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sfL $SCRIPT_BASE_URL/patch_swap.sh | bash -s'
Environment=TIMER_UNIT=$timer_unit
Environment=ATTEMPT_FILE=$attempt_file
StandardOutput=journal
StandardError=journal
EOF

    cat <<EOF > /etc/systemd/system/$timer_unit
[Unit]
Description=Run ${chain_lower}-patch-swap every 5 seconds until complete

[Timer]
OnBootSec=2sec
OnUnitActiveSec=5sec
AccuracySec=1sec
Unit=$service_unit
Persistent=false

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable "$timer_unit" >/dev/null 2>&1
    systemctl start "$timer_unit"
    log "Created and started $timer_unit to expand swap if needed."
}

# Detect OS details for binary selection
# Sets os_name, os_version, os_major_version for use in binary selection
# This function is called before downloading or updating
# It sources /etc/os-release and parses the relevant fields
# Example: os_name=debian, os_version=11, os_major_version=11
# Combined function to detect OS family and detailed information
# This helps select the correct release asset for the system
getSystemDetails() {
    log "Detecting OS information..."

    if [ -f /etc/os-release ]; then
        source /etc/os-release

        # Set OS family (basic categorization)
        case "$ID" in
            debian|ubuntu)
                os_family="debian"
                ;;
            rhel|centos|fedora|rocky|almalinux|ol)
                os_family="redhat"
                ;;
            *)
                os_family="$ID"
                ;;
        esac

        # Set detailed OS info
        os_name=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        os_version=$(echo "$VERSION_ID" | tr -d '"')

        if [ "$os_family" = "redhat" ]; then
            os_major_version=$(echo "$os_version" | cut -d. -f1)
        else
            os_major_version="$os_version"
        fi

        log "Detected: $os_name $os_version (Family: $os_family)"
    else
        os_family="unknown"
        os_name="unknown"
        os_version="unknown"
        os_major_version="unknown"
        log "Could not detect OS information"
    fi
}

# Configure system locale for UTF-8 support
configureLocale() {
    local preferredLocale="en_US.UTF-8"
    local preferredLocaleFile="/etc/locale.gen"

    # Check if locale is already properly configured
    if [ -n "${LANG:-}" ] && [ -n "${LC_ALL:-}" ] && [ "${LANG:-}" = "$preferredLocale" ] && [ "${LC_ALL:-}" = "$preferredLocale" ]; then
        log "Locale already configured as $preferredLocale. Skipping configuration."
        return 0
    fi

    if [ "$os_family" = "debian" ]; then
        log "Configuring locale for Debian/Ubuntu system..."
        # Ensure locales package is installed
        if ! dpkg -s locales >/dev/null 2>&1; then
            log "Installing locales package..."
            apt-get update -y >/dev/null 2>&1 && apt-get install -y locales >/dev/null 2>&1 || log "Failed to install locales package"
        fi

        # Check if locale is already enabled in locale.gen
        if [ -f "$preferredLocaleFile" ] && grep -q "^$preferredLocale UTF-8" "$preferredLocaleFile"; then
            log "Locale $preferredLocale already enabled in $preferredLocaleFile"
        else
            log "Enabling $preferredLocale in $preferredLocaleFile..."
            # Uncomment or add the preferred locale in /etc/locale.gen
            sed -i "/^# $preferredLocale UTF-8/s/^# //" "$preferredLocaleFile" 2>/dev/null || true
            if ! grep -q "^$preferredLocale UTF-8" "$preferredLocaleFile"; then
                echo "$preferredLocale UTF-8" >> "$preferredLocaleFile"
            fi
        fi

        # Generate the locale — always attempt if not available
        if locale -a 2>/dev/null | grep -q "^en_US.utf8$"; then
            log "Locale $preferredLocale already generated. Skipping generation."
        else
            log "Generating locale $preferredLocale..."
            locale-gen "$preferredLocale" 2>&1 | systemd-cat -t install.sh || true
            # Fallback: install locales-all if locale-gen didn't produce the locale
            if ! locale -a 2>/dev/null | grep -q "^en_US.utf8$"; then
                log "locale-gen failed, installing locales-all as fallback..."
                apt-get install -y locales-all >/dev/null 2>&1 || log "Failed to install locales-all"
            fi
        fi

        # Check if system-wide locale is already set
        if [ -f /etc/default/locale ] && grep -q "^LANG=$preferredLocale$" /etc/default/locale; then
            log "System-wide locale already set to $preferredLocale. Skipping update."
        else
            log "Setting system-wide locale to $preferredLocale..."
            update-locale LANG=$preferredLocale LC_ALL=$preferredLocale || log "Failed to update system locale"
        fi

    elif [ "$os_family" = "redhat" ]; then
        log "Configuring locale for RedHat/Rocky/AlmaLinux system..."
        # Check if language pack is already installed
        if locale -a 2>/dev/null | grep -q "^$preferredLocale$"; then
            log "Locale $preferredLocale already available. Skipping language pack installation."
        else
            # Install the appropriate language pack for UTF-8 support
            if command -v dnf >/dev/null 2>&1; then
                log "Installing language pack using dnf..."
                dnf install -y glibc-langpack-en >/dev/null 2>&1 || log "Failed to install glibc-langpack-en, continuing..."
            else
                log "Installing glibc-common using yum..."
                yum install -y glibc-common >/dev/null 2>&1 || log "Failed to install glibc-common, continuing..."
            fi
        fi

        # Set locale environment variables (only if not already set)
        if [ "${LANG:-}" != "$preferredLocale" ] || [ "${LC_ALL:-}" != "$preferredLocale" ]; then
            export LANG=$preferredLocale
            export LC_ALL=$preferredLocale
            log "Locale environment variables set to $preferredLocale"
        else
            log "Locale environment variables already set to $preferredLocale"
        fi
    fi

    log "Locale configuration completed"
}

# Download the most recent compatible binary from GitHub Releases
getCompatibleBinary() {

    # Detect OS details for asset selection
    getSystemDetails

    # Gracefully stop daemon if running
    if systemctl is-active --quiet $service_name; then
        log "Stopping $service_name..."
        systemctl stop $service_name || log "Failed to stop $service_name. Continuing with update."
    fi
    # Download latest release info from GitHub
    log "Querying GitHub API for latest ${effective_chain} release..."
    release_info=$(curl -s https://api.github.com/repos/getlynx/Lynx/releases/latest)
    if [ $? -ne 0 ] || [ -z "$release_info" ]; then
        log "Failed to fetch release information from GitHub API"
    fi
    # Detect architecture
    ARCH="$(uname -m)"
    log "Searching for compatible binary for $os_name $os_version ($ARCH)..."

    # Pre-filter release assets by chain name if specified
    if [ -n "$chain_name" ]; then
        log "Filtering binaries for chain: $chain_name"
        filtered_urls=$(echo "$release_info" | grep "browser_download_url" | grep -i "$chain_name" || true)
        if [ -z "$filtered_urls" ]; then
            log "No binary found for chain '$chain_name'. This chain may not have been built yet. For assistance, please visit our Discord server: https://discord.gg/6jUaNeV2Uy"
            return 1
        fi
    else
        filtered_urls=$(echo "$release_info" | grep "browser_download_url")
    fi

    # Select the correct asset based on OS family, version, and architecture
    if [ "$os_family" = "debian" ]; then
        if [[ "$ARCH" == "aarch64" || "$ARCH" == arm* ]]; then
            download_url=$(echo "$filtered_urls" | \
                grep -iE "debian|ubuntu|ol" | \
                grep -i "$os_version" | \
                grep -iE "\\.zip" | \
                grep -iE "arm" | \
                head -n 1 | \
                cut -d '"' -f 4)
        else
            download_url=$(echo "$filtered_urls" | \
                grep -iE "debian|ubuntu|ol" | \
                grep -i "$os_version" | \
                grep -iE "\\.zip" | \
                grep -iE "amd" | \
                head -n 1 | \
                cut -d '"' -f 4)
        fi
    elif [ "$os_family" = "redhat" ]; then
        if [[ "$ARCH" == "aarch64" || "$ARCH" == arm* ]]; then
            download_url=$(echo "$filtered_urls" | \
                grep -iE "rhel|centos|fedora|redhat|rocky|almalinux|ol" | \
                grep -i "$os_major_version" | \
                grep -iE "\\.zip" | \
                grep -iE "arm" | \
                head -n 1 | \
                cut -d '"' -f 4)
        else
            download_url=$(echo "$filtered_urls" | \
                grep -iE "rhel|centos|fedora|redhat|rocky|almalinux|ol" | \
                grep -i "$os_major_version" | \
                grep -iE "\\.zip" | \
                grep -iE "amd" | \
                head -n 1 | \
                cut -d '"' -f 4)
        fi
    else
        log "Unsupported OS family for binary selection: $os_family"
    fi
    if [ -z "$download_url" ]; then
        if [ -n "$chain_name" ]; then
            log "No binary found for chain '$chain_name' on $os_name $os_version ($ARCH). This chain may not have been built yet. For assistance, please visit our Discord server: https://discord.gg/6jUaNeV2Uy"
            return 1
        fi
        log "No suitable binary found for $os_name $os_version ($ARCH). Please check GitHub releases manually."
        return 1
    fi
    local filename=$(basename "$download_url")
    log "Downloading $filename to /root..."
    wget -q -O "/root/$filename" "$download_url" || log "Failed to download $filename"
    # Extract only the binaries to /usr/local/bin
    log "Extracting binaries to /usr/local/bin..."
    unzip -o "/root/$filename" $daemon_name $cli_name $tx_name -d /usr/local/bin >/dev/null 2>&1 || log "Failed to extract binaries"
    # Clean up the downloaded archive
    log "Cleaning up downloaded archive..."
    rm -f "/root/$filename"
    # Set correct permissions on the binaries
    log "Setting permissions for binaries..."
    chmod 755 /usr/local/bin/$daemon_name /usr/local/bin/$cli_name /usr/local/bin/$tx_name || log "Failed to set permissions"
    # Restart the service if it exists
    if [ -f "/etc/systemd/system/$service_name" ]; then
        log "Restarting $service_name..."
        systemctl restart $service_name || log "Failed to restart $service_name"
    else
        log "Service $service_name not yet created. Skipping restart."
    fi
    log "${effective_chain} has been updated to the latest release."
}

# Create systemd unit file for the chain daemon
createDaemonServiceUnit() {
    if [ ! -f /etc/systemd/system/$service_name ] || [ "$rebuild_mode" = "rebuild" ]; then
        log "Creating /etc/systemd/system/$service_name systemd unit file."
        cat <<EOF > /etc/systemd/system/$service_name
[Unit]
Description=${effective_chain} Cryptocurrency Daemon
Documentation=https://getlynx.io/
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=/bin/mkdir -p $WorkingDirectory
ExecStartPre=/bin/chown root:root $WorkingDirectory
ExecStart=/usr/local/bin/$daemon_name -datadir=$WorkingDirectory -dbcache=2048${assumevalid_flag}
ExecStop=/usr/local/bin/$cli_name -datadir=$WorkingDirectory -rpcconnect=$rpc_host stop
Restart=on-failure
RestartSec=30
User=root
TimeoutStartSec=300
TimeoutStopSec=60
WorkingDirectory=$WorkingDirectory

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        log "/etc/systemd/system/$service_name created and systemd reloaded."
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            log "/etc/systemd/system/$service_name already exists. Skipping creation."
        fi
    fi
}

# Check if daemon service is running, and start if not
startDaemon() {
    # First verify the binary exists
    if [ ! -f "/usr/local/bin/$daemon_name" ]; then
        log "ERROR: Cannot start service - $daemon_name binary not found at /usr/local/bin/$daemon_name"
        log "Attempting to reinstall binary..."

        # Download the most recent compatible binary from GitHub Releases
        getCompatibleBinary || true

        if [ ! -f "/usr/local/bin/$daemon_name" ]; then
            log "ERROR: Binary installation failed. Cannot start service."
            return 1
        fi
    fi

    if pgrep -x "$daemon_name" >/dev/null; then
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            log "${effective_chain} daemon is already running."
        fi
        return
    else
        log "${effective_chain} daemon is not running. Attempting to start."
        systemctl enable $service_name >/dev/null 2>&1
        sleep 5
        systemctl start $service_name
        log "${effective_chain} daemon started."
        if [ -f /etc/rc.local ]; then
            log "Disabling rc.local to prevent future install.sh downloads"
            chmod -x /etc/rc.local
        fi
        exit 0
    fi
}

# Create a one-shot service with two timers for patch_firewall.sh:
#   1. A fast-poll timer (every 5 sec) that self-disables once the daemon is ready
#   2. A maintenance timer (every 6 hours) that keeps firewall rules correct permanently
patchFirewall() {
    local service_unit="${chain_lower}-patch-firewall.service"
    local timer_unit="${chain_lower}-patch-firewall.timer"
    local maint_timer_unit="${chain_lower}-patch-firewall-maint.timer"

    # Create the systemd service unit (fetches and runs patch_firewall.sh remotely)
    cat <<EOF > /etc/systemd/system/$service_unit
[Unit]
Description=Apply ${effective_chain} firewall rules
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sfL $SCRIPT_BASE_URL/patch_firewall.sh | bash -s'
Environment=CLI_PATH=/usr/local/bin/$cli_name
Environment=DATADIR=$WorkingDirectory
Environment=RPCCONNECT=$rpc_host
Environment=CHAIN_NAME=$effective_chain
Environment=CHAIN_LOWER=$chain_lower
Environment=TIMER_UNIT=$timer_unit
StandardOutput=journal
StandardError=journal
EOF

    # Fast-poll timer: runs every 5 sec until firewall is applied, then self-disables
    cat <<EOF > /etc/systemd/system/$timer_unit
[Unit]
Description=Run ${chain_lower}-patch-firewall every 5 seconds until complete

[Timer]
OnBootSec=4sec
OnUnitActiveSec=5sec
AccuracySec=5sec
Unit=$service_unit
Persistent=false

[Install]
WantedBy=timers.target
EOF

    # Maintenance timer: reapplies firewall rules every 6 hours and after reboot
    cat <<EOF > /etc/systemd/system/$maint_timer_unit
[Unit]
Description=Reapply ${chain_lower}-patch-firewall every 6 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Unit=$service_unit
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable "$timer_unit" >/dev/null 2>&1
    systemctl start "$timer_unit"
    systemctl enable "$maint_timer_unit" >/dev/null 2>&1
    systemctl start "$maint_timer_unit"
    log "Created and started $timer_unit and $maint_timer_unit for firewall rules."
}

# Configure defaultSSH keys
createAuthorizedKeyDefaults() {

    # Ensure /root/.ssh and authorized_keys exist, add default keys if missing
    SSH_DIR="/root/.ssh"
    AUTH_KEYS="${SSH_DIR}/authorized_keys"
    log "Ensuring SSH directory and authorized_keys file exist..."
    mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR" || log "Failed to create or set permissions on $SSH_DIR"
    # Add default SSH keys if not already present
    if [ ! -f "$AUTH_KEYS" ] || ! grep -q 'benjamin@lynx.local' "$AUTH_KEYS"; then
        cat <<'EOF' >> "$AUTH_KEYS"
# Sample SSH public key (replace with your own and remove the # to enable)
# ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCcXZL7RcgCCrfyNohpemCZbu2oiGyu22kzcWHZZl8P4xLRgiO/1dbLlpg19G+YqxW7bSC2JHCwvqGlIb+aJeD7LbXWbracU2FH4I2k42jj7D+JWoxrJqh9zZ9GBQ8GT2ObIYxbk7tqh9wujLTEIfHr9zoE3Hnt8DaXZs/yu8EVI6EM+7lp1b3Fp/NNQQsrxgjWLj0KrvL40lfY6VukZ4nCXVQTkYuHOSRiPTx7SgcUGNS0hwOOt0IiYruL6JVKq+Y4hLk9U8tir5UUTXhcF+8e6zR1gvvvT6FP6J50z+G/l9Q/iQHwMIgoaxzNJ0JO4zk8ZXs4R0GJAql5UV2ezDnOpUAKtmz+jPmRKxhp5IngBUtgHYCni97nP6Jp0rKf9kAlQyEKf+0n21otCSPo0a1SOE+L1cqZbetdbXcbXvimc+m+j7Xn41B+ukPdIsDqlKjBCuvUXoYTWQTcgKCGU/dQ9tvvUWFM4quH9ORADqS7kbdBKegVvU3J67bNYd7bR25MytVEZ91V2nnNLydwP+29kWt/hqleUUpgBs+q9DkCI34yxv1CkZqvPlGvcDMpjBsL/DGy10xjmOSo5LRZQW67FqZ5aMVz2d4KLyykTwtUSgYqJ+eH4Gdmsfg/5gZimL8SjXC9eF+RV/n8aw8oVUJdhGsYxo3SYZaGbB6Nb92lew== benjamin@lynx.local

EOF
        log "Added default SSH public keys to $AUTH_KEYS."
    fi

    # Configure SSH daemon to allow public key authentication
    log "Configuring SSH daemon for public key authentication..."
    SSH_CONFIG="/etc/ssh/sshd_config"

    # Backup original config if it doesn't exist
    if [ ! -f "${SSH_CONFIG}.backup" ]; then
        cp "$SSH_CONFIG" "${SSH_CONFIG}.backup" || log "Failed to backup SSH config"
    fi

    # Enable public key authentication
    if ! grep -q "^PubkeyAuthentication yes" "$SSH_CONFIG"; then
        # Add or update PubkeyAuthentication setting
        if grep -q "^#PubkeyAuthentication" "$SSH_CONFIG"; then
            sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG" || log "Failed to enable PubkeyAuthentication"
        elif ! grep -q "^PubkeyAuthentication" "$SSH_CONFIG"; then
            echo "PubkeyAuthentication yes" >> "$SSH_CONFIG" || log "Failed to add PubkeyAuthentication setting"
        fi
        log "Enabled public key authentication in SSH config."
    fi

    # Ensure AuthorizedKeysFile is set correctly
    if ! grep -q "^AuthorizedKeysFile" "$SSH_CONFIG"; then
        echo "AuthorizedKeysFile .ssh/authorized_keys" >> "$SSH_CONFIG" || log "Failed to add AuthorizedKeysFile setting"
        log "Added AuthorizedKeysFile setting to SSH config."
    fi

    # Restart SSH daemon to apply changes
    log "Restarting SSH daemon to apply configuration changes..."
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        log "SSH daemon restarted successfully."
    else
        log "Failed to restart SSH daemon"
    fi
}

# Check if blockchain has completed syncing
isBlockchainSyncComplete() {
    # Skip sync check if the service hasn't been created yet (fresh install)
    if [ ! -f "/etc/systemd/system/$service_name" ]; then
        log "Service $service_name not yet created. Continuing with installation."
        return 0
    fi

    # Check if cli binary is available
    if [ ! -f "/usr/local/bin/$cli_name" ]; then
        log "ERROR: $cli_name binary not found. Cannot check sync status."
        log "Will continue to install and configure services."
        return 0
    fi

    # Get blockchain sync status
    SYNC_STATUS=$(/usr/local/bin/$cli_name -datadir=$WorkingDirectory -rpcconnect=$rpc_host getblockchaininfo 2>/dev/null | grep -o '"initialblockdownload":[^,}]*' | sed 's/.*://' | tr -d '"' | xargs)

    # If sync is complete (false), stop and disable timer
    if [ "$SYNC_STATUS" = "false" ]; then
        log "Blockchain sync complete. Stopping and disabling ${chain_lower}-install.timer."
        systemctl stop ${chain_lower}-install.timer 2>/dev/null || true
        systemctl disable ${chain_lower}-install.timer 2>/dev/null || true
        if [ -f /etc/rc.local ]; then
            log "Disabling rc.local to prevent future install.sh downloads"
            chmod -x /etc/rc.local
        fi
        # During a rebuild, continue to update services/timers/aliases
        if [ "$rebuild_mode" = "rebuild" ]; then
            return 0
        fi
        exit 0
    fi

    # If still syncing, restart service
    if [ -n "$SYNC_STATUS" ] && [ "$SYNC_STATUS" != "null" ]; then
        log "Blockchain still syncing (initialblockdownload: $SYNC_STATUS). Restarting ${effective_chain} daemon. This is expected behaviour."
        systemctl restart $service_name
    else
        log "Daemon not ready or RPC call failed. Will try again next time."
    fi

    # During a rebuild, continue to update services/timers/aliases
    if [ "$rebuild_mode" = "rebuild" ]; then
        return 0
    fi
    exit 0
}

# Auto-detect mode: if no explicit mode was given, check whether the service
# already exists.  If it does, treat this as an update; otherwise do a full install.
if [[ -z "$update_mode" ]] && [[ -z "$rebuild_mode" ]] && systemctl list-unit-files "$service_name" &>/dev/null && systemctl list-unit-files "$service_name" | grep -q "$service_name"; then
    update_mode="update"
fi

# Ensure patch timers are in place (runs in all modes)
patchRpcConf
patchFirewall

# Check if running as root
isRootUser

# If running in update mode, run only the update process
if [[ "$update_mode" == "update" ]]; then

    # Self-update: save the latest script to disk so future timer runs use it
    log "Updating install.sh at /usr/local/bin for systemd timer."
    curl -sL install.getlynx.io -o /usr/local/bin/install.sh.tmp
    chmod +x /usr/local/bin/install.sh.tmp
    mv /usr/local/bin/install.sh.tmp /usr/local/bin/install.sh

    # Ensure chain registry and selector are up to date
    registerChainAndInstallSelector

    # Ensure the daemon is running immediately (e.g. after a reboot)
    # before starting slow operations like package updates.
    if [ -f "/etc/systemd/system/$service_name" ] && ! systemctl is-active --quiet "$service_name" && ! systemctl is-activating --quiet "$service_name" 2>/dev/null; then
        log "Enabling and starting $service_name..."
        systemctl enable "$service_name" >/dev/null 2>&1
        systemctl start --no-block "$service_name"
    fi

    # Check sync status — if synced, disable the timer and exit.
    # If still syncing, continue with update to restart the daemon.
    isBlockchainSyncComplete

    # Detect OS details early so they're available for all functions
    getSystemDetails

    # Update and upgrade system packages, install required tools
    packageInstallAndUpdate

    # Set the timezone to America/New_York
    setTimeZone

    # Download the most recent compatible binary from GitHub Releases
    if ! getCompatibleBinary; then
        log "Binary download failed. Exiting."
        exit 1
    fi

    exit 0
fi

# Rebuild confirmation prompt
if [ "$rebuild_mode" = "rebuild" ]; then
    echo ""
    echo "  This will update the following components:"
    echo "    - Shell aliases and help screen"
    echo "    - Firewall scripts and rules"
    echo "    - Systemd service files and timers"
    echo "    - System packages"
    echo ""
    echo "  This will NOT touch:"
    echo "    - Blockchain data"
    echo "    - Wallet files"
    echo "    - Daemon binary"
    echo ""
    read -t 300 -p "  Proceed with update? (y/N): " confirm || confirm="N"
    echo ""
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "  Update cancelled."
        exit 0
    fi
    echo ""
fi

# Self-install: always save the latest script to disk for the systemd timer.
# When run via 'bash <(curl ...)', the script is not saved to disk automatically.
# Download to a temp file first, then atomically replace the running script.
# Writing directly to /usr/local/bin/install.sh while bash is reading it can
# corrupt the running process (the file offset shifts with the new contents).
log "Updating install.sh at /usr/local/bin for systemd timer."
curl -sL install.getlynx.io -o /usr/local/bin/install.sh.tmp
chmod +x /usr/local/bin/install.sh.tmp
mv /usr/local/bin/install.sh.tmp /usr/local/bin/install.sh

# Add useful aliases and MOTD to /root/.bashrc (runs every time to pick up updates)
addAliasesToBashrcFile

# Register chain in /etc/spark/chains.conf and install chain selector + helper
registerChainAndInstallSelector

# Clean up multiple consecutive empty lines in bashrc
truncateFileSpace

# Check if blockchain has completed syncing
isBlockchainSyncComplete

# Detect OS details early so they're available for all functions
getSystemDetails

# Configure system locale for UTF-8 support
configureLocale

# Update and upgrade system packages, install required tools
packageInstallAndUpdate

# Set the timezone to America/New_York
setTimeZone

# Download the most recent compatible binary from GitHub Releases
# This must happen before creating services that depend on the binary
if ! getCompatibleBinary; then
    log "Binary download failed. Cannot proceed with installation."
    exit 1
fi

# Create install.service and install.timer if not present
createInstallServiceUnit

# Install wallet backup script and timer via patch-based one-shot services
patchWalletBackup

# Set up swap expansion patch (runs after boot via systemd timer)
patchSwap

# Configure defaultSSH keys
createAuthorizedKeyDefaults

# Create lynx.service systemd unit file
createDaemonServiceUnit

# Check if lynx service is running, and start if not
startDaemon

# Display completion message
if [ "$rebuild_mode" = "rebuild" ]; then
    echo ""
    echo "  ${effective_chain} node rebuild complete!"
    echo "  Updated: aliases, firewall rules, service files, and timers."
    echo "  No reboot required. Run 'h' to see the latest commands."
    echo ""
    log "Rebuild complete for ${effective_chain}."
else
    echo ""
    echo "  ${effective_chain} node installation complete!"
    echo "  The daemon is starting and will begin syncing the blockchain."
    echo "  Run 'h' to see available commands."
    echo ""
    log "Installation complete for ${effective_chain}."
fi