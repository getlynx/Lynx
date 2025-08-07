#!/bin/bash
set -euo pipefail

################################################################################
# LYNX NODE INSTALLER SCRIPT
################################################################################
#
# PURPOSE:
#   Automates the complete setup, configuration, and maintenance of a Lynx 
#   cryptocurrency node on AMD64 and ARM64 architectures. Handles initial 
#   installation, ongoing maintenance, wallet backup automation, and provides 
#   a rich user experience with staking statistics and convenient command aliases.
#
# AUTHOR: Lynx Development Team
# VERSION: 2.0
# LAST UPDATED: 2025
# DOCUMENTATION: https://docs.getlynx.io/
#
################################################################################
#
# CORE FUNCTIONALITY:
#
#   1. SYSTEM INITIALIZATION:
#      - Detects system architecture (AMD64 or ARM64)
#      - Validates architecture support and exits gracefully if unsupported
#      - Creates data directory at /var/lib/lynx with proper permissions
#      - Establishes backward compatibility symlink (/root/.lynx)
#      - Sets up 4GB swap file if current swap is insufficient (<3GB) - Raspberry Pi only
#      - Downloads and installs architecture-appropriate Lynx binaries from GitHub releases
#      - Creates systemd services for Lynx daemon and maintenance timer
#
#   2. AUTOMATED MAINTENANCE:
#      - Runs every 12 minutes via systemd timer during blockchain sync
#      - Monitors blockchain synchronization progress
#      - Automatically restarts daemon during sync phase
#      - Self-disables timer once blockchain sync completes
#      - Provides conditional logging (reduced after 6 hours uptime)
#
#   3. WALLET BACKUP SYSTEM:
#      - Creates automated wallet backups every 60 minutes
#      - Implements duplicate detection using SHA256 hashing
#      - Maintains rolling backup history (max 100 backups)
#      - Stores backups in secure directory (/var/lib/lynx-backup)
#      - Provides manual backup command via 'bac' alias
#
#   4. USER EXPERIENCE ENHANCEMENTS:
#      - Rich MOTD displaying real-time staking statistics
#      - Shows stakes won, yield rates, immature UTXOs, wallet balance
#      - Comprehensive bash aliases for all common operations
#      - Automatic directory change to /root on login
#      - Clean, formatted command help interface
#
################################################################################
#
# BASH ALIASES CREATED:
#
#   WALLET OPERATIONS:
#     gb      - Get wallet balances (getbalances)
#     gna     - Generate new address
#     lag     - List address groupings
#     sta     - Send to address (usage: sta <address> <amount>)
#     swe     - Sweep wallet (send all funds to address)
#     bac     - Manual wallet backup
#     lbac    - List backup directory contents
#
#   NODE MANAGEMENT:
#     lv      - Show Lynx version
#     lyc     - Edit Lynx configuration file
#     lyl     - View debug log (real-time tail)
#     lynx    - Clean restart Lynx daemon (stops, removes debug.log, starts)
#     gbi     - Get blockchain info
#     lelp    - Show Lynx help
#     stat    - Check Lynx service status
#     wd      - Change to working directory (/var/lib/lynx)
#
#   SYSTEM UTILITIES:
#     jou     - View install script logs (journalctl)
#     motd    - Display help message and statistics
#     update  - Update node (checks version, updates if newer available)
#     htop    - System resource monitor
#
################################################################################
#
# SYSTEM REQUIREMENTS:
#   - Supported architectures: AMD64 (x86_64) or ARM64 (aarch64) - automatically detected
#   - Linux system with systemd
#   - Root privileges (required for system-level operations)
#   - Internet connectivity for downloads and updates
#   - Minimum 4GB RAM recommended for optimal performance
#   - Sufficient disk space (blockchain data + swap file for Raspberry Pi)
#
# REQUIRED DEPENDENCIES:
#   - bash, systemd, coreutils
#   - wget, curl, unzip (for downloads)
#   - fallocate, mkswap, swapon (for swap management)
#   - logger (systemd logging)
#   - awk, sed, grep (text processing)
#
################################################################################
#
# INSTALLATION METHODS:
#
#   1. AUTOMATIC (via iso-builder.sh):
#      - Downloaded and executed automatically on first boot of custom image
#      - Integrated into rc.local for seamless setup
#
#   2. MANUAL INSTALLATION:
#      wget -O /usr/local/bin/install.sh https://raw.githubusercontent.com/getlynx/Lynx/refs/heads/main/contrib/pi/install.sh
#      chmod +x /usr/local/bin/install.sh
#      /usr/local/bin/install.sh
#
#   3. RE-RUN (if needed):
#      /usr/local/bin/install.sh
#
################################################################################
#
# OPERATIONAL PHASES:
#
#   1. INITIAL SETUP PHASE:
#      - Detects system architecture (AMD64/ARM64) and validates support
#      - Creates all systemd services and timers
#      - Downloads and installs architecture-specific Lynx binaries
#      - Configures system resources (swap for Pi only, directories)
#      - Sets up user environment (aliases, MOTD)
#      - Initiates system reboot if major changes made
#
#   2. MAINTENANCE PHASE:
#      - Triggered every 12 minutes by systemd timer
#      - Ensures Lynx daemon is running
#      - Monitors blockchain sync progress
#      - Restarts daemon during sync if needed
#      - Transitions to completion phase when sync finishes
#
#   3. COMPLETION PHASE:
#      - Disables maintenance timer when sync completes
#      - Disables rc.local to prevent re-downloads
#      - System operates normally with periodic wallet backups
#
################################################################################
#
# LOGGING AND MONITORING:
#   - All operations logged to systemd journal with 'install.sh' identifier
#   - View logs: journalctl -t install.sh -f
#   - Smart logging: verbose during first 6 hours, reduced thereafter
#   - Backup operations logged with 'backup.sh' identifier
#   - Debug information available in /var/lib/lynx/debug.log
#
# SECURITY IMPLEMENTATION:
#   - Systemd services run with security restrictions (NoNewPrivileges, PrivateTmp)
#   - Backup files have strict permissions (400)
#   - Backup directory restricted to root access (700)
#   - Swap file secured with 600 permissions (Raspberry Pi only)
#   - VPS/server systems skip swap management to avoid permission issues
#   - All downloads verified for integrity
#
################################################################################
#
# TROUBLESHOOTING COMMANDS:
#   systemctl status lynx              # Check daemon status
#   systemctl status install.timer    # Check maintenance timer
#   systemctl status lynx-wallet-backup.timer  # Check backup timer
#   journalctl -t install.sh -f       # View setup/maintenance logs
#   journalctl -t backup.sh -f        # View backup logs
#   tail -f /var/lib/lynx/debug.log   # View Lynx daemon logs
#   lynx-cli getblockchaininfo         # Check sync status
#   lynx-cli getbalances               # Check wallet balances
#
# NETWORK CONFIGURATION:
#   - Lynx P2P port: 22566 (configurable in lynx.conf)
#   - RPC port: 8332 (configurable in lynx.conf)  
#   - Requires outbound internet access for initial sync
#
# FILES AND DIRECTORIES CREATED:
#   /var/lib/lynx/                     # Main data directory
#   /var/lib/lynx-backup/             # Wallet backup storage
#   /usr/local/bin/install.sh         # This script
#   /usr/local/bin/backup.sh          # Wallet backup script
#   /etc/systemd/system/install.service       # Maintenance service
#   /etc/systemd/system/install.timer         # Maintenance timer
#   /etc/systemd/system/lynx.service          # Lynx daemon service
#   /etc/systemd/system/lynx-wallet-backup.service  # Backup service
#   /etc/systemd/system/lynx-wallet-backup.timer    # Backup timer
#   /swapfile                         # 4GB swap file (if created on Raspberry Pi)
#   /root/.bashrc                     # Modified with aliases and MOTD
#   /root/.lynx -> /var/lib/lynx      # Compatibility symlink
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
    echo "║    jou                    - View install logs                  ║"
    echo "║    gbi                    - Get blockchain info                ║"
    echo "║    lelp                   - Show Lynx help                     ║"
    echo "║    stat                   - Check Lynx service status          ║"
    echo "║    wd                     - Change to Lynx working directory   ║"
    echo "║                                                                ║"
    echo "║  USEFUL COMMANDS:                                              ║"
    echo "║    htop                   - Monitor system resources           ║"
    echo "║    motd                   - Show this help message again       ║"
    echo "║    update                 - 🚀 Update node                     ║"
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
alias jou='journalctl -t install.sh -n 100 -f'
alias gbi='lynx-cli getblockchaininfo'
alias lelp='lynx-cli help'
alias motd='show_lynx_motd'
alias stat='systemctl status lynx'
alias update='wget -qO- https://update.getlynx.io/ | bash'
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
    
    logger -t install.sh "Cleaned up multiple empty lines in $BASHRC"
}

