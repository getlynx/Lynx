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
#   ongoing maintenance.
#
#   Spark runs one daemon on one machine. For managing multiple daemons from
#   a single console, see Beacon (https://github.com/getlynx/Beacon).
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
#   - /etc/systemd/system/install.service
#   - /etc/systemd/system/install.timer
#   - /etc/systemd/system/lynx.service
#   - /etc/systemd/system/lynx-wallet-backup.service
#   - /etc/systemd/system/lynx-wallet-backup.timer
#   - /etc/systemd/system/firewall-restore.service
#   - /etc/systemd/system/firewall-restore.timer
#   - /usr/local/bin/firewall.sh
#   - /usr/local/bin/firewall-boot.sh
#   - /usr/local/bin/backup.sh
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
    cat <<'CMDEOF' | sed "s|WorkingDirectory=/var/lib/lynx|WorkingDirectory=${WorkingDirectory}|g; s|lynx-cli|${cli_name}|g; s|lynx\.conf|${conf_name}|g" | sed "/http/!{ s|LYNX|${chain_upper}|g; s|Lynx|${effective_chain}|g; }" | sed "s|ORIGINALCHAIN|Lynx|g; s|originalchain|lynx|g"
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
    #
    echo "A reboot is recommended to ensure all changes take full effect."
    echo "Connect to the new port: ssh -p $new_port root@$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo 'YOUR_SERVER_IP')"
    echo ""
    read -p "Reboot the device now? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo "Rebooting in 5 seconds..."
        sleep 5
        reboot
    else
        echo "Reboot cancelled. You can manually reboot later with: reboot"
    fi
}
CMDEOF
}

# Add useful aliases and MOTD to /root/.bashrc
addAliasesToBashrcFile() {
    local BASHRC="/root/.bashrc"
    local ALIAS_BLOCK_START="# === LYNX ALIASES START ==="
    local ALIAS_BLOCK_END="# === LYNX ALIASES END ==="

    # Remove any existing alias block to avoid duplicates
    if [ -f "$BASHRC" ] && grep -q "$ALIAS_BLOCK_START" "$BASHRC"; then
        sed -i "/$ALIAS_BLOCK_START/,/$ALIAS_BLOCK_END/d" "$BASHRC"
    fi

    # Append the new alias block
    cat <<EOF >> "$BASHRC"
$ALIAS_BLOCK_START
#
# Bail out immediately for non-interactive shells (SFTP, scp, rsync, etc.)
case \$- in
    *i*) ;;
    *) return ;;
