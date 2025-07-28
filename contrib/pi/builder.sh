#!/bin/bash
set -euo pipefail

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
    stakes_won=$(grep "New proof-of-stake block found" $HOME/.lynx/debug.log 2>/dev/null | grep "$(date -d '24 hours ago' '+%Y-%m-%d')" | wc -l)
    if [ -z "$stakes_won" ] || [ "$stakes_won" = "0" ]; then
        stakes_won=$(grep "New proof-of-stake block found" $HOME/.lynx/debug.log 2>/dev/null | grep "$(date '+%Y-%m-%d')" | wc -l)
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
    
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           🦊 LYNX NODE COMMANDS 🦊                           ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════╣"
    echo "║  NODE STATUS:                                                                ║"
    echo "║    🎯 Stakes won in last 24 hours: $stakes_won$spacing║"
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
    echo "║    lyc   - Edit Lynx config (nano ~/.lynx/lynx.conf)                         ║"
    echo "║    lyl   - View Lynx debug log (tail -f ~/.lynx/debug.log)                   ║"
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

# Function to add useful aliases and MOTD to $HOME/.bashrc
add_aliases_to_bashrc() {
    local BASHRC="$HOME/.bashrc"
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
# Function to get RPC credentials
get_rpc_credentials() {
    if [ -f \$HOME/.lynx/lynx.conf ]; then
        RPC_USER=\$(grep "^main\.rpcuser=" \$HOME/.lynx/lynx.conf | cut -d'=' -f2)
        RPC_PASS=\$(grep "^main\.rpcpassword=" \$HOME/.lynx/lynx.conf | cut -d'=' -f2)
        
        if [ -n "\$RPC_USER" ] && [ -n "\$RPC_PASS" ]; then
            return 0
        else
            echo "RPC credentials not found in lynx.conf"
            return 1
        fi
    else
        echo "lynx.conf not found at \$HOME/.lynx/lynx.conf"
        return 1
    fi
}

alias gb='get_rpc_credentials && lynx-cli -rpcuser="\$RPC_USER" -rpcpassword="\$RPC_PASS" getbalances'
alias gna='get_rpc_credentials && lynx-cli -rpcuser="\$RPC_USER" -rpcpassword="\$RPC_PASS" getnewaddress'
alias lag='get_rpc_credentials && lynx-cli -rpcuser="\$RPC_USER" -rpcpassword="\$RPC_PASS" listaddressgroupings'
alias lv='lynx-cli -version'
alias lyc='nano \$HOME/.lynx/lynx.conf'
alias lyl='tail -n 500 -f \$HOME/.lynx/debug.log'
alias lynx='systemctl stop lynx && rm -rf \$HOME/.lynx/debug.log && systemctl start lynx'
alias sta='get_rpc_credentials && lynx-cli -rpcuser="\$RPC_USER" -rpcpassword="\$RPC_PASS" sendtoaddress \$1 \$2'
alias jou='journalctl -t builder.sh -n 100 -f'
alias gbi='get_rpc_credentials && lynx-cli -rpcuser="\$RPC_USER" -rpcpassword="\$RPC_PASS" getblockchaininfo'
alias lelp='get_rpc_credentials && lynx-cli -rpcuser="\$RPC_USER" -rpcpassword="\$RPC_PASS" help'
alias motd='show_lynx_motd'
alias stat='systemctl status lynx'
swe() { get_rpc_credentials && lynx-cli -rpcuser="\$RPC_USER" -rpcpassword="\$RPC_PASS" sendtoaddress "\$1" "\$2" "" "" true; }
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
    logger -t builder.sh "Downloading $filename to $HOME..."
    wget -q -O "$HOME/$filename" "$download_url" || { logger -t builder.sh "Failed to download $filename"; return 1; }
    logger -t builder.sh "Extracting $filename..."
    unzip -o "$HOME/$filename" -d /usr/local/bin/ || { logger -t builder.sh "Failed to extract $filename"; return 1; }
    chmod +x /usr/local/bin/lynx* || logger -t builder.sh "Failed to chmod Lynx binaries"
    logger -t builder.sh "Lynx ARM binary installed successfully."
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
ExecStart=/usr/local/bin/lynxd -daemon=1 -assumevalid=fa71fe1bdfa0f68ef184c8cddc4c401cae852b566f36042ec59396c9273e8bce
ExecStop=/usr/local/bin/lynx-cli stop
Restart=on-failure
RestartSec=90
User=root
TimeoutStopSec=90
Environment=HOME=/root
WorkingDirectory=/root

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
        exit 0
    fi
}

# Function to read RPC credentials from lynx.conf
get_rpc_credentials() {
    if [ -f $HOME/.lynx/lynx.conf ]; then
        RPC_USER=$(grep "^main\.rpcuser=" $HOME/.lynx/lynx.conf | cut -d'=' -f2)
        RPC_PASS=$(grep "^main\.rpcpassword=" $HOME/.lynx/lynx.conf | cut -d'=' -f2)
        
        if [ -n "$RPC_USER" ] && [ -n "$RPC_PASS" ]; then
            logger -t builder.sh "RPC credentials loaded from lynx.conf: user=$RPC_USER"
            return 0
        else
            logger -t builder.sh "RPC credentials not found in lynx.conf"
            return 1
        fi
    else
        logger -t builder.sh "lynx.conf not found at $HOME/.lynx/lynx.conf"
        return 1
    fi
}

# Function to check if blockchain sync is complete
check_blockchain_sync() {
    # Get RPC credentials
    if get_rpc_credentials; then
        # Try to get blockchain info with error handling
        SYNC_STATUS=$(/usr/local/bin/lynx-cli -rpcuser="$RPC_USER" -rpcpassword="$RPC_PASS" getblockchaininfo 2>/dev/null | grep -o '"initialblockdownload":[^,}]*' | sed 's/.*://' | tr -d '"' | xargs)

        # Check if the command succeeded and returned valid data
        if [ $? -eq 0 ] && [ -n "$SYNC_STATUS" ] && [ "$SYNC_STATUS" != "null" ]; then
            if [ "$SYNC_STATUS" = "false" ]; then
                logger -t builder.sh "Blockchain sync complete. Stopping and disabling builder.timer."
                systemctl stop builder.timer
                systemctl disable builder.timer
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
    else
        logger -t builder.sh "Failed to get RPC credentials. Cannot check blockchain sync."
        return 1
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
