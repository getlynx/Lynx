#!/bin/bash
# patch_firewall.sh - Apply dynamic firewall rules for the chain node
#
# Called by the {chain}-patch-firewall.timer systemd unit. Expects these
# environment variables to be set by the service unit:
#
#   CLI_PATH     - full path to the CLI binary (e.g. /usr/local/bin/borrelly-cli)
#   DATADIR      - daemon data directory (e.g. /var/lib/borrelly)
#   RPCCONNECT   - RPC loopback IP (e.g. 127.0.0.244)
#   CHAIN_NAME   - display name for logging (e.g. Borrelly)
#   TIMER_UNIT   - this timer's unit name (for self-disabling)

set -euo pipefail

# Validate required environment variables
for var in CLI_PATH DATADIR RPCCONNECT CHAIN_NAME TIMER_UNIT; do
    if [ -z "${!var:-}" ]; then
        logger -t patch_firewall "ERROR: $var not set. Exiting."
        exit 1
    fi
done

# Detect the SSH port from sshd_config (default 22)
ssh_port=$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
ssh_port="${ssh_port:-22}"

# Dynamically detect the P2P port from the daemon
p2p_port=""
if [ -f "$CLI_PATH" ]; then
    p2p_port=$("$CLI_PATH" -datadir="$DATADIR" -rpcconnect="$RPCCONNECT" getnetworkinfo 2>/dev/null | sed -n '/"localaddresses"/,/]/p' | grep '"port"' | head -1 | sed 's/[^0-9]//g')
fi

# If the daemon isn't ready yet, exit and let the timer retry
if [ -z "$p2p_port" ]; then
    logger -t patch_firewall "Could not detect P2P port from daemon. Will retry."
    exit 0
fi

logger -t patch_firewall "Detected P2P port from daemon: $p2p_port"

# Apply firewall rules
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
# iptables -A INPUT -p tcp --dport 8332 -j ACCEPT # RPC port
# RPC_PORT_END - This line will be updated by the rpc_port function
iptables -A INPUT -p tcp --dport $p2p_port -j ACCEPT # $CHAIN_NAME P2P port
iptables -A INPUT -j DROP

# Purge the journal history to keep the drive trim
journalctl --vacuum-time=7d >/dev/null 2>&1

logger -t patch_firewall "$CHAIN_NAME firewall rules applied at $(date)"

# Disable the timer now that firewall is configured
systemctl stop "$TIMER_UNIT" 2>/dev/null || true
systemctl disable "$TIMER_UNIT" 2>/dev/null || true
logger -t patch_firewall "Disabled $TIMER_UNIT."
