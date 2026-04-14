#!/bin/bash
# patch_firewall.sh - Apply dynamic firewall rules using per-chain iptables sub-chains
#
# Architecture:
#   INPUT → SPARK (parent chain)
#     SPARK contains: lo ACCEPT, ESTABLISHED/RELATED ACCEPT, SSH ACCEPT,
#                     jumps to per-chain sub-chains, terminal DROP
#     SPARK_GALATEA contains: galatea P2P port ACCEPT
#     SPARK_FENRIR  contains: fenrir P2P port ACCEPT
#     ... etc.
#
# Each chain's timer only flushes its own sub-chain — never INPUT or SPARK.
# A flock serializes concurrent runs to avoid iptables race conditions.
#
# Called by the {chain}-patch-firewall.timer systemd unit. Expects these
# environment variables to be set by the service unit:
#
#   CLI_PATH     - full path to the CLI binary (e.g. /usr/local/bin/fenrir-cli)
#   DATADIR      - daemon data directory (e.g. /var/lib/fenrir)
#   RPCCONNECT   - RPC loopback IP (e.g. 127.0.0.108)
#   CHAIN_NAME   - display name for logging (e.g. Fenrir)
#   CHAIN_LOWER  - lowercase chain name (e.g. fenrir)
#   TIMER_UNIT   - fast-poll timer unit name (for self-disabling)

set -euo pipefail

# Validate required environment variables
for var in CLI_PATH DATADIR RPCCONNECT CHAIN_NAME CHAIN_LOWER TIMER_UNIT; do
    if [ -z "${!var:-}" ]; then
        logger -t patch_firewall "ERROR: $var not set. Exiting."
        exit 1
    fi
done

# Detect the SSH port from sshd_config (default 22)
ssh_port=$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}') || true
ssh_port="${ssh_port:-22}"

# Dynamically detect the P2P port from the daemon
p2p_port=""
if [ -f "$CLI_PATH" ]; then
    p2p_port=$("$CLI_PATH" -datadir="$DATADIR" -rpcconnect="$RPCCONNECT" getnetworkinfo 2>/dev/null | sed -n '/"localaddresses"/,/]/p' | grep '"port"' | head -1 | sed 's/[^0-9]//g') || true
fi

# If the daemon isn't ready yet, exit and let the timer retry
if [ -z "$p2p_port" ]; then
    logger -t patch_firewall "$CHAIN_NAME: Could not detect P2P port from daemon. Will retry."
    exit 0
fi

logger -t patch_firewall "$CHAIN_NAME: Detected P2P port $p2p_port. Applying rules."

CHAIN_UPPER=$(echo "$CHAIN_LOWER" | tr '[:lower:]' '[:upper:]')
PARENT="SPARK"
SUBCHAIN="SPARK_${CHAIN_UPPER}"
LOCKFILE="/var/lock/spark-iptables"

# All iptables mutations happen inside a flock to prevent concurrent runs from
# interleaving (e.g. two chains' timers firing at the same moment).
(
    flock -w 30 200 || { logger -t patch_firewall "$CHAIN_NAME: Could not acquire lock. Will retry."; exit 0; }

    # --- 1. Ensure SPARK parent chain exists and is attached to INPUT ---
    iptables -N "$PARENT" 2>/dev/null || true
    # INSERT at position 1 so SPARK takes priority over any legacy rules
    iptables -C INPUT -j "$PARENT" 2>/dev/null || iptables -I INPUT 1 -j "$PARENT"

    # --- 2. Ensure shared rules in SPARK (idempotent, never flushed) ---
    # Loopback
    iptables -C "$PARENT" -i lo -j ACCEPT 2>/dev/null || \
        iptables -I "$PARENT" 1 -i lo -j ACCEPT

    # Established/related connections
    iptables -C "$PARENT" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -I "$PARENT" 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # SSH
    iptables -C "$PARENT" -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null || \
        iptables -I "$PARENT" 3 -p tcp --dport "$ssh_port" -j ACCEPT

    # --- 3. Create this chain's sub-chain if it doesn't exist ---
    iptables -N "$SUBCHAIN" 2>/dev/null || true

    # --- 4. Flush only this chain's sub-chain ---
    iptables -F "$SUBCHAIN"

    # --- 5. Populate the sub-chain with this chain's rules ---
    iptables -A "$SUBCHAIN" -p tcp --dport "$p2p_port" -j ACCEPT

    # --- 6. Ensure SPARK has a jump to this sub-chain (before DROP) ---
    if ! iptables -C "$PARENT" -j "$SUBCHAIN" 2>/dev/null; then
        # Find the DROP rule number (if any) so we can insert before it
        # Note: || true prevents pipefail from killing the subshell when grep finds no match
        drop_line=$(iptables -L "$PARENT" --line-numbers -n 2>/dev/null | grep -i "DROP" | tail -1 | awk '{print $1}') || true
        if [ -n "$drop_line" ]; then
            iptables -I "$PARENT" "$drop_line" -j "$SUBCHAIN"
        else
            iptables -A "$PARENT" -j "$SUBCHAIN"
        fi
    fi

    # --- 7. Ensure terminal DROP is last rule in SPARK ---
    # Remove any existing DROP(s) and re-append as last
    while iptables -D "$PARENT" -j DROP 2>/dev/null; do :; done
    iptables -A "$PARENT" -j DROP

    # --- 8. Clean up legacy rules from INPUT (from old patch_firewall.sh) ---
    # Remove any non-SPARK rules that were appended directly to INPUT by the old script.
    # We keep only the jump to SPARK. This is idempotent and safe.
    while true; do
        # Find the first INPUT rule that is NOT the jump to SPARK
        # Note: || true prevents pipefail from killing the subshell when grep finds no match
        legacy_line=$(iptables -L INPUT --line-numbers -n 2>/dev/null | tail -n +3 | grep -v "SPARK" | head -1 | awk '{print $1}') || true
        if [ -n "$legacy_line" ]; then
            iptables -D INPUT "$legacy_line" 2>/dev/null || break
        else
            break
        fi
    done

) 200>"$LOCKFILE"

# Purge old journal entries to keep the drive trim
journalctl --vacuum-time=7d >/dev/null 2>&1

logger -t patch_firewall "$CHAIN_NAME: Firewall rules applied at $(date). Sub-chain: $SUBCHAIN, P2P port: $p2p_port, SSH port: $ssh_port"

# Disable the fast-poll timer now that firewall is configured
systemctl stop "$TIMER_UNIT" 2>/dev/null || true
systemctl disable "$TIMER_UNIT" 2>/dev/null || true
logger -t patch_firewall "$CHAIN_NAME: Disabled fast-poll timer $TIMER_UNIT."