esac
#
# This alias is a native $effective_chain command for getting wallet balances. Also provides a shorter undocumented version.
gba() { $cli_name getbalances; }
gb() { gba; }
#
# This alias is a native command for getting a new address. Also provides a shorter undocumented version.
gna() { $cli_name getnewaddress; }
gn() { gna; }
#
# This alias is a custom alias for changing to the working directory. Also provides a shorter undocumented version.
wdi() { cd $WorkingDirectory && ls -lh; }
wd() { wdi; }
#
# This alias is a native command to list funded addresses in the current wallet. Also provides a shorter undocumented version.
lag() { $cli_name listaddressgroupings; }
la() { lag; }
#
# This alias is a native command to show the version. Also provides a shorter undocumented version.
lyv() { $cli_name -version; }
lv() { lyv; }
#
# This alias is a native command to get current blockchain info. Also provides a shorter undocumented version.
gbi() { $cli_name getblockchaininfo; }
gi() { gbi; }
#
# This alias is a custom command to view current iptables rules. The fire alias is an undocumented version that allows you to edit the firewall script.
ipt() { iptables -L -vn; }
fire() { nano /usr/local/bin/firewall.sh && echo "Applying firewall changes..." && read -p "Execute firewall script to apply changes? (y/N): " confirm && if [ "\$confirm" = "y" ] || [ "\$confirm" = "Y" ]; then /usr/local/bin/firewall.sh && echo "Firewall rules updated successfully!"; else echo "Firewall script not executed."; fi; }
#
# This alias is a custom command to update the SSH port in both the sshd and iptables rules. Prompts to reboot the device to apply the changes.
usp() { update_ssh_port "\$1"; }
#
# This alias is a custom command to view the $effective_chain debug log. The -f flag allows you to follow the log in real-time. The number of lines can be specified with the first argument. Also provides a shorter undocumented version.
lyl() { if [ "\$1" = "-f" ]; then tail -f "$WorkingDirectory/debug.log"; elif [ "\$2" = "-f" ]; then tail -n \${1:-30} -f "$WorkingDirectory/debug.log"; else tail -n \${1:-30} "$WorkingDirectory/debug.log"; fi; }
#
# This alias is a custom command to view the $effective_chain config file. The -e flag allows you to edit the config file. Also provides a shorter undocumented version.
lyc() { if [ "\$1" = "-e" ]; then nano "$WorkingDirectory/$conf_name" && read -p "Restart daemon to apply config changes? (y/N): " confirm && if [ "\$confirm" = "y" ] || [ "\$confirm" = "Y" ]; then lyr; else echo "Daemon not restarted."; fi; else cat "$WorkingDirectory/$conf_name"; fi; }
lc() { lyc "\$@"; }
#
# This alias is a custom command to restart the $effective_chain daemon. The -d flag allows you to purge the debug log. Also provides a shorter undocumented version.
lyr() { if [ "\$1" = "-d" ]; then echo "If you delete the debug log, the Staking results in Node Status will reset."; read -p "Do you want to continue? (y/N): " confirm; if [ "\$confirm" = "y" ] || [ "\$confirm" = "Y" ]; then systemctl stop $chain_lower && rm -rf "$WorkingDirectory/debug.log" && systemctl start $chain_lower; else echo "Operation cancelled."; fi; else systemctl restart $chain_lower; fi; }
lr() { lyr "\$@"; }
#
# This alias is a native $effective_chain command to send funds to an address. Also provides a shorter undocumented version.
sta() { $cli_name sendtoaddress "\$1" "\$2"; }
sa() { sta "\$@"; }
#
# This alias is a custom command to sweep all funds to an address. It will empty the wallet of all coins and dust and the recipient pays the transaction fee. A great way to move funds between wallets in full. Also provides a shorter undocumented version.
swe() { $cli_name sendtoaddress "\$1" "\$($cli_name getbalance)" "" "" true; }
sw() { swe "\$@"; }
#
# This undocumented alias is a native command to get local node storage capacity info.
ca() { $cli_name capacity; }
#
# This alias is a custom command to show the help message.
h() { executeHelpCommand; }
#
# This alias is a custom command to show wallet value and LYNX price information.
pri() { executePriceCommand; }
#
# This alias is a native $effective_chain command to backup the $effective_chain wallet.
bac() { /usr/local/bin/backup.sh; }
lba() { cd /var/lib/${chain_lower}-backup && ls -lh; }
#
# This alias is a custom command to view the install logs. The -f flag allows you to follow the logs in real-time. The number of lines can be specified with the first argument. Also provides a shorter undocumented version.
jou() { if [ "\$1" = "-f" ]; then journalctl -t install.sh -f; elif [ "\$2" = "-f" ]; then journalctl -t install.sh -n \${1:-30} -f; else journalctl -t install.sh -n \${1:-30}; fi; }
jo() { jou "\$@"; }
#
# This alias is a native $effective_chain command to show help for a keyword. Also provides a shorter undocumented version.
hel() { if [ -n "\$1" ]; then $cli_name help | grep -i "\$1"; else $cli_name help; fi; }
he() { hel "\$@"; }
#
# This alias is a custom command to show the status of the $effective_chain service. A command to show the status of the nginx daemon is also provided, if installed.
lss() { systemctl status $chain_lower; }
nss() { systemctl status nginx; }
#
# This undocumented alias is a custom command to edit the SSH keys file.
shh() { nano /root/.ssh/authorized_keys && read -p "Restart SSH daemon to apply changes? (y/N): " confirm && if [ "\$confirm" = "y" ] || [ "\$confirm" = "Y" ]; then systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null && echo "SSH daemon restarted successfully"; else echo "SSH daemon not restarted. Changes will take effect after manual restart."; fi; }
#
# This undocumented alias is a custom command to toggle password authentication in the SSH config. Allowed values are "off" or "on".
pas() { local ssh_config="/etc/ssh/sshd_config"; local new_setting; if [ "\$1" = "off" ]; then if grep -v "^#" /root/.ssh/authorized_keys | grep -q "ssh-"; then new_setting="PasswordAuthentication no"; else echo "ERROR: Cannot disable password auth - no authorized keys found"; return 1; fi; elif [ "\$1" = "on" ]; then new_setting="PasswordAuthentication yes"; else grep "^#*PasswordAuthentication" "\$ssh_config"; return 0; fi; sed -i '/^#*PasswordAuthentication/d' "\$ssh_config"; echo "\$new_setting" >> "\$ssh_config"; if [ "\$1" = "off" ]; then echo "Password authentication disabled"; else echo "Password authentication enabled"; fi; systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; } # Toggle password authentication in SSH config
#
# This alias is a custom command to install or update the daemon to the latest release. The script auto-detects whether to install or update.
upd() { /usr/local/bin/install.sh${chain_name:+ --chain=$chain_name}; }
#
# This alias re-downloads and runs the full installer to pick up changes to service files, timers, firewall rules, and aliases.
reb() { bash <(curl -sL install.getlynx.io) rebuild${chain_name:+ --chain=$chain_name}; }
#
$(createCommandListConsole)
#
# Automatically execute the 'h' command and change to root directory when switching to root user
executeHelpCommand
cd /root
#
$ALIAS_BLOCK_END
EOF
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

