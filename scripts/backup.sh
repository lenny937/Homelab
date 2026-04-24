#!/bin/bash

# ── CONFIG ───────────────────────────────────────────
DOCKER_DIR="/home/lenny/docker"
BACKUP_DIR="/media/lenny/jellyfin-media/backups"
GDRIVE_DIR="gdrive:homelab-backups"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="homelab-backup-$DATE.tar.gz"
LOG="/home/lenny/backup.log"

# ── LOGGING ──────────────────────────────────────────
echo "[$DATE] Starting backup..." >> $LOG

# ── SAVE CRONTAB ─────────────────────────────────────
crontab -l > /home/lenny/docker/crontab-backup.txt

# ── CREATE BACKUP DIRS ───────────────────────────────
mkdir -p $BACKUP_DIR
mkdir -p $BACKUP_DIR/homeassistant

# ── EXPORT PORTAINER DOCKER VOLUME ───────────────────
docker run --rm \
  -v docker_portainer_data:/data \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/portainer-volume-$DATE.tar.gz /data

# ── COMPRESS DOCKER CONFIGS + TAILSCALE STATE ────────
sudo tar -czf $BACKUP_DIR/$BACKUP_NAME \
  --exclude="$DOCKER_DIR/jellyfin/config/transcodes" \
  --exclude="$DOCKER_DIR/jellyfin/config/cache" \
  --exclude="$DOCKER_DIR/qbittorrent/config/qBittorrent/ipc-socket" \
  --ignore-failed-read \
  $DOCKER_DIR \
  /var/lib/tailscale

echo "[$DATE] Local backup complete: $BACKUP_NAME" >> $LOG

# ── SYNC HOME ASSISTANT BACKUPS FROM PI ──────────────
# Requires SSH key at ~/.ssh/pi_ha (see configs/tailscale-pihole-dns.md)
rsync -av --delete \
  -e "ssh -i /home/lenny/.ssh/pi_ha -p 22" \
  root@192.168.1.124:/backup/ \
  $BACKUP_DIR/homeassistant/

echo "[$DATE] Home Assistant backup sync complete." >> $LOG

# ── SYNC TO GOOGLE DRIVE ─────────────────────────────
rclone copy $BACKUP_DIR/$BACKUP_NAME $GDRIVE_DIR/ --log-file=$LOG
rclone copy $BACKUP_DIR/homeassistant/ $GDRIVE_DIR/homeassistant/ --log-file=$LOG

echo "[$DATE] Google Drive sync complete." >> $LOG

# ── CLEANUP OLD BACKUPS (keep last 7) ────────────────
ls -t $BACKUP_DIR/homelab-backup-*.tar.gz | tail -n +8 | xargs -r rm
ls -t $BACKUP_DIR/portainer-volume-*.tar.gz | tail -n +8 | xargs -r rm

echo "[$DATE] Cleanup complete. Done." >> $LOG
