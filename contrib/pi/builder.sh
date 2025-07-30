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
#   - Creates /var/lib/lynx directory if it doesn't exist
#   - Sets proper ownership (root:root) and permissions (755)
#   - Creates symlink /root/.lynx -> /var/lib/lynx for compatibility
#
################################################################################

# Create the Lynx data directory with proper permissions
mkdir -p /var/lib/lynx
chown root:root /var/lib/lynx
chmod 755 /var/lib/lynx

# Create symbolic link for backward compatibility with legacy configurations
# This ensures that any scripts or tools expecting ~/.lynx will still work
if [ ! -e /root/.lynx ]; then
    ln -sf /var/lib/lynx /root/.lynx
fi

# Set the working directory variable for use throughout the script
WorkingDirectory=/var/lib/lynx

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
    # Count stakes won in the last 24 hours
    stakes_won=$(grep "New proof-of-stake block found" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d '24 hours ago' '+%Y-%m-%d')" | wc -l)
    if [ -z "$stakes_won" ] || [ "$stakes_won" = "0" ]; then
        stakes_won=$(grep "New proof-of-stake block found" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date '+%Y-%m-%d')" | wc -l)
    fi
    
    # Calculate dynamic spacing based on number of digits
    stakes_digits=${#stakes_won}
    if [ "$stakes_digits" -eq 1 ]; then
        spacing="                                         "
    elif [ "$stakes_digits" -eq 2 ]; then
        spacing="                                        "
    elif [ "$stakes_digits" -eq 3 ]; then
        spacing="                                       "
    else
        spacing="                                      "
    fi

    # Count total blocks (UpdateTip) in the last 24 hours for yield calculation
    total_blocks=$(grep "UpdateTip" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date -d '24 hours ago' '+%Y-%m-%d')" | wc -l)
    if [ -z "$total_blocks" ] || [ "$total_blocks" = "0" ]; then
        total_blocks=$(grep "UpdateTip" $WorkingDirectory/debug.log 2>/dev/null | grep "$(date '+%Y-%m-%d')" | wc -l)
    fi
    
    # Calculate percent yield (stakes won / total blocks * 100)
    if [ "$total_blocks" -gt 0 ]; then
        # Use bc for floating point arithmetic with 2 decimal places
        percent_yield=$(echo "scale=2; $stakes_won * 100 / $total_blocks" | bc 2>/dev/null || echo "0.00")
    else
        percent_yield="0.00"
    fi
    
    # Calculate dynamic spacing for percent yield display
    yield_digits=${#percent_yield}
    if [ "$yield_digits" -le 6 ]; then
        yield_spacing="                                    "
    elif [ "$yield_digits" -eq 7 ]; then
        yield_spacing="                                   "
    else
        yield_spacing="                                  "
    fi
    
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
    
    # Calculate dynamic spacing for 7-day stakes display
    stakes_7d_digits=${#stakes_won_7d}
    if [ "$stakes_7d_digits" -eq 1 ]; then
        spacing_7d="                                         "
    elif [ "$stakes_7d_digits" -eq 2 ]; then
        spacing_7d="                                        "
    elif [ "$stakes_7d_digits" -eq 3 ]; then
        spacing_7d="                                       "
    else
        spacing_7d="                                      "
    fi
    
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
        # Use bc for floating point arithmetic with 2 decimal places
        percent_yield_7d=$(echo "scale=2; $stakes_won_7d * 100 / $total_blocks_7d" | bc 2>/dev/null || echo "0.00")
    else
        percent_yield_7d="0.00"
    fi
    
    # Calculate dynamic spacing for 7-day percent yield display
    yield_7d_digits=${#percent_yield_7d}
    if [ "$yield_7d_digits" -le 6 ]; then
        yield_7d_spacing="                                    "
    elif [ "$yield_7d_digits" -eq 7 ]; then
        yield_7d_spacing="                                   "
    else
        yield_7d_spacing="                                  "
    fi
    
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           🦊 LYNX NODE COMMANDS 🦊                           ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════╣"
    echo "║  NODE STATUS:                                                                ║"
    echo "║    🎯 Stakes won in last 24 hours: $stakes_won$spacing║"
    echo "║    📊 Yield rate (stakes/blocks): ${percent_yield}%$yield_spacing║"
    echo "║    🎯 Stakes won in last 7 days: $stakes_won_7d$spacing_7d║"
    echo "║    📊 7-day yield rate (stakes/blocks): ${percent_yield_7d}%$yield_7d_spacing║"
    echo "║                                                                              ║"
    echo "║  WALLET COMMANDS:                                                            ║"
    echo "║    gb    - Get wallet balances (lynx-cli getbalances)                        ║"
    echo "║    gna   - Generate new address (lynx-cli getnewaddress)                     ║"
    echo "║    lag   - List address groupings (lynx-cli listaddressgroupings)            ║"
    echo "║    sta   - Send to address (lynx-cli sendtoaddress)                          ║"
    echo "║    swe   - Sweep a wallet (lynx-cli sendtoaddress)                           ║"
    echo "║                                                                              ║"
    echo "║  SYSTEM COMMANDS:                                                            ║"
    echo "║    lv    - Show Lynx version (lynx-cli -version)                             ║"
    echo "║    lyc   - Edit Lynx config (nano /var/lib/lynx/lynx.conf)                   ║"
    echo "║    lyl   - View Lynx debug log (tail -f /var/lib/lynx/debug.log)             ║"
    echo "║    lynx  - Restart Lynx daemon (systemctl restart lynx)                      ║"
    echo "║    jou   - View builder logs (journalctl -t builder.sh -n 100 -f)            ║"
    echo "║    gbi   - Get blockchain info (lynx-cli getblockchaininfo)                  ║"
    echo "║    lelp  - Show Lynx help (lynx-cli help)                                    ║"
    echo "║    stat  - Check Lynx service status (systemctl status lynx)                 ║"
    echo "║                                                                              ║"
    echo "║  USEFUL COMMANDS:                                                            ║"
    echo "║    htop  - Monitor system resources                                          ║"
    echo "║    motd  - Show this help message again                                      ║"
    echo "║                                                                              ║"
    echo "║  📚 Complete project documentation: https://docs.getlynx.io/                 ║"
    echo "║  💾 Store files permanently: https://clevver.org/                            ║"
    echo "║  🔍 Blockchain explorer: https://chainz.cryptoid.info/lynx/                  ║"
    echo "║  📈 Trade Lynx (LYNX/LTC): https://freixlite.com/market/LYNX/LTC             ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
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
alias lag='lynx-cli listaddressgroupings'
alias lv='lynx-cli -version'
alias lyc='nano $WorkingDirectory/lynx.conf'
alias lyl='tail -n 500 -f $WorkingDirectory/debug.log'
alias lynx='systemctl stop lynx && rm -rf $WorkingDirectory/debug.log && systemctl start lynx'
alias sta='lynx-cli sendtoaddress \$1 \$2'
alias jou='journalctl -t builder.sh -n 100 -f'
alias gbi='lynx-cli getblockchaininfo'
alias lelp='lynx-cli help'
alias motd='show_lynx_motd'
alias stat='systemctl status lynx'
swe() { lynx-cli sendtoaddress "\$1" "\$2" "" "" true; }
$ALIAS_BLOCK_END

$MOTD_BLOCK_START
$(create_motd_function)
show_lynx_motd
$MOTD_BLOCK_END
EOF
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

# Only log if system has been running for 6 hours or less
if [ "$uptime_seconds" -le "$log_threshold_seconds" ]; then
    # Add aliases to bashrc
    add_aliases_to_bashrc
fi

# Call the builder timer creation function
create_builder_timer

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