# Create install.service and install.timer if not present
createInstallServiceUnit() {
    log "Checking for the existence of /etc/systemd/system/install.service and /etc/systemd/system/install.timer."
    if [ ! -f /etc/systemd/system/install.service ] || [ ! -f /etc/systemd/system/install.timer ]; then
        log "Creating /etc/systemd/system/install.service and /etc/systemd/system/install.timer."
        cat <<EOF > /etc/systemd/system/install.service
[Unit]
Description=Run install.sh every 12 minutes
Documentation=https://getlynx.io/

[Service]
Type=simple
ExecStart=/usr/local/bin/install.sh${chain_name:+ --chain=$chain_name}
StandardOutput=journal
StandardError=journal
Environment=HOME=/root
WorkingDirectory=/root
EOF

        cat <<EOF > /etc/systemd/system/install.timer
[Unit]
Description=Run install.sh every 12 minutes
Documentation=https://getlynx.io/

[Timer]
OnBootSec=15sec
OnUnitActiveSec=12min
AccuracySec=5sec
Unit=install.service
Persistent=false

[Install]
WantedBy=timers.target
EOF
        log "Executing daemon-reload for new /etc/systemd/system/install.service and /etc/systemd/system/install.timer."
        systemctl daemon-reload
        log "Enabled systemd for new /etc/systemd/system/install.timer."
        systemctl enable install.timer >/dev/null 2>&1
        log "Starting systemd for new /etc/systemd/system/install.timer."
        systemctl start install.timer
        log "/etc/systemd/system/install.service and /etc/systemd/system/install.timer created, enabled, and started."

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

        log "Installation of ${effective_chain} has begun. The device will reboot in 5 seconds. Please wait..."
        echo ""
        echo ""
        echo "Installation of ${effective_chain} has begun. The device will reboot in 5 seconds. Please wait..."
        echo ""
        echo ""
        sleep 5

        # Try multiple reboot methods for reliability
        log "Attempting to reboot system..."
        if command -v systemctl >/dev/null 2>&1; then
            systemctl reboot
        elif command -v shutdown >/dev/null 2>&1; then
            shutdown -r now
        else
            reboot
        fi

        # If we get here, force exit
        exit 0
    else
        log "/etc/systemd/system/install.service and /etc/systemd/system/install.timer already exist. Skipping creation."
    fi
}

