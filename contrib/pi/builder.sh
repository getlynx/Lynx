#!/bin/bash
set -euo pipefail

################################################################################
# LYNX NODE BUILDER SCRIPT
################################################################################
#
# PURPOSE:
#   This script automates the setup and maintenance of a Lynx cryptocurrency node
#   on ARM-based systems (Raspberry Pi, ARM64 servers, etc.). It handles the
#   complete lifecycle from initial setup to ongoing maintenance.
#
# AUTHOR: Lynx Development Team
# VERSION: 2.0
# LAST UPDATED: 2025
# DOCUMENTATION: https://docs.getlynx.io/
#
################################################################################
#
# FUNCTIONALITY OVERVIEW:
#   This script performs the following operations in sequence:
#
#   1. SYSTEM SETUP:
#      - Creates systemd timer (builder.timer) to run every 12 minutes
#      - Sets up 4GB swap file if current swap is less than 3GB
#      - Installs Lynx ARM binaries if not present
#      - Creates systemd service (lynx.service) for the Lynx daemon
#
#   2. USER EXPERIENCE:
#      - Adds convenient aliases to ~/.bashrc for common Lynx operations
#      - Creates a beautiful MOTD (Message of the Day) with node status
#      - Provides quick access to wallet commands, system monitoring, and logs
#
#   3. NODE MAINTENANCE:
#      - Ensures Lynx daemon is running
#      - Monitors blockchain synchronization status
#      - Automatically restarts daemon during sync
#      - Disables timer once sync is complete
#
################################################################################
#
# ALIASES CREATED (type 'motd' to see all):
#   WALLET COMMANDS:
#     gb    - Get wallet balances
#     gna   - Generate new address
#     lag   - List address groupings
#     sta   - Send to address
#     swe   - Sweep a wallet (send all funds)
#
#   SYSTEM COMMANDS:
#     lv    - Show Lynx version
#     lyc   - Edit Lynx config file
#     lyl   - View Lynx debug log (real-time)
#     lynx  - Restart Lynx daemon
#     jou   - View builder script logs
#     gbi   - Get blockchain info
#     lelp  - Show Lynx help
#     stat  - Check Lynx service status
#
#   USEFUL COMMANDS:
#     htop  - Monitor system resources
#     motd  - Show help message again
#
################################################################################
#
# SYSTEM REQUIREMENTS:
#   - ARM architecture (aarch64 or arm*)
#   - Debian/Ubuntu-based system
#   - Root privileges
#   - Internet connection
#   - Minimum 4GB RAM recommended
#
# DEPENDENCIES:
#   - systemd
#   - wget, curl, unzip
#   - fallocate, mkswap, swapon
#   - logger (for system logging)
#
################################################################################
#
# INSTALLATION:
#   This script is typically downloaded and executed by iso-builder.sh during
#   the initial system setup. It can also be run manually:
#
#   wget -O /usr/local/bin/builder.sh https://raw.githubusercontent.com/getlynx/Lynx/refs/heads/main/contrib/pi/builder.sh
#   chmod +x /usr/local/bin/builder.sh
#   /usr/local/bin/builder.sh
#
################################################################################
#
# OPERATION MODES:
#   - INITIAL SETUP: Creates all necessary files and services
#   - MAINTENANCE: Runs every 12 minutes via systemd timer
#   - SYNC MONITORING: Checks blockchain sync status and manages daemon
#
# LOGGING:
#   - All operations are logged to systemd journal
#   - View logs: journalctl -t builder.sh -f
#   - Logging is reduced after 6 hours of uptime to prevent spam
#
################################################################################
#
# SECURITY FEATURES:
#   - All file operations use proper permissions
#   - Systemd services run with appropriate security contexts
#   - Swap file has restricted permissions (600)
#
################################################################################
#
# TROUBLESHOOTING:
#   - Check service status: systemctl status lynx
#   - View debug logs: tail -f $WorkingDirectory/debug.log
#   - Check builder logs: journalctl -t builder.sh -f
#   - Restart daemon: systemctl restart lynx
#   - Manual sync check: lynx-cli getblockchaininfo
#
################################################################################
#
# NETWORK PORTS:
#   - Lynx daemon typically uses port 22566 (configurable in lynx.conf)
#   - RPC typically uses port 8332 (configurable in lynx.conf)
#
# FILES CREATED:
#   - /etc/systemd/system/builder.service
#   - /etc/systemd/system/builder.timer
#   - /etc/systemd/system/lynx.service
#   - /swapfile (if needed)
#   - ~/.bashrc (aliases added)
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

