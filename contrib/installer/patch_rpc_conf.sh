#!/bin/bash
# patch_rpc_conf.sh - Patch chain conf file with per-chain RPC loopback address
#
# Called by the {chain}-patch_rpc_conf.timer systemd unit. Expects these
# environment variables to be set by the service unit:
#
#   CONF_PATH    - full path to the chain conf file
#   RPC_HOST     - target loopback IP (e.g. 127.0.0.244)
#   SERVICE_NAME - daemon systemd service unit name
#   TIMER_UNIT   - this timer's unit name (for self-disabling)

set -euo pipefail

# Validate required environment variables
for var in CONF_PATH RPC_HOST SERVICE_NAME TIMER_UNIT; do
    if [ -z "${!var:-}" ]; then
        logger -t patch_rpc_conf "ERROR: $var not set. Exiting."
        exit 1
    fi
done

# If the conf file doesn't exist yet, exit and let the timer retry
if [ ! -f "$CONF_PATH" ]; then
    logger -t patch_rpc_conf "Conf file $CONF_PATH not found. Will retry."
    exit 0
fi

# Check if rpcbind is already set to the target address
CURRENT=$(grep -m1 '^main\.rpcbind=' "$CONF_PATH" 2>/dev/null | cut -d= -f2)
if [ "$CURRENT" = "$RPC_HOST" ]; then
    logger -t patch_rpc_conf "main.rpcbind already set to $RPC_HOST. Disabling timer."
    systemctl stop "$TIMER_UNIT" 2>/dev/null || true
    systemctl disable "$TIMER_UNIT" 2>/dev/null || true
    exit 0
fi

# Patch the conf file (substitute if present, append if missing)
if grep -q '^main\.rpcbind=' "$CONF_PATH" 2>/dev/null; then
    sed -i "s|^main\.rpcbind=.*|main.rpcbind=$RPC_HOST|" "$CONF_PATH"
else
    echo "main.rpcbind=$RPC_HOST" >> "$CONF_PATH"
fi
if grep -q '^main\.rpcallowip=' "$CONF_PATH" 2>/dev/null; then
    sed -i "s|^main\.rpcallowip=.*|main.rpcallowip=$RPC_HOST|" "$CONF_PATH"
else
    echo "main.rpcallowip=$RPC_HOST" >> "$CONF_PATH"
fi
logger -t patch_rpc_conf "Updated main.rpcbind and main.rpcallowip to $RPC_HOST in $CONF_PATH."

# Restart the daemon to pick up the new settings
systemctl restart "$SERVICE_NAME" 2>/dev/null || true
logger -t patch_rpc_conf "Restarted $SERVICE_NAME."

# Disable the timer now that patching is complete
systemctl stop "$TIMER_UNIT" 2>/dev/null || true
systemctl disable "$TIMER_UNIT" 2>/dev/null || true
logger -t patch_rpc_conf "Disabled $TIMER_UNIT."