# Function to create install.service and install.timer if not present
create_install_timer() {
    # Ensure the install.sh script is available in /usr/local/bin for systemd service
    local script_path="$0"
    local target_path="/usr/local/bin/install.sh"
    
    # Copy the script to /usr/local/bin if it's not already there or if it's different
    if [ ! -f "$target_path" ] || ! cmp -s "$script_path" "$target_path" 2>/dev/null; then
        logger -t install.sh "Copying install.sh script to $target_path for systemd service access."
        cp "$script_path" "$target_path"
        chmod +x "$target_path"
        chown root:root "$target_path"
        logger -t install.sh "Install script successfully copied to $target_path"
    else
        logger -t install.sh "Install script already present at $target_path"
    fi
    
    if [ ! -f /etc/systemd/system/install.service ] || [ ! -f /etc/systemd/system/install.timer ]; then
        logger -t install.sh "Creating /etc/systemd/system/install.service and install.timer."
        cat <<EOF > /etc/systemd/system/install.service
[Unit]
Description=Run install.sh every 12 minutes
Documentation=https://getlynx.io/

[Service]
Type=simple
ExecStart=/usr/local/bin/install.sh
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
OnBootSec=1min
OnUnitActiveSec=12min
AccuracySec=30sec
Unit=install.service
Persistent=false

[Install]
WantedBy=timers.target
EOF
        systemctl daemon-reload
        systemctl enable install.timer
        systemctl start install.timer
        logger -t install.sh "/etc/systemd/system/install.service and install.timer created, enabled, and started."
        logger -t install.sh "Install script is now available at $target_path for system service execution."
        logger -t install.sh "Gracefully exiting script. The device will reboot in 2 seconds."
        echo "The device will reboot in 2 seconds. Please wait..."
        sleep 2
        reboot
        exit 0
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t install.sh "/etc/systemd/system/install.service and install.timer already exist. Skipping creation."
        fi
    fi
}

