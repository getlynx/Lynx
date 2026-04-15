#!/bin/bash
# patch_swap.sh - Ensure system has at least 4GB swap
#
# Called by the {chain}-patch-swap.timer systemd unit. Expects these
# environment variables to be set by the service unit:
#
#   TIMER_UNIT   - this timer's unit name (for self-disabling)
#   ATTEMPT_FILE - path to the file tracking retry attempts

set -euo pipefail

TAG="patch_swap"
MAX_ATTEMPTS=5

# Validate required environment variables
for var in TIMER_UNIT ATTEMPT_FILE; do
    if [ -z "${!var:-}" ]; then
        logger -t "$TAG" "ERROR: $var not set. Exiting."
        exit 1
    fi
done

# --- Helper: disable the timer and exit ---
disable_timer() {
    systemctl stop "$TIMER_UNIT" 2>/dev/null || true
    systemctl disable "$TIMER_UNIT" 2>/dev/null || true
    logger -t "$TAG" "Disabled $TIMER_UNIT."
}

# --- Track attempts ---
attempt=1
if [ -f "$ATTEMPT_FILE" ]; then
    attempt=$(cat "$ATTEMPT_FILE" 2>/dev/null || echo 1)
    attempt=$((attempt + 1))
fi
echo "$attempt" > "$ATTEMPT_FILE"

logger -t "$TAG" "Attempt $attempt of $MAX_ATTEMPTS."

# --- Check if swap is already sufficient ---
current_swap=$(free -m | awk '/^Swap:/ {print $2}')
logger -t "$TAG" "Current swap size: ${current_swap}MB"

if [ "$current_swap" -ge 3072 ]; then
    logger -t "$TAG" "Swap is sufficient (>=3GB). No changes needed."
    rm -f "$ATTEMPT_FILE"
    disable_timer
    exit 0
fi

logger -t "$TAG" "Current swap is less than 3GB. Attempting to set up 4GB swap file."

# --- Preflight checks ---
if ! command -v fallocate >/dev/null 2>&1; then
    logger -t "$TAG" "WARNING: fallocate not available. Cannot create swap."
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        logger -t "$TAG" "Max attempts reached. Giving up."
        rm -f "$ATTEMPT_FILE"
        disable_timer
    fi
    exit 0
fi

if ! command -v mkswap >/dev/null 2>&1; then
    logger -t "$TAG" "WARNING: mkswap not available. Cannot create swap."
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        logger -t "$TAG" "Max attempts reached. Giving up."
        rm -f "$ATTEMPT_FILE"
        disable_timer
    fi
    exit 0
fi

if ! touch /swapfile_test 2>/dev/null; then
    logger -t "$TAG" "WARNING: Cannot write to root filesystem."
    rm -f /swapfile_test
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        logger -t "$TAG" "Max attempts reached. Giving up."
        rm -f "$ATTEMPT_FILE"
        disable_timer
    fi
    exit 0
fi
rm -f /swapfile_test

# --- Disable existing swap if present ---
if [ "$current_swap" -gt 0 ]; then
    swap_file=$(cat /proc/swaps | tail -n1 | awk '{print $1}')
    logger -t "$TAG" "Disabling existing swap: $swap_file"
    if ! swapoff "$swap_file" 2>/dev/null; then
        logger -t "$TAG" "WARNING: Failed to disable existing swap."
        if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
            logger -t "$TAG" "Max attempts reached. Giving up."
            rm -f "$ATTEMPT_FILE"
            disable_timer
        fi
        exit 0
    fi
    sed -i '/swap/d' /etc/fstab 2>/dev/null || logger -t "$TAG" "Note: Could not remove old swap entry from /etc/fstab"
fi

# --- Create new 4GB swap file ---
logger -t "$TAG" "Creating new 4GB swapfile at /swapfile"

if ! fallocate -l 4G /swapfile 2>/dev/null; then
    logger -t "$TAG" "fallocate failed. Trying dd..."
    if ! dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null; then
        logger -t "$TAG" "WARNING: Failed to create swap file."
        if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
            logger -t "$TAG" "Max attempts reached. Giving up."
            rm -f "$ATTEMPT_FILE"
            disable_timer
        fi
        exit 0
    fi
fi

# --- Set permissions, initialize, and enable ---
if ! chmod 600 /swapfile 2>/dev/null; then
    logger -t "$TAG" "WARNING: Failed to set swap file permissions."
    rm -f /swapfile
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        rm -f "$ATTEMPT_FILE"
        disable_timer
    fi
    exit 0
fi

if ! mkswap /swapfile 2>/dev/null; then
    logger -t "$TAG" "WARNING: Failed to initialize swap file."
    rm -f /swapfile
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        rm -f "$ATTEMPT_FILE"
        disable_timer
    fi
    exit 0
fi

if ! swapon /swapfile 2>/dev/null; then
    logger -t "$TAG" "WARNING: Failed to enable swap file."
    rm -f /swapfile
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        rm -f "$ATTEMPT_FILE"
        disable_timer
    fi
    exit 0
fi

# --- Persist in fstab ---
if ! echo '/swapfile none swap sw 0 0' >> /etc/fstab 2>/dev/null; then
    logger -t "$TAG" "WARNING: Failed to add swap to /etc/fstab. Swap will not persist after reboot."
fi

logger -t "$TAG" "Swap updated successfully to 4GB."
rm -f "$ATTEMPT_FILE"
disable_timer