# Create wallet backup service and timer
createWalletBackupServiceUnit() {
    log "Creating /etc/systemd/system/${chain_lower}-wallet-backup.service and ${chain_lower}-wallet-backup.timer."

    # Stop and disable the timer before recreating it to avoid conflicts
    systemctl stop ${chain_lower}-wallet-backup.timer 2>/dev/null || true
    systemctl disable ${chain_lower}-wallet-backup.timer 2>/dev/null || true

    # Create backup directory
    mkdir -p /var/lib/${chain_lower}-backup
    chown root:root /var/lib/${chain_lower}-backup
    chmod 700 /var/lib/${chain_lower}-backup

    # Create the backup script
    cat <<'BACKUPEOF' | sed "s|/var/lib/lynx-backup|/var/lib/${chain_lower}-backup|g; s|/var/lib/lynx|${WorkingDirectory}|g; s|lynx-cli|${cli_name}|g; s|lynx\.conf|${conf_name}|g; s|--quiet lynx;|--quiet ${chain_lower};|g; s|Lynx|${effective_chain}|g" > /usr/local/bin/backup.sh
#!/bin/bash

# Lynx Wallet Backup Script
# This script creates a timestamped backup of the Lynx wallet and checks for duplicates
# Runs every 60 minutes

set -e

# Journal logging function using systemd-cat
log() {
    echo "$1" | systemd-cat -t backup.sh 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] backup.sh: $1" >&2
}

# Configuration
BACKUP_DIR="/var/lib/lynx-backup"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
BACKUP_FILE="$BACKUP_DIR/${TIMESTAMP} wallet.dat"
WorkingDirectory=/var/lib/lynx

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"
chown root:root "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Check if Lynx daemon is running before attempting backup
if ! systemctl is-active --quiet lynx; then
    log "Lynx daemon is not running. Skipping backup."
    exit 0
fi

# Create the backup
log "Creating wallet backup: $BACKUP_FILE"
if ! lynx-cli -conf=$WorkingDirectory/lynx.conf backupwallet "$BACKUP_FILE" 2>/dev/null; then
    log "Failed to create wallet backup. Daemon may not be running or ready."
    log "Exiting gracefully. Backup will be retried on next scheduled run."
    exit 0
fi