# Function to create wallet backup service and timer
create_wallet_backup_timer() {
    logger -t install.sh "Creating /etc/systemd/system/lynx-wallet-backup.service and lynx-wallet-backup.timer."
    
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
     logger -t install.sh "/etc/systemd/system/lynx-wallet-backup.service and lynx-wallet-backup.timer created, enabled, and started."
}

# Function to check and update swap to at least 4GB if less than 3GB (Raspberry Pi only)
check_and_update_swap() {
    # Only manage swap on Raspberry Pi devices
    if ! is_raspberry_pi; then
        logger -t install.sh "Non-Raspberry Pi system detected. Skipping swap management for VPS/server compatibility."
        logger -t install.sh "Current system will use existing swap configuration."
        return 0
    fi
    
    logger -t install.sh "Raspberry Pi detected. Checking swap size for optimization."
    # Get current swap size in MB (divided by 1024)
    current_swap=$(free -m | awk '/^Swap:/ {print $2}')
    logger -t install.sh "Current swap size: ${current_swap}MB"

    # Check if swap is less than 3GB (3072MB) or doesn't exist
    if [ "$current_swap" -lt 3072 ]; then
        logger -t install.sh "Current swap is less than 3GB. Setting up 4GB swap file for Raspberry Pi."

        # If there's existing swap, turn it off and remove from fstab
        if [ "$current_swap" -gt 0 ]; then
            swap_file=$(cat /proc/swaps | tail -n1 | awk '{print $1}')
            logger -t install.sh "Disabling existing swap: $swap_file"
            swapoff "$swap_file" && logger -t install.sh "Swapoff succeeded for $swap_file" || logger -t install.sh "Swapoff failed for $swap_file"
            sed -i '/swap/d' /etc/fstab && logger -t install.sh "Removed old swap entry from /etc/fstab" || logger -t install.sh "Failed to remove old swap entry from /etc/fstab"
        fi

        logger -t install.sh "Creating new 4GB swapfile at /swapfile"
        fallocate -l 4G /swapfile && logger -t install.sh "fallocate succeeded" || logger -t install.sh "fallocate failed"
        chmod 600 /swapfile && logger -t install.sh "chmod 600 succeeded" || logger -t install.sh "chmod 600 failed"
        mkswap /swapfile && logger -t install.sh "mkswap succeeded" || logger -t install.sh "mkswap failed"
        swapon /swapfile && logger -t install.sh "swapon succeeded" || logger -t install.sh "swapon failed"
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab && logger -t install.sh "Added swap entry to /etc/fstab" || logger -t install.sh "Failed to add swap entry to /etc/fstab"
        logger -t install.sh "Swap updated on Raspberry Pi. Rebooting system to apply changes. Gracefully exiting script."
        sleep 2
        reboot
        exit 0
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t install.sh "Raspberry Pi swap is sufficient (>=3GB). No changes made."
        fi
    fi
    # Only log if system has been running for 6 hours or less
    if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
        logger -t install.sh "Swap check complete."
    fi
}