# Set the working directory variable for use throughout the script
WorkingDirectory=/var/lib/lynx

# Create the Lynx data directory with proper permissions
mkdir -p $WorkingDirectory
chown root:root $WorkingDirectory
chmod 755 $WorkingDirectory

# Create symbolic link for backward compatibility with legacy configurations
# This ensures that any scripts or tools expecting ~/.lynx will still work
if [ ! -e /root/.lynx ]; then
    ln -sf $WorkingDirectory /root/.lynx
fi

# Get system uptime in seconds for conditional logging
uptime_seconds=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)
# Threshold for conditional logging (6 hours = 21600 seconds)
log_threshold_seconds=21600

# Function to create a nicely formatted MOTD function
create_motd_function() {
    cat <<'EOF'
# Function to display Lynx aliases in a nicely formatted MOTD
show_lynx_motd() {
    echo ""
    WorkingDirectory=/var/lib/lynx
    # Count stakes won in the last 24 hours
    stakes_won=$(grep "New proof-of-stake block found" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d '24 hours ago' '+%Y-%m-%d')" | wc -l)
    if [ -z "$stakes_won" ] || [ "$stakes_won" = "0" ]; then
        stakes_won=$(grep "New proof-of-stake block found" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date '+%Y-%m-%d')" | wc -l)
    fi

    # Calculate dynamic spacing for "Stakes won in last 24 hours" display
    # Formula: 28 - stakes_digits = spaces needed (28 is the base spacing for 1 digit)
    stakes_digits=${#stakes_won}
    spaces_needed=$((28 - stakes_digits))
    spacing=$(printf '%*s' "$spaces_needed" '')

    # Count total blocks (UpdateTip) in the last 24 hours for yield calculation
    total_blocks=$(grep "UpdateTip" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d '24 hours ago' '+%Y-%m-%d')" | wc -l)
    if [ -z "$total_blocks" ] || [ "$total_blocks" = "0" ]; then
        total_blocks=$(grep "UpdateTip" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date '+%Y-%m-%d')" | wc -l)
    fi

    # Calculate percent yield (stakes won / total blocks * 100)
    if [ "$total_blocks" -gt 0 ]; then
        # Use awk for floating point arithmetic with 3 decimal places
        percent_yield=$(awk "BEGIN {printf \"%.3f\", $stakes_won * 100 / $total_blocks}" 2>/dev/null || echo "0.000")
    else
        percent_yield="0.000"
    fi

    # Calculate dynamic spacing for "Yield rate" display
    # Formula: 28 - yield_digits = spaces needed (28 is the base spacing for 6 digits: "0.000")
    yield_numeric=$(echo "$percent_yield" | sed 's/%//')
    yield_digits=${#yield_numeric}
    spaces_needed=$((28 - yield_digits))
    yield_spacing=$(printf '%*s' "$spaces_needed" '')

    # Count stakes won in the last 7 days
    stakes_won_7d=$(grep "New proof-of-stake block found" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d '7 days ago' '+%Y-%m-%d')" | wc -l)
    if [ -z "$stakes_won_7d" ] || [ "$stakes_won_7d" = "0" ]; then
        # Try to get stakes from the last 7 days by checking each day
        stakes_won_7d=0
        for i in {1..7}; do
            daily_stakes=$(grep "New proof-of-stake block found" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d "$i days ago" '+%Y-%m-%d')" | wc -l)
            stakes_won_7d=$((stakes_won_7d + daily_stakes))
        done
    fi

    # Calculate dynamic spacing for "Stakes won in last 7 days" display
    # Formula: 30 - stakes_7d_digits = spaces needed (30 is the base spacing for 1 digit)
    stakes_7d_digits=${#stakes_won_7d}
    spaces_needed=$((30 - stakes_7d_digits))
    spacing_7d=$(printf '%*s' "$spaces_needed" '')

    # Count total blocks (UpdateTip) in the last 7 days for yield calculation
    total_blocks_7d=$(grep "UpdateTip" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d '7 days ago' '+%Y-%m-%d')" | wc -l)
    if [ -z "$total_blocks_7d" ] || [ "$total_blocks_7d" = "0" ]; then
        # Try to get blocks from the last 7 days by checking each day
        total_blocks_7d=0
        for i in {1..7}; do
            daily_blocks=$(grep "UpdateTip" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d "$i days ago" '+%Y-%m-%d')" | wc -l)
            total_blocks_7d=$((total_blocks_7d + daily_blocks))
        done
    fi

    # Calculate percent yield for 7 days (stakes won / total blocks * 100)
    if [ "$total_blocks_7d" -gt 0 ]; then
        # Use awk for floating point arithmetic with 3 decimal places
        percent_yield_7d=$(awk "BEGIN {printf \"%.3f\", $stakes_won_7d * 100 / $total_blocks_7d}" 2>/dev/null || echo "0.000")
    else
        percent_yield_7d="0.000"
    fi

    # Calculate dynamic spacing for "7-day yield rate" display
    # Formula: 22 - yield_7d_digits = spaces needed (22 is the base spacing for 5 digits)
    yield_7d_numeric=$(echo "$percent_yield_7d" | sed 's/%//')
    yield_7d_digits=${#yield_7d_numeric}
    spaces_needed=$((22 - yield_7d_digits))
    yield_7d_spacing=$(printf '%*s' "$spaces_needed" '')

    # Count immature UTXOs (confirmations < 31)
    immature_utxos=$(lynx-cli listunspent 2>/dev/null | grep confirmations | sed 's/.*"confirmations": \([0-9]*\).*/\1/' | awk '$1 < 31' | wc -l)
    if [ -z "$immature_utxos" ]; then
        immature_utxos="0"
    fi

    # Calculate dynamic spacing for "Immature UTXOs" display
    # Formula: 20 - immature_digits = spaces needed (20 is the base spacing for 1 digit)
    immature_digits=${#immature_utxos}
    spaces_needed=$((20 - immature_digits))
    immature_spacing=$(printf '%*s' "$spaces_needed" '')

    # Get current wallet balance
    wallet_balance=$(lynx-cli getbalance 2>/dev/null || echo "0")
    if [ -z "$wallet_balance" ]; then
        wallet_balance="0"
    fi

    # Calculate dynamic spacing for "Current wallet balance" display
    # Formula: 33 - balance_digits = spaces needed (33 is the base spacing for 10 digits)
    balance_digits=${#wallet_balance}
    spaces_needed=$((33 - balance_digits))
    balance_spacing=$(printf '%*s' "$spaces_needed" '')

    # Get Lynx version for display
    lynx_version=$(lynx-cli -version 2>/dev/null | head -1 || echo "Unknown")
    if [ -z "$lynx_version" ]; then
        lynx_version="Unknown"
    fi

    # Calculate dynamic spacing for "Lynx Version" display
    # Formula: 45 - version_digits = spaces needed (45 is the base spacing for short versions)
    version_digits=${#lynx_version}
    spaces_needed=$((45 - version_digits))
    version_spacing=$(printf '%*s' "$spaces_needed" '')

    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    🦊 LYNX NODE COMMANDS 🦊                    ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo "║  NODE STATUS:                                                  ║"
    echo "║    🎯 Stakes won in last 24 hours: $stakes_won$spacing║"
    echo "║    📊 Yield rate (stakes/blocks): ${percent_yield}%$yield_spacing║"
    echo "║    🎯 Stakes won in last 7 days: $stakes_won_7d$spacing_7d║"
    echo "║    📊 7-day yield rate (stakes/blocks): ${percent_yield_7d}%$yield_7d_spacing║"
    echo "║    🔄 Immature UTXOs (< 31 confirmations): $immature_utxos$immature_spacing║"
    echo "║    💰 Current wallet balance: $wallet_balance$balance_spacing║"
    echo "║                                                                ║"
    echo "║  WALLET COMMANDS:                                              ║"
    echo "║    gb                     - Get wallet balances                ║"
    echo "║    gna                    - Generate new address               ║"
    echo "║    lag                    - List address groupings             ║"
    echo "║    sta [address] [amount] - Send to address                    ║"
    echo "║    swe [address]          - Sweep a wallet                     ║"
    echo "║    bac                    - Manual wallet backup               ║"
    echo "║    lbac                   - List backup directory contents     ║"
    echo "║                                                                ║"
    echo "║  SYSTEM COMMANDS:                                              ║"
    echo "║    lv                     - Show Lynx version                  ║"
    echo "║    lyc                    - Edit Lynx config                   ║"
    echo "║    lyl                    - View Lynx debug log                ║"
    echo "║    lynx                   - Restart Lynx daemon                ║"
    echo "║    jou                    - View builder logs                  ║"
    echo "║    gbi                    - Get blockchain info                ║"
    echo "║    lelp                   - Show Lynx help                     ║"
    echo "║    stat                   - Check Lynx service status          ║"
    echo "║    wd                     - Change to Lynx working directory   ║"
    echo "║                                                                ║"
    echo "║  USEFUL COMMANDS:                                              ║"
    echo "║    htop                   - Monitor system resources           ║"
    echo "║    motd                   - Show this help message again       ║"
    echo "║                                                                ║"
    echo "║  📚 Complete project documentation: https://docs.getlynx.io/   ║"
    echo "║  💾 Store files permanently: https://clevver.org/              ║"
    echo "║  🔍 Blockchain explorer: https://explorer.getlynx.io/          ║"
    echo "║  📈 Trade Lynx: https://freixlite.com/market/LYNX/LTC          ║"
    echo "║  🔢 Lynx Version: $lynx_version$version_spacing║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}
EOF
}

# Function to add useful aliases and MOTD to /root/.bashrc
add_aliases_to_bashrc() {
    local BASHRC="/root/.bashrc"
    local ALIAS_BLOCK_START="# === LYNX ALIASES START ==="
    local ALIAS_BLOCK_END="# === LYNX ALIASES END ==="
    local MOTD_BLOCK_START="# === LYNX MOTD START ==="
    local MOTD_BLOCK_END="# === LYNX MOTD END ==="
    
    # Remove any existing alias block to avoid duplicates
    if [ -f "$BASHRC" ] && grep -q "$ALIAS_BLOCK_START" "$BASHRC"; then
        sed -i "/$ALIAS_BLOCK_START/,/$ALIAS_BLOCK_END/d" "$BASHRC"
    fi
    
    # Remove any existing MOTD block to avoid duplicates
    if [ -f "$BASHRC" ] && grep -q "$MOTD_BLOCK_START" "$BASHRC"; then
        sed -i "/$MOTD_BLOCK_START/,/$MOTD_BLOCK_END/d" "$BASHRC"
    fi
    
    # Append the new alias block
    cat <<EOF >> "$BASHRC"
$ALIAS_BLOCK_START
alias gb='lynx-cli getbalances'
alias gna='lynx-cli getnewaddress'
alias wd='cd $WorkingDirectory && ls -lh'
alias bac='/usr/local/bin/backup.sh'
alias lbac='cd /var/lib/lynx-backup && ls -lh'
alias lag='lynx-cli listaddressgroupings'
alias lv='lynx-cli -version'
alias lyc='nano $WorkingDirectory/lynx.conf'
alias lyl='tail -n 500 -f $WorkingDirectory/debug.log'
alias lynx='systemctl stop lynx && rm -rf $WorkingDirectory/debug.log && systemctl start lynx'
alias sta='lynx-cli sendtoaddress \$1 \$2'
swe() { lynx-cli sendtoaddress "\$1" "\$(lynx-cli getbalance)" "" "" true; }
alias jou='journalctl -t builder.sh -n 100 -f'
alias gbi='lynx-cli getblockchaininfo'
alias lelp='lynx-cli help'
alias motd='show_lynx_motd'
alias stat='systemctl status lynx'
$ALIAS_BLOCK_END

$MOTD_BLOCK_START
$(create_motd_function)
show_lynx_motd

# Automatically change to root directory when switching to root user
cd /root
$MOTD_BLOCK_END
EOF
}

# Function to clean up multiple consecutive empty lines in bashrc
cleanup_bashrc_empty_lines() {
    local BASHRC="/root/.bashrc"
    
    # Only proceed if the file exists
    if [ ! -f "$BASHRC" ]; then
        return
    fi
    
    # Use sed to replace multiple consecutive empty lines with single empty lines
    # This pattern matches 2 or more consecutive empty lines and replaces them with 1
    sed -i '/^$/N;/^\n$/D' "$BASHRC"
    
    logger -t builder.sh "Cleaned up multiple empty lines in $BASHRC"
}

# Function to create builder.service and builder.timer if not present
create_builder_timer() {
    if [ ! -f /etc/systemd/system/builder.service ] || [ ! -f /etc/systemd/system/builder.timer ]; then
        logger -t builder.sh "Creating /etc/systemd/system/builder.service and builder.timer."
        cat <<EOF > /etc/systemd/system/builder.service
[Unit]
Description=Run builder.sh every 12 minutes
Documentation=https://getlynx.io/

[Service]
Type=simple
ExecStart=/usr/local/bin/builder.sh
StandardOutput=journal
StandardError=journal
Environment=HOME=/root
WorkingDirectory=/root
EOF

        cat <<EOF > /etc/systemd/system/builder.timer
[Unit]
Description=Run builder.sh every 12 minutes
Documentation=https://getlynx.io/

[Timer]
OnBootSec=1min
OnUnitActiveSec=12min
AccuracySec=30sec
Unit=builder.service
Persistent=false

[Install]
WantedBy=timers.target
EOF
        systemctl daemon-reload
        systemctl enable builder.timer
        systemctl start builder.timer
        logger -t builder.sh "/etc/systemd/system/builder.service and builder.timer created, enabled, and started. Gracefully exiting script."
        echo "The device will reboot in 2 seconds. Please wait..."
        sleep 2
        reboot
        exit 0
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t builder.sh "/etc/systemd/system/builder.service and builder.timer already exist. Skipping creation."
        fi
    fi
}

# Function to create wallet backup service and timer
create_wallet_backup_timer() {
    logger -t builder.sh "Creating /etc/systemd/system/lynx-wallet-backup.service and lynx-wallet-backup.timer."
    
    # Stop and disable the timer before recreating it to avoid conflicts
    systemctl stop lynx-wallet-backup.timer 2>/dev/null || true
    systemctl disable lynx-wallet-backup.timer 2>/dev/null || true
    
    # Create backup directory
    mkdir -p /var/lib/lynx-backup
    chown root:root /var/lib/lynx-backup
    chmod 700 /var/lib/lynx-backup
    
    # Create the backup script
    cat <<'EOF' > /usr/local/bin/backup.sh
#!/bin/bash

# Lynx Wallet Backup Script
# This script creates a timestamped backup of the Lynx wallet and checks for duplicates
# Runs every 60 minutes

set -e

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
    logger -t backup.sh "Lynx daemon is not running. Skipping backup."
    exit 0
fi

# Create the backup
logger -t backup.sh "Creating wallet backup: $BACKUP_FILE"
if ! lynx-cli -conf=$WorkingDirectory/lynx.conf backupwallet "$BACKUP_FILE" 2>/dev/null; then
    logger -t backup.sh "Failed to create wallet backup. Daemon may not be running or ready."
    logger -t backup.sh "Exiting gracefully. Backup will be retried on next scheduled run."
    exit 0
fi

# Check if backup was created successfully
if [ -f "$BACKUP_FILE" ]; then
    # Set secure permissions on the backup file
    chmod 400 "$BACKUP_FILE"
    
    # Calculate hash of the new backup
    logger -t backup.sh "Calculating hash of new backup..."
    new_hash=$(sha256sum "$BACKUP_FILE" | cut -d" " -f1)
    
    # Check if any existing backup has the same hash
    duplicate_found=false
    for existing_file in "$BACKUP_DIR"/*.dat; do
        if [ "$existing_file" != "$BACKUP_FILE" ] && [ -f "$existing_file" ]; then
            existing_hash=$(sha256sum "$existing_file" | cut -d" " -f1)
            if [ "$new_hash" = "$existing_hash" ]; then
                duplicate_found=true
                logger -t backup.sh "Duplicate found: $existing_file"
                break
            fi
        fi
    done
    
    # If duplicate found, remove the new backup and exit
    if [ "$duplicate_found" = true ]; then
        rm -f "$BACKUP_FILE"
        logger -t backup.sh "Duplicate wallet backup detected. Removing new backup file."
        exit 0
    else
        logger -t backup.sh "New wallet backup created successfully: $BACKUP_FILE"
        logger -t backup.sh "Backup hash: $new_hash"
        
        # Check if we have more than 100 backup files and remove oldest ones
        backup_count=$(ls -1 "$BACKUP_DIR"/*.dat 2>/dev/null | wc -l)
        if [ "$backup_count" -gt 100 ]; then
            logger -t backup.sh "Backup count ($backup_count) exceeds limit of 100. Removing oldest backups..."
            
            # List all backup files by modification time (oldest first) and remove excess
            ls -1t "$BACKUP_DIR"/*.dat 2>/dev/null | tail -n +101 | while read -r old_file; do
                if [ -f "$old_file" ]; then
                    rm -f "$old_file"
                    logger -t backup.sh "Removed old backup: $(basename "$old_file")"
                fi
            done
            
            # Get final count after cleanup
            final_count=$(ls -1 "$BACKUP_DIR"/*.dat 2>/dev/null | wc -l)
            logger -t backup.sh "Backup cleanup complete. Current backup count: $final_count"
        fi
    fi
else
    logger -t backup.sh "Failed to create wallet backup"
    exit 1
fi
EOF

    # Make the backup script executable
    chmod +x /usr/local/bin/backup.sh
    chown root:root /usr/local/bin/backup.sh

            cat <<EOF > /etc/systemd/system/lynx-wallet-backup.service
[Unit]
Description=Backup Lynx wallet every 60 minutes
Documentation=https://getlynx.io/
After=lynx.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
StandardOutput=journal
StandardError=journal
Environment=HOME=$WorkingDirectory
WorkingDirectory=$WorkingDirectory
User=root
Group=root
# Ensure the service can access lynx-cli and the wallet
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EOF

         cat <<EOF > /etc/systemd/system/lynx-wallet-backup.timer
[Unit]
Description=Backup Lynx wallet every 60 minutes
Documentation=https://getlynx.io/

[Timer]
OnBootSec=15min
OnUnitActiveSec=60min
AccuracySec=5m
Unit=lynx-wallet-backup.service
Persistent=true

[Install]
WantedBy=timers.target
EOF
     systemctl daemon-reload
     systemctl enable lynx-wallet-backup.timer
     systemctl start lynx-wallet-backup.timer
     logger -t builder.sh "/etc/systemd/system/lynx-wallet-backup.service and lynx-wallet-backup.timer created, enabled, and started."
}

# Function to check and update swap to at least 4GB if less than 3GB
check_and_update_swap() {
    logger -t builder.sh "Checking swap size."
    # Get current swap size in MB (divided by 1024)
    current_swap=$(free -m | awk '/^Swap:/ {print $2}')
    logger -t builder.sh "Current swap size: ${current_swap}MB"

    # Check if swap is less than 3GB (3072MB) or doesn't exist
    if [ "$current_swap" -lt 3072 ]; then
        logger -t builder.sh "Current swap is less than 3GB. Setting up 4GB swap file."

        # If there's existing swap, turn it off and remove from fstab
        if [ "$current_swap" -gt 0 ]; then
            swap_file=$(cat /proc/swaps | tail -n1 | awk '{print $1}')
            logger -t builder.sh "Disabling existing swap: $swap_file"
            swapoff "$swap_file" && logger -t builder.sh "Swapoff succeeded for $swap_file" || logger -t builder.sh "Swapoff failed for $swap_file"
            sed -i '/swap/d' /etc/fstab && logger -t builder.sh "Removed old swap entry from /etc/fstab" || logger -t builder.sh "Failed to remove old swap entry from /etc/fstab"
        fi

        logger -t builder.sh "Creating new 4GB swapfile at /swapfile"
        fallocate -l 4G /swapfile && logger -t builder.sh "fallocate succeeded" || logger -t builder.sh "fallocate failed"
        chmod 600 /swapfile && logger -t builder.sh "chmod 600 succeeded" || logger -t builder.sh "chmod 600 failed"
        mkswap /swapfile && logger -t builder.sh "mkswap succeeded" || logger -t builder.sh "mkswap failed"
        swapon /swapfile && logger -t builder.sh "swapon succeeded" || logger -t builder.sh "swapon failed"
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab && logger -t builder.sh "Added swap entry to /etc/fstab" || logger -t builder.sh "Failed to add swap entry to /etc/fstab"
        logger -t builder.sh "Swap updated. Rebooting system to apply changes. Gracefully exiting script."
        sleep 2
        reboot
        exit 0
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t builder.sh "Swap is sufficient (>=3GB). No changes made."
        fi
    fi
    # Only log if system has been running for 6 hours or less
    if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
        logger -t builder.sh "Swap check complete."
    fi
}

# Function to check if ARM Debian Lynx binary is installed, else download and install
check_and_install_lynx_arm() {
    ARCH="$(uname -m)"
    if [ "$ARCH" != "aarch64" ] && [[ "$ARCH" != arm* ]]; then
        logger -t builder.sh "Not an ARM architecture. Skipping Lynx ARM binary check."
        return
    fi
    if command -v lynxd >/dev/null 2>&1; then
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t builder.sh "Lynx daemon already installed. Skipping download."
        fi
        return
    fi
    logger -t builder.sh "Lynx daemon not found. Downloading and installing latest ARM release."
    # Download and install Lynx binary (Debian ARM)
    release_info=$(curl -s https://api.github.com/repos/getlynx/Lynx/releases/latest)
    if [ $? -ne 0 ] || [ -z "$release_info" ]; then
        logger -t builder.sh "Failed to fetch release information from GitHub API"
        return 1
    fi
    download_url=$(echo "$release_info" | \
        grep "browser_download_url" | \
        grep -iE "debian|ubuntu|ol" | \
        grep -iE "\.zip" | \
        grep -iE "arm" | \
        head -n 1 | \
        cut -d '"' -f 4)
    if [ -z "$download_url" ]; then
        logger -t builder.sh "No suitable ARM Debian Lynx binary found."
        return 1
    fi
    filename=$(basename "$download_url")
    logger -t builder.sh "Downloading $filename to $WorkingDirectory..."
    
    # Download with progress and verification
    wget --progress=bar:force -O "$WorkingDirectory/$filename" "$download_url"
    if [ $? -ne 0 ]; then
        logger -t builder.sh "ERROR: Failed to download $filename"
        return 1
    fi
    
    # Verify download was successful
    if [ ! -f "$WorkingDirectory/$filename" ]; then
        logger -t builder.sh "ERROR: Downloaded file $filename not found"
        return 1
    fi
    
    # Check file size (should be reasonable for a binary)
    file_size=$(stat -c %s "$WorkingDirectory/$filename")
    if [ "$file_size" -lt 1000000 ]; then  # Less than 1MB is suspicious
        logger -t builder.sh "ERROR: Downloaded file $filename is too small ($file_size bytes) - likely corrupted"
        logger -t builder.sh "File contents (first 200 chars):"
        head -c 200 "$WorkingDirectory/$filename" | logger -t builder.sh
        return 1
    fi
    
    logger -t builder.sh "Download successful. File size: $file_size bytes"
    logger -t builder.sh "Extracting $filename..."
    
    # Extract with verification
    unzip -o "$WorkingDirectory/$filename" -d /usr/local/bin/
    if [ $? -ne 0 ]; then
        logger -t builder.sh "ERROR: Failed to extract $filename"
        return 1
    fi
    
    # Verify extraction was successful
    if [ ! -f "/usr/local/bin/lynxd" ]; then
        logger -t builder.sh "ERROR: lynxd not found after extraction"
        logger -t builder.sh "Contents of /usr/local/bin/:"
        ls -la /usr/local/bin/ | logger -t builder.sh
        return 1
    fi
    chmod +x /usr/local/bin/lynx* || logger -t builder.sh "Failed to chmod Lynx binaries"
    
    # Verify the binary was actually installed
    if [ -f "/usr/local/bin/lynxd" ]; then
        logger -t builder.sh "Lynx ARM binary installed successfully."
    else
        logger -t builder.sh "ERROR: Lynx binary installation failed - lynxd not found at /usr/local/bin/lynxd"
        return 1
    fi
}

# Function to create lynx.service systemd unit file if not present
create_lynx_service() {
    if [ ! -f /etc/systemd/system/lynx.service ]; then
        logger -t builder.sh "Creating /etc/systemd/system/lynx.service systemd unit file."
        cat <<EOF > /etc/systemd/system/lynx.service
[Unit]
Description=Lynx Cryptocurrency Daemon
Documentation=https://getlynx.io/
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=/bin/mkdir -p $WorkingDirectory
ExecStartPre=/bin/chown root:root $WorkingDirectory
ExecStart=/usr/local/bin/lynxd -datadir=$WorkingDirectory -assumevalid=fa71fe1bdfa0f68ef184c8cddc4c401cae852b566f36042ec59396c9273e8bce
ExecStop=/usr/local/bin/lynx-cli -datadir=$WorkingDirectory stop
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
        logger -t builder.sh "/etc/systemd/system/lynx.service created and systemd reloaded."
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t builder.sh "/etc/systemd/system/lynx.service already exists. Skipping creation."
        fi
    fi
}

# Function to check if lynx service is running, and start if not
ensure_lynx_service_running() {
    # First verify the binary exists
    if [ ! -f "/usr/local/bin/lynxd" ]; then
        logger -t builder.sh "ERROR: Cannot start Lynx service - lynxd binary not found at /usr/local/bin/lynxd"
        logger -t builder.sh "Attempting to reinstall Lynx binary..."
        check_and_install_lynx_arm
        if [ ! -f "/usr/local/bin/lynxd" ]; then
            logger -t builder.sh "ERROR: Lynx binary installation failed. Cannot start service."
            return 1
        fi
    fi
    
    if pgrep -x "lynxd" >/dev/null; then
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t builder.sh "Lynx daemon is already running."
        fi
        return
    else
        logger -t builder.sh "Lynx daemon is not running. Attempting to start."
        systemctl enable lynx.service
        sleep 5
        systemctl start lynx.service
        logger -t builder.sh "Lynx daemon started."
        logger -t builder.sh "Disabling rc.local to prevent future builder.sh downloads"
        chmod -x /etc/rc.local
        exit 0
    fi
}

# Function to check if blockchain sync is complete
check_blockchain_sync() {
    # Try to get blockchain info with error handling
    SYNC_STATUS=$(/usr/local/bin/lynx-cli getblockchaininfo 2>/dev/null | grep -o '"initialblockdownload":[^,}]*' | sed 's/.*://' | tr -d '"' | xargs)

    # Check if the command succeeded and returned valid data
    if [ $? -eq 0 ] && [ -n "$SYNC_STATUS" ] && [ "$SYNC_STATUS" != "null" ]; then
        if [ "$SYNC_STATUS" = "false" ]; then
            logger -t builder.sh "Blockchain sync complete. Stopping and disabling builder.timer."
            systemctl stop builder.timer
            systemctl disable builder.timer
            logger -t builder.sh "Disabling rc.local to prevent future builder.sh downloads"
            chmod -x /etc/rc.local
            return
        else
            #logger -t builder.sh "Blockchain still syncing or status unknown (got:$SYNC_STATUS). Restarting Lynx daemon."
            logger -t builder.sh "Blockchain still syncing or status unknown. Expected behaviour. Restarting Lynx daemon. "
            systemctl restart lynx.service
        fi
    else
        logger -t builder.sh "Daemon not ready or RPC call failed. Will try again next time."
        return 0
    fi
}

# Add aliases to bashrc
add_aliases_to_bashrc

# Clean up any multiple empty lines that may have been created
cleanup_bashrc_empty_lines

# Call the builder timer creation function
create_builder_timer

# Call the wallet backup timer creation function
create_wallet_backup_timer

# Call the swap check/update function
check_and_update_swap

# Call the ARM Lynx check/install function
check_and_install_lynx_arm

# Call the lynx service creation function
create_lynx_service

# Call the lynx service running check function
ensure_lynx_service_running

# Call the blockchain sync check function
check_blockchain_sync