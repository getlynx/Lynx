#!/bin/bash
# patch_wallet_backup_script.sh - Install /usr/local/bin/{chain}-backup.sh if missing
#
# Called by the {chain}-patch-wallet-backup-script.timer systemd unit. Expects
# these environment variables to be set by the service unit:
#
#   CHAIN_LOWER        - lowercase chain name (e.g. galatea)
#   EFFECTIVE_CHAIN    - display name (e.g. Galatea)
#   CLI_NAME           - CLI binary (e.g. galatea-cli)
#   CLI_FLAGS          - CLI flags (e.g. -datadir=/var/lib/galatea -rpcconnect=127.0.0.193)
#   CONF_NAME          - conf filename (e.g. galatea.conf)
#   WORKING_DIRECTORY  - data directory (e.g. /var/lib/galatea)
#   TIMER_UNIT         - this timer's unit name (for self-disabling)

set -euo pipefail

for var in CHAIN_LOWER EFFECTIVE_CHAIN CLI_NAME CLI_FLAGS CONF_NAME WORKING_DIRECTORY TIMER_UNIT; do
    if [ -z "${!var:-}" ]; then
        logger -t patch_wallet_backup_script "ERROR: $var not set. Exiting."
        exit 1
    fi
done

# If the backup script is already installed, disable the timer and exit
if [ -f "/usr/local/bin/${CHAIN_LOWER}-backup.sh" ]; then
    logger -t patch_wallet_backup_script "/usr/local/bin/${CHAIN_LOWER}-backup.sh already exists. Disabling timer."
    systemctl stop "$TIMER_UNIT" 2>/dev/null || true
    systemctl disable "$TIMER_UNIT" 2>/dev/null || true
    exit 0
fi

# Ensure backup directory exists
mkdir -p "/var/lib/${CHAIN_LOWER}-backup"
chown root:root "/var/lib/${CHAIN_LOWER}-backup"
chmod 700 "/var/lib/${CHAIN_LOWER}-backup"

# Install {chain}-backup.sh with chain-specific substitutions
cat <<'BACKUPEOF' | sed "s|/var/lib/lynx-backup|/var/lib/${CHAIN_LOWER}-backup|g; s|/var/lib/lynx|${WORKING_DIRECTORY}|g; s|lynx-cli|${CLI_NAME} ${CLI_FLAGS}|g; s|lynx\.conf|${CONF_NAME}|g; s|--quiet lynx;|--quiet ${CHAIN_LOWER};|g; s|Lynx|${EFFECTIVE_CHAIN}|g" > "/usr/local/bin/${CHAIN_LOWER}-backup.sh"
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
if ! lynx-cli backupwallet "$BACKUP_FILE" 2>/dev/null; then
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

chmod +x "/usr/local/bin/${CHAIN_LOWER}-backup.sh"
chown root:root "/usr/local/bin/${CHAIN_LOWER}-backup.sh"
logger -t patch_wallet_backup_script "Installed /usr/local/bin/${CHAIN_LOWER}-backup.sh."

# Self-disable timer
systemctl stop "$TIMER_UNIT" 2>/dev/null || true
systemctl disable "$TIMER_UNIT" 2>/dev/null || true
logger -t patch_wallet_backup_script "Disabled $TIMER_UNIT."