# Function to detect if running on a Raspberry Pi
is_raspberry_pi() {
    # Check multiple indicators for Raspberry Pi detection
    if [ -f /sys/firmware/devicetree/base/model ]; then
        if grep -qi "raspberry pi" /sys/firmware/devicetree/base/model 2>/dev/null; then
            return 0  # True - is Raspberry Pi
        fi
    fi
    
    # Check /proc/cpuinfo for Raspberry Pi hardware
    if [ -f /proc/cpuinfo ]; then
        if grep -qi "raspberry pi\|bcm2835\|bcm2708\|bcm2709\|bcm2711\|bcm2712" /proc/cpuinfo 2>/dev/null; then
            return 0  # True - is Raspberry Pi
        fi
    fi
    
    # Check /proc/device-tree/model if available
    if [ -f /proc/device-tree/model ]; then
        if grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
            return 0  # True - is Raspberry Pi
        fi
    fi
    
    return 1  # False - not a Raspberry Pi
}

# Function to detect system architecture and return appropriate binary identifier
detect_system_architecture() {
    local arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo ""
            echo "═══════════════════════════════════════════════════════════════"
            echo "                    UNSUPPORTED ARCHITECTURE                    "
            echo "═══════════════════════════════════════════════════════════════"
            echo ""
            echo "Your system architecture '$arch' is not currently supported."
            echo ""
            echo "Lynx binaries are available for:"
            echo "  • AMD64 (x86_64) - Intel/AMD 64-bit processors"
            echo "  • ARM64 (aarch64) - ARM 64-bit processors (Raspberry Pi 4+, Apple Silicon, etc.)"
            echo ""
            echo "If you believe this is an error, please check:"
            echo "  • System architecture: uname -m"
            echo "  • Available releases: https://github.com/getlynx/Lynx/releases"
            echo ""
            echo "For support, visit: https://docs.getlynx.io/"
            echo ""
            echo "═══════════════════════════════════════════════════════════════"
            logger -t install.sh "Unsupported architecture: $arch. Installation aborted."
            exit 1
            ;;
    esac
}

# Function to extract version number from version string (e.g., "v26.2.35" -> "26.2.35")
extract_version_number() {
    echo "$1" | sed 's/^v//' | sed 's/[^0-9.].*//'
}

# Function to compare version numbers (returns 0 if v1 == v2, 1 if v1 > v2, 2 if v1 < v2)
compare_versions() {
    local v1="$1"
    local v2="$2"
    
    if [ "$v1" = "$v2" ]; then
        return 0  # Equal
    fi
    
    # Use sort -V for version comparison
    local higher=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | tail -n1)
    
    if [ "$higher" = "$v1" ]; then
        return 1  # v1 > v2
    else
        return 2  # v1 < v2
    fi
}

# Function to get current running Lynx version
get_current_lynx_version() {
    # Only check version if daemon is running (safety check)
    if ! pgrep -x "lynxd" >/dev/null; then
        echo ""
        return 1
    fi
    
    # Try to get version from running daemon
    local version=$(lynx-cli -version 2>/dev/null | head -1 | grep -o 'v[0-9][0-9.]*' | head -1)
    if [ -n "$version" ]; then
        extract_version_number "$version"
        return 0
    fi
    
    # Fallback: try binary version if cli fails
    local binary_version=$(/usr/local/bin/lynxd -version 2>/dev/null | head -1 | grep -o 'v[0-9][0-9.]*' | head -1)
    if [ -n "$binary_version" ]; then
        extract_version_number "$binary_version"
        return 0
    fi
    
    echo ""
    return 1
}