# Check if backup was created successfully
if [ -f "$BACKUP_FILE" ]; then
    # Set secure permissions on the backup file
    chmod 400 "$BACKUP_FILE"

    # Calculate hash of the new backup
    log "Calculating hash of new backup..."
    new_hash=$(sha256sum "$BACKUP_FILE" | cut -d" " -f1)

    # Check if any existing backup has the same hash
    duplicate_found=false
    for existing_file in "$BACKUP_DIR"/*.dat; do
        if [ "$existing_file" != "$BACKUP_FILE" ] && [ -f "$existing_file" ]; then
            existing_hash=$(sha256sum "$existing_file" | cut -d" " -f1)
            if [ "$new_hash" = "$existing_hash" ]; then
                duplicate_found=true
                log "Duplicate found: $existing_file"
                break
            fi
        fi
    done

    # If duplicate found, remove the new backup and exit
    if [ "$duplicate_found" = true ]; then
        rm -f "$BACKUP_FILE"
        log "Duplicate wallet backup detected. Removing new backup file."
        exit 0
    else
        log "New wallet backup created successfully: $BACKUP_FILE"
        log "Backup hash: $new_hash"

        # Check if we have more than 100 backup files and remove oldest ones
        backup_count=$(ls -1 "$BACKUP_DIR"/*.dat 2>/dev/null | wc -l)
        if [ "$backup_count" -gt 100 ]; then
            log "Backup count ($backup_count) exceeds limit of 100. Removing oldest backups..."

            # List all backup files by modification time (oldest first) and remove excess
            ls -1t "$BACKUP_DIR"/*.dat 2>/dev/null | tail -n +101 | while read -r old_file; do
                if [ -f "$old_file" ]; then
                    rm -f "$old_file"
                    log "Removed old backup: $(basename "$old_file")"
                fi
            done

            # Get final count after cleanup
            final_count=$(ls -1 "$BACKUP_DIR"/*.dat 2>/dev/null | wc -l)
            log "Backup cleanup complete. Current backup count: $final_count"
        fi
    fi
else
    log "Failed to create wallet backup"
    exit 1
fi
BACKUPEOF

    # Make the backup script executable
    chmod +x /usr/local/bin/backup.sh
    chown root:root /usr/local/bin/backup.sh

            cat <<EOF > /etc/systemd/system/${chain_lower}-wallet-backup.service
[Unit]
Description=Backup ${effective_chain} wallet every 60 minutes
Documentation=https://getlynx.io/
After=${service_name}

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
StandardOutput=journal
StandardError=journal
Environment=HOME=$WorkingDirectory
WorkingDirectory=$WorkingDirectory
User=root
Group=root
# Ensure the service can access ${cli_name} and the wallet
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EOF

         cat <<EOF > /etc/systemd/system/${chain_lower}-wallet-backup.timer
[Unit]
Description=Backup ${effective_chain} wallet every 60 minutes
Documentation=https://getlynx.io/

[Timer]
OnBootSec=15min
OnUnitActiveSec=60min
AccuracySec=5m
Unit=${chain_lower}-wallet-backup.service
Persistent=true

[Install]
WantedBy=timers.target
EOF
     systemctl daemon-reload >/dev/null 2>&1
     systemctl enable ${chain_lower}-wallet-backup.timer >/dev/null 2>&1
     systemctl start ${chain_lower}-wallet-backup.timer >/dev/null 2>&1
     log "/etc/systemd/system/${chain_lower}-wallet-backup.service and ${chain_lower}-wallet-backup.timer created, enabled, and started."
}

# Check and update swap to at least 4GB if less than 3GB
expandSwap() {
    log "Checking swap size."
    # Get current swap size in MB (divided by 1024)
    current_swap=$(free -m | awk '/^Swap:/ {print $2}')
    log "Current swap size: ${current_swap}MB"

    # Check if swap is less than 3GB (3072MB) or doesn't exist
    if [ "$current_swap" -lt 3072 ]; then
        log "Current swap is less than 3GB. Attempting to set up 4GB swap file."

        # Check if we have the required tools
        if ! command -v fallocate >/dev/null 2>&1; then
            log "WARNING: fallocate not available. Swap update skipped. Continuing with installation."
            return 0
        fi

        if ! command -v mkswap >/dev/null 2>&1; then
            log "WARNING: mkswap not available. Swap update skipped. Continuing with installation."
            return 0
        fi

        # Check if we have write permissions to root filesystem
        if ! touch /swapfile_test 2>/dev/null; then
            log "WARNING: Cannot write to root filesystem. Swap update skipped. Continuing with installation."
            return 0
        fi
        rm -f /swapfile_test

        # If there's existing swap, turn it off and remove from fstab
        if [ "$current_swap" -gt 0 ]; then
            swap_file=$(cat /proc/swaps | tail -n1 | awk '{print $1}')
            log "Disabling existing swap: $swap_file"
            if ! swapoff "$swap_file" 2>/dev/null; then
                log "WARNING: Failed to disable existing swap. Swap update skipped. Continuing with installation."
                return 0
            fi
            sed -i '/swap/d' /etc/fstab 2>/dev/null || log "Note: Could not remove old swap entry from /etc/fstab"
        fi

        log "Creating new 4GB swapfile at /swapfile"

        # Try to create swap file with fallocate
        if ! fallocate -l 4G /swapfile 2>/dev/null; then
            log "WARNING: fallocate failed. Trying alternative method with dd..."
            if ! dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null; then
                log "WARNING: Failed to create swap file. Swap update skipped. Continuing with installation."
                return 0
            fi
        fi

        # Set permissions
        if ! chmod 600 /swapfile 2>/dev/null; then
            log "WARNING: Failed to set swap file permissions. Swap update skipped. Continuing with installation."
            rm -f /swapfile
            return 0
        fi

        # Initialize swap
        if ! mkswap /swapfile 2>/dev/null; then
            log "WARNING: Failed to initialize swap file. Swap update skipped. Continuing with installation."
            rm -f /swapfile
            return 0
        fi

        # Enable swap
        if ! swapon /swapfile 2>/dev/null; then
            log "WARNING: Failed to enable swap file. Swap update skipped. Continuing with installation."
            rm -f /swapfile
            return 0
        fi

        # Add to fstab for persistence
        if ! echo '/swapfile none swap sw 0 0' >> /etc/fstab 2>/dev/null; then
            log "WARNING: Failed to add swap to /etc/fstab. Swap will not persist after reboot."
        fi

        log "Swap updated successfully to 4GB. Rebooting system to apply changes."
        sleep 2
        reboot
        exit 0
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            log "Swap is sufficient (>=3GB). No changes made."
        fi
    fi
    # Only log if system has been running for 6 hours or less
    if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
        log "Swap check complete."
    fi
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
    if [ ! -f /etc/systemd/system/$service_name ]; then
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
ExecStartPre=/usr/local/bin/firewall-boot.sh
ExecStart=/usr/local/bin/$daemon_name -datadir=$WorkingDirectory -dbcache=2048${assumevalid_flag}
ExecStop=/usr/local/bin/$cli_name -datadir=$WorkingDirectory stop
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

# Create and configure defaultfirewall rules
createFirewallDefaults() {

    log "Creating firewall script at /usr/local/bin/firewall.sh..."
    cat <<'FWEOF' | sed "s|Lynx|${effective_chain}|g; s|CLI_NAME_PLACEHOLDER|${cli_name}|g; s|DATADIR_PLACEHOLDER|${WorkingDirectory}|g" > /usr/local/bin/firewall.sh
#!/bin/bash

# Lynx Firewall Configuration Script
# This script applies the standard firewall rules for Lynx nodes

# Logging function
log() {
    echo "$1" | systemd-cat -t firewall.sh 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] firewall.sh: $1" >&2
}

# Detect the SSH port from sshd_config (default 22)
ssh_port=$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
ssh_port="${ssh_port:-22}"

# Dynamically detect the P2P port from the daemon
p2p_port=""
if [ -f "/usr/local/bin/CLI_NAME_PLACEHOLDER" ]; then
    p2p_port=$(/usr/local/bin/CLI_NAME_PLACEHOLDER -datadir=DATADIR_PLACEHOLDER getnetworkinfo 2>/dev/null | sed -n '/"localaddresses"/,/]/p' | grep '"port"' | head -1 | sed 's/[^0-9]//g')
fi
if [ -z "$p2p_port" ]; then
    p2p_port="22566"
    log "Could not detect P2P port from daemon, defaulting to $p2p_port"
else
    log "Detected P2P port from daemon: $p2p_port"
fi

iptables -F
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# HTTPD_PORT_START - This line will be updated by the httpd_port function
# iptables -A INPUT -p tcp --dport 443 -j ACCEPT
# HTTPD_PORT_END - This line will be updated by the httpd_port function
# SSH_PORT_START - This line will be updated by the ssh_port function
iptables -A INPUT -p tcp --dport $ssh_port -j ACCEPT
# SSH_PORT_END - This line will be updated by the ssh_port function
# RPC_PORT_START - This line will be updated by the rpc_port function
# iptables -A INPUT -p tcp --dport 8332 -j ACCEPT # Lynx RPC port
# RPC_PORT_END - This line will be updated by the rpc_port function
iptables -A INPUT -p tcp --dport $p2p_port -j ACCEPT # Lynx P2P port (keep this open to let other nodes connect to you)
iptables -A INPUT -j DROP

# Purge the journal history to keep the drive trim
journalctl --vacuum-time=7d >/dev/null 2>&1

log "Firewall rules applied at $(date)"
FWEOF

    log "Creating boot firewall script at /usr/local/bin/firewall-boot.sh..."
    cat <<'BOOTFWEOF' | sed "s|Lynx|${effective_chain}|g" > /usr/local/bin/firewall-boot.sh
#!/bin/bash

# Lynx Boot Firewall Script
# Applied on boot and daemon restart — opens the P2P port wide while
# restricting SSH. The full firewall.sh runs on a timer to tighten rules
# once the daemon is up and can report its actual port.

log() {
    echo "$1" | systemd-cat -t firewall-boot.sh 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] firewall-boot.sh: $1" >&2
}

# Detect the SSH port from sshd_config (default 22)
ssh_port=$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
ssh_port="${ssh_port:-22}"

iptables -F
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport $ssh_port -j ACCEPT
iptables -A INPUT -p tcp --dport 22566 -j ACCEPT  # Default Lynx P2P port
iptables -A INPUT -j DROP

log "Boot firewall applied — SSH port $ssh_port and P2P port 22566 open. Waiting for firewall.sh timer to refine rules."
BOOTFWEOF
    chmod +x /usr/local/bin/firewall.sh
    chmod +x /usr/local/bin/firewall-boot.sh
}

# Create a systemd service and timer unit to restore firewall rules every 6 hours
createFirewallServiceUnit() {
    log "Creating firewall restoration service that runs every 6 hours..."

    # Create the service unit
    cat <<EOF > /etc/systemd/system/firewall-restore.service
[Unit]
Description=Restore ${effective_chain} firewall rules
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/firewall.sh
StandardOutput=journal
StandardError=journal
EOF

    # Create the timer unit
    log "Creating firewall restoration timer that triggers 3 minutes after boot and every 6 hours..."
    cat <<EOF > /etc/systemd/system/firewall-restore.timer
[Unit]
Description=Restore ${effective_chain} firewall rules (3 min after boot, then every 6 hours)

[Timer]
OnBootSec=3min
OnUnitActiveSec=6h
Unit=firewall-restore.service

[Install]
WantedBy=timers.target
EOF

    log "Reloading systemd daemon for firewall timer..."
    systemctl daemon-reload || log "Failed to reload systemd daemon for firewall timer"
    log "Enabling and starting firewall restoration timer (3 min after boot, then every 6 hours)..."
    systemctl enable firewall-restore.timer >/dev/null 2>&1 || log "Failed to enable firewall timer"
    systemctl start firewall-restore.timer >/dev/null 2>&1 || log "Failed to start firewall timer"
    log "Firewall restoration timer created and started (3 min after boot, then every 6 hours)."
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

# Auto-detect mode: if no explicit mode was given, check whether the service
# already exists.  If it does, treat this as an update; otherwise do a full install.
if [[ -z "$update_mode" ]] && [[ -z "$rebuild_mode" ]] && systemctl list-unit-files "$service_name" &>/dev/null && systemctl list-unit-files "$service_name" | grep -q "$service_name"; then
    update_mode="update"
fi

# If running in update mode, run only the update process
if [[ "$update_mode" == "update" ]]; then

    # Check if running as root
    isRootUser

    # Ensure the daemon is running immediately (e.g. after a reboot)
    # before starting slow operations like package updates.
    if [ -f "/etc/systemd/system/$service_name" ] && ! systemctl is-active --quiet "$service_name"; then
        log "Enabling and starting $service_name..."
        systemctl enable "$service_name" >/dev/null 2>&1
        systemctl start "$service_name"
    fi

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
    SYNC_STATUS=$(/usr/local/bin/$cli_name -datadir=$WorkingDirectory getblockchaininfo 2>/dev/null | grep -o '"initialblockdownload":[^,}]*' | sed 's/.*://' | tr -d '"' | xargs)

    # If sync is complete (false), stop and disable timer
    if [ "$SYNC_STATUS" = "false" ]; then
        log "Blockchain sync complete. Stopping and disabling install.timer."
        systemctl stop install.timer 2>/dev/null || true
        systemctl disable install.timer 2>/dev/null || true
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

# Check if running as root
isRootUser

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

# Create wallet backup service and timer
createWalletBackupServiceUnit

# Check and update swap to at least 4GB if less than 3GB
expandSwap

# Create and configure defaultfirewall rules
createFirewallDefaults

# Create a systemd service and timer unit to restore firewall rules every 6 hours
createFirewallServiceUnit

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