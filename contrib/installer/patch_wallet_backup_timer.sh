#!/bin/bash
# patch_wallet_backup_timer.sh - Install the wallet backup service/timer pair if missing
#
# Called by the {chain}-patch-wallet-backup-timer.timer systemd unit. Expects
# these environment variables to be set by the service unit:
#
#   CHAIN_LOWER         - lowercase chain name (e.g. galatea)
#   EFFECTIVE_CHAIN     - display name (e.g. Galatea)
#   SERVICE_NAME        - daemon service unit (e.g. galatea.service)
#   WORKING_DIRECTORY   - data directory (e.g. /var/lib/galatea)
#   BACKUP_SERVICE_UNIT - wallet backup service (e.g. galatea-wallet-backup.service)
#   BACKUP_TIMER_UNIT   - wallet backup timer (e.g. galatea-wallet-backup.timer)
#   TIMER_UNIT          - this timer's unit name (for self-disabling)

set -euo pipefail

for var in CHAIN_LOWER EFFECTIVE_CHAIN SERVICE_NAME WORKING_DIRECTORY BACKUP_SERVICE_UNIT BACKUP_TIMER_UNIT TIMER_UNIT; do
    if [ -z "${!var:-}" ]; then
        logger -t patch_wallet_backup_timer "ERROR: $var not set. Exiting."
        exit 1
    fi
done

service_path="/etc/systemd/system/${BACKUP_SERVICE_UNIT}"
timer_path="/etc/systemd/system/${BACKUP_TIMER_UNIT}"

# If both unit files already exist and the timer is enabled, disable this timer and exit
if [ -f "$service_path" ] && [ -f "$timer_path" ] && systemctl is-enabled --quiet "$BACKUP_TIMER_UNIT" 2>/dev/null; then
    logger -t patch_wallet_backup_timer "$BACKUP_TIMER_UNIT already installed. Disabling timer."
    systemctl stop "$TIMER_UNIT" 2>/dev/null || true
    systemctl disable "$TIMER_UNIT" 2>/dev/null || true
    exit 0
fi

cat <<EOF > "$service_path"
[Unit]
Description=Backup ${EFFECTIVE_CHAIN} wallet every 60 minutes
Documentation=https://getlynx.io/
After=${SERVICE_NAME}

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
StandardOutput=journal
StandardError=journal
Environment=HOME=${WORKING_DIRECTORY}
WorkingDirectory=${WORKING_DIRECTORY}
User=root
Group=root
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EOF

cat <<EOF > "$timer_path"
[Unit]
Description=Backup ${EFFECTIVE_CHAIN} wallet every 60 minutes
Documentation=https://getlynx.io/

[Timer]
OnBootSec=15min
OnUnitActiveSec=60min
AccuracySec=5m
Unit=${BACKUP_SERVICE_UNIT}
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable "$BACKUP_TIMER_UNIT" >/dev/null 2>&1
systemctl start "$BACKUP_TIMER_UNIT" >/dev/null 2>&1
logger -t patch_wallet_backup_timer "Installed $BACKUP_SERVICE_UNIT and $BACKUP_TIMER_UNIT."

# Self-disable timer
systemctl stop "$TIMER_UNIT" 2>/dev/null || true
systemctl disable "$TIMER_UNIT" 2>/dev/null || true
logger -t patch_wallet_backup_timer "Disabled $TIMER_UNIT."