# Function to get latest GitHub release version
get_latest_github_version() {
    local release_info=$(curl -s https://api.github.com/repos/getlynx/Lynx/releases/latest)
    if [ $? -ne 0 ] || [ -z "$release_info" ]; then
        echo ""
        return 1
    fi
    
    local tag_name=$(echo "$release_info" | grep '"tag_name":' | cut -d '"' -f 4)
    if [ -n "$tag_name" ]; then
        extract_version_number "$tag_name"
        return 0
    fi
    
    echo ""
    return 1
}

# Function to check if Lynx binary needs update or installation
check_and_install_lynx_binary() {
    # Detect the system architecture
    local detected_arch
    detected_arch=$(detect_system_architecture)
    if [ $? -ne 0 ]; then
        logger -t install.sh "Failed to detect supported architecture. Exiting."
        return 1
    fi
    
    logger -t install.sh "Detected architecture: $detected_arch"
    
    # Check if binaries exist
    if ! command -v lynxd >/dev/null 2>&1; then
        logger -t install.sh "Lynx daemon not found. Downloading and installing latest $detected_arch release."
        install_lynx_binaries "$detected_arch"
        return $?
    fi
    
    # Binaries exist - check if daemon is running (safety requirement for updates)
    if ! pgrep -x "lynxd" >/dev/null; then
        logger -t install.sh "Lynx binaries found but daemon not running. Skipping version check for safety."
        logger -t install.sh "To update Lynx version, start the daemon first: systemctl start lynx"
        return 0
    fi
    
    # Get current and latest versions
    local current_version
    local latest_version
    
    current_version=$(get_current_lynx_version)
    if [ $? -ne 0 ] || [ -z "$current_version" ]; then
        logger -t install.sh "Could not determine current Lynx version. Skipping update check."
        return 0
    fi
    
    latest_version=$(get_latest_github_version)
    if [ $? -ne 0 ] || [ -z "$latest_version" ]; then
        logger -t install.sh "Could not fetch latest Lynx version from GitHub. Skipping update check."
        return 0
    fi
    
    logger -t install.sh "Current Lynx version: $current_version"
    logger -t install.sh "Latest Lynx version: $latest_version"
    
    # Compare versions
    compare_versions "$current_version" "$latest_version"
    local comparison=$?
    
    case $comparison in
        0)
            logger -t install.sh "Lynx is up to date. No update needed."
            return 0
            ;;
        1)
            logger -t install.sh "Current version ($current_version) is newer than GitHub release ($latest_version). No update needed."
            return 0
            ;;
        2)
            logger -t install.sh "New Lynx version available: $latest_version (current: $current_version)"
            logger -t install.sh "Performing graceful update..."
            perform_lynx_update "$detected_arch"
            return $?
            ;;
    esac
}

# Function to perform graceful Lynx binary update
perform_lynx_update() {
    local arch="$1"
    
    logger -t install.sh "Starting graceful Lynx update process..."
    
    # Step 1: Gracefully stop the daemon
    logger -t install.sh "Stopping Lynx daemon gracefully..."
    systemctl stop lynx.service
    
    # Wait for graceful shutdown (max 30 seconds)
    local countdown=30
    while pgrep -x "lynxd" >/dev/null && [ $countdown -gt 0 ]; do
        sleep 1
        countdown=$((countdown - 1))
    done
    
    if pgrep -x "lynxd" >/dev/null; then
        logger -t install.sh "WARNING: Lynx daemon did not stop gracefully within 30 seconds"
        return 1
    fi
    
    logger -t install.sh "Lynx daemon stopped successfully"
    
    # Step 2: Backup current binaries (just in case)
    logger -t install.sh "Backing up current Lynx binaries..."
    mkdir -p /tmp/lynx-backup-$(date +%Y%m%d-%H%M%S)
    local backup_dir="/tmp/lynx-backup-$(date +%Y%m%d-%H%M%S)"
    cp /usr/local/bin/lynx* "$backup_dir/" 2>/dev/null
    
    # Step 3: Remove old binaries
    logger -t install.sh "Removing old Lynx binaries..."
    rm -f /usr/local/bin/lynxd /usr/local/bin/lynx-cli /usr/local/bin/lynx-tx
    
    # Step 4: Install new binaries
    logger -t install.sh "Installing new Lynx binaries..."
    if install_lynx_binaries "$arch"; then
        logger -t install.sh "New Lynx binaries installed successfully"
    else
        logger -t install.sh "ERROR: Failed to install new binaries. Attempting to restore backup..."
        cp "$backup_dir"/* /usr/local/bin/ 2>/dev/null
        chmod +x /usr/local/bin/lynx* 2>/dev/null
        logger -t install.sh "Backup restored. Starting original daemon..."
        systemctl start lynx.service
        return 1
    fi
    
    # Step 5: Start the daemon with new binaries
    logger -t install.sh "Starting Lynx daemon with new version..."
    systemctl start lynx.service
    
    # Step 6: Verify successful start
    sleep 5
    if pgrep -x "lynxd" >/dev/null; then
        logger -t install.sh "Lynx update completed successfully!"
        # Clean up backup after successful update
        rm -rf "$backup_dir"
        return 0
    else
        logger -t install.sh "ERROR: New daemon failed to start. Attempting to restore backup..."
        systemctl stop lynx.service
        rm -f /usr/local/bin/lynx*
        cp "$backup_dir"/* /usr/local/bin/
        chmod +x /usr/local/bin/lynx*
        systemctl start lynx.service
        logger -t install.sh "Backup restored and daemon restarted"
        return 1
    fi
}

# Function to install Lynx binaries (separated for reuse)
install_lynx_binaries() {
    local detected_arch="$1"
    
    # Download and install Lynx binary for detected architecture
    release_info=$(curl -s https://api.github.com/repos/getlynx/Lynx/releases/latest)
    if [ $? -ne 0 ] || [ -z "$release_info" ]; then
        logger -t install.sh "Failed to fetch release information from GitHub API"
        return 1
    fi
    
    # Determine architecture-specific grep pattern based on your release naming convention
    local arch_pattern
    case "$detected_arch" in
        amd64)
            arch_pattern="\.AMD\.zip$"
            ;;
        arm64)
            arch_pattern="\.ARM\.zip$"
            ;;
    esac
    
    # First try to get a Debian binary (preferred), then fall back to Ubuntu
    download_url=$(echo "$release_info" | \
        grep "browser_download_url" | \
        grep -E "$arch_pattern" | \
        grep -i "debian" | \
        head -n 1 | \
        cut -d '"' -f 4)
    
    # If no Debian binary found, try Ubuntu
    if [ -z "$download_url" ]; then
        download_url=$(echo "$release_info" | \
            grep "browser_download_url" | \
            grep -E "$arch_pattern" | \
            grep -i "ubuntu" | \
            head -n 1 | \
            cut -d '"' -f 4)
    fi
    
    # If still no binary found, try any Linux distribution
    if [ -z "$download_url" ]; then
        download_url=$(echo "$release_info" | \
            grep "browser_download_url" | \
            grep -E "$arch_pattern" | \
            head -n 1 | \
            cut -d '"' -f 4)
    fi
    
    if [ -z "$download_url" ]; then
        logger -t install.sh "No suitable $detected_arch Lynx binary found in GitHub releases."
        logger -t install.sh "Expected filename pattern: *.${detected_arch^^}.zip"
        return 1
    fi
    
    filename=$(basename "$download_url")
    logger -t install.sh "Downloading $filename to $WorkingDirectory..."
    
    # Download with progress and verification
    wget --progress=bar:force -O "$WorkingDirectory/$filename" "$download_url"
    if [ $? -ne 0 ]; then
        logger -t install.sh "ERROR: Failed to download $filename"
        return 1
    fi
    
    # Verify download was successful
    if [ ! -f "$WorkingDirectory/$filename" ]; then
        logger -t install.sh "ERROR: Downloaded file $filename not found"
        return 1
    fi
    
    # Check file size (should be reasonable for a binary)
    file_size=$(stat -c %s "$WorkingDirectory/$filename")
    if [ "$file_size" -lt 1000000 ]; then  # Less than 1MB is suspicious
        logger -t install.sh "ERROR: Downloaded file $filename is too small ($file_size bytes) - likely corrupted"
        logger -t install.sh "File contents (first 200 chars):"
        head -c 200 "$WorkingDirectory/$filename" | logger -t install.sh
        return 1
    fi
    
    logger -t install.sh "Download successful. File size: $file_size bytes"
    logger -t install.sh "Extracting $filename..."
    
    # Extract with verification
    unzip -o "$WorkingDirectory/$filename" -d /usr/local/bin/
    if [ $? -ne 0 ]; then
        logger -t install.sh "ERROR: Failed to extract $filename"
        return 1
    fi
    
    # Verify extraction was successful
    if [ ! -f "/usr/local/bin/lynxd" ]; then
        logger -t install.sh "ERROR: lynxd not found after extraction"
        logger -t install.sh "Contents of /usr/local/bin/:"
        ls -la /usr/local/bin/ | logger -t install.sh
        return 1
    fi
    
    # Set proper permissions
    chmod +x /usr/local/bin/lynx* || logger -t install.sh "Failed to chmod Lynx binaries"
    
    # Clean up downloaded zip file
    rm -f "$WorkingDirectory/$filename"
    
    # Verify the binary was actually installed
    if [ -f "/usr/local/bin/lynxd" ]; then
        logger -t install.sh "Lynx $detected_arch binary installed successfully."
        return 0
    else
        logger -t install.sh "ERROR: Lynx binary installation failed - lynxd not found at /usr/local/bin/lynxd"
        return 1
    fi
}

# Function to create lynx.service systemd unit file if not present
create_lynx_service() {
    if [ ! -f /etc/systemd/system/lynx.service ]; then
        logger -t install.sh "Creating /etc/systemd/system/lynx.service systemd unit file."
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
        logger -t install.sh "/etc/systemd/system/lynx.service created and systemd reloaded."
    else
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t install.sh "/etc/systemd/system/lynx.service already exists. Skipping creation."
        fi
    fi
}

# Function to check if lynx service is running, and start if not
ensure_lynx_service_running() {
    # First verify the binary exists
    if [ ! -f "/usr/local/bin/lynxd" ]; then
        logger -t install.sh "ERROR: Cannot start Lynx service - lynxd binary not found at /usr/local/bin/lynxd"
        logger -t install.sh "Attempting to reinstall Lynx binary..."
        check_and_install_lynx_binary
        if [ ! -f "/usr/local/bin/lynxd" ]; then
            logger -t install.sh "ERROR: Lynx binary installation failed. Cannot start service."
            return 1
        fi
    fi
    
    if pgrep -x "lynxd" >/dev/null; then
        # Only log if system has been running for 6 hours or less
        if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
            logger -t install.sh "Lynx daemon is already running."
        fi
        return
    else
        logger -t install.sh "Lynx daemon is not running. Attempting to start."
        systemctl enable lynx.service
        sleep 5
        systemctl start lynx.service
        logger -t install.sh "Lynx daemon started."
        logger -t install.sh "Disabling rc.local to prevent future install.sh downloads"
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
            logger -t install.sh "Blockchain sync complete. Stopping and disabling install.timer."
            systemctl stop install.timer
            systemctl disable install.timer
            logger -t install.sh "Disabling rc.local to prevent future install.sh downloads"
            chmod -x /etc/rc.local
            return
        else
            #logger -t install.sh "Blockchain still syncing or status unknown (got:$SYNC_STATUS). Restarting Lynx daemon."
            logger -t install.sh "Blockchain still syncing or status unknown. Expected behaviour. Restarting Lynx daemon. "
            systemctl restart lynx.service
        fi
    else
        logger -t install.sh "Daemon not ready or RPC call failed. Will try again next time."
        return 0
    fi
}

# Add aliases to bashrc
add_aliases_to_bashrc

# Clean up any multiple empty lines that may have been created
cleanup_bashrc_empty_lines

# Call the install timer creation function
create_install_timer

# Call the wallet backup timer creation function
create_wallet_backup_timer

# Call the swap check/update function
check_and_update_swap

# Call the Lynx binary check/install function
check_and_install_lynx_binary

# Call the lynx service creation function
create_lynx_service

# Call the lynx service running check function
ensure_lynx_service_running

# Call the blockchain sync check function
check_blockchain_sync