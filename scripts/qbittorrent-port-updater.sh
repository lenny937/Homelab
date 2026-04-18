#!/bin/bash
#
# qBittorrent port auto-updater
# Watches Gluetun's forwarded port and updates qBittorrent when it changes.
# Runs continuously as a systemd service.
#

set -euo pipefail

# Config
QBIT_HOST="http://192.168.1.152:8081"
QBIT_USER="admin"
QBIT_PASS="YOUR_QBIT_PASSWORD_HERE"
CHECK_INTERVAL=300  # seconds (5 minutes)
LOG_FILE="/home/lenny/docker/qbittorrent/port-updater.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get Gluetun's forwarded port (via docker exec — file is inside the container)
get_gluetun_port() {
    docker exec gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null || echo ""
}

# Get qBittorrent's current listening port via API
get_qbit_port() {
    local cookie
    cookie=$(curl -s -c - --data "username=${QBIT_USER}&password=${QBIT_PASS}" \
        "${QBIT_HOST}/api/v2/auth/login" 2>/dev/null | grep SID | awk '{print $NF}') || return 1
    
    [ -z "$cookie" ] && return 1
    
    curl -s --cookie "SID=${cookie}" "${QBIT_HOST}/api/v2/app/preferences" 2>/dev/null | \
        grep -oP '"listen_port":\K[0-9]+' || echo ""
}

# Update qBittorrent's listening port via API
update_qbit_port() {
    local new_port="$1"
    local cookie
    cookie=$(curl -s -c - --data "username=${QBIT_USER}&password=${QBIT_PASS}" \
        "${QBIT_HOST}/api/v2/auth/login" 2>/dev/null | grep SID | awk '{print $NF}') || return 1
    
    [ -z "$cookie" ] && { log "ERROR: Could not log in to qBittorrent"; return 1; }
    
    curl -s --cookie "SID=${cookie}" \
        --data "json=$(printf '{"listen_port":%d}' "$new_port")" \
        "${QBIT_HOST}/api/v2/app/setPreferences" > /dev/null
    
    log "Updated qBittorrent listening port to ${new_port}"
}

log "Port updater started"

while true; do
    gluetun_port=$(get_gluetun_port)
    
    if [ -z "$gluetun_port" ] || ! [[ "$gluetun_port" =~ ^[0-9]+$ ]]; then
        log "WARN: Could not read Gluetun port (VPN connecting?). Retrying in ${CHECK_INTERVAL}s."
        sleep "$CHECK_INTERVAL"
        continue
    fi
    
    qbit_port=$(get_qbit_port)
    
    if [ "$gluetun_port" != "$qbit_port" ]; then
        log "Port mismatch detected: Gluetun=${gluetun_port}, qBittorrent=${qbit_port}"
        update_qbit_port "$gluetun_port"
    fi
    
    sleep "$CHECK_INTERVAL"
done
