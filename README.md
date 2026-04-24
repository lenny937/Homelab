# Lenny's Homelab

Last updated: 2026-04-24

---

## Overview

A Docker Compose-based homelab running on a Lenovo V15 Ubuntu server. Includes a full media stack (Jellyfin + VPN-isolated qBittorrent via WireGuard), network-wide ad blocking via Pi-hole, automated backups with 3-2-1 strategy, Home Assistant integration, and remote access via Tailscale with Pi-hole DNS pushed to all Tailscale devices.

---

## Hardware

| Device | Role | IP |
|--------|------|----|
| Lenovo V15 G3 ABA (Ubuntu 24.04) | Main homelab server | 192.168.1.152 |
| Home Assistant Pi (HAOS 17.2) | Home automation | 192.168.1.124 |
| M1 MacBook Air | Management / daily driver | DHCP |
| BT Smart Hub 2 | Router/gateway | 192.168.1.254 |
| 2TB USB Drive (/dev/sda) | Media + backups | — |
| 511GB NVMe (/dev/nvme0n1) | Ubuntu OS | — |

---

## Storage Layout

    /dev/nvme0n1p2   → Ubuntu OS (511GB)
    /dev/sda1        → 2TB USB, mounted at /media/lenny/jellyfin-media
      ├── media/
      │   ├── Shows/
      │   └── Movies/
      ├── downloads/
      │   └── incomplete/
      ├── backups/              → nightly backup archives (7 days)
      │   └── homeassistant/   → HA backup pulls from Pi
      └── timeshift/            → weekly OS snapshots

---

## Docker Stack

| Container | Image | Port | Notes |
|-----------|-------|------|-------|
| Jellyfin | linuxserver/jellyfin | host networking | Media server |
| Portainer | portainer/portainer-ce | 9000 | Container management |
| Pi-hole | pihole/pihole | 53, 8080 | DNS + ad blocking |
| Watchtower | containrrr/watchtower | — | Auto-updates at 4am |
| Nginx Proxy Manager | jc21/nginx-proxy-manager | 80, 443, 81 | Reverse proxy |
| Homepage | ghcr.io/gethomepage/homepage | 3000 | Dashboard |
| Uptime Kuma | louislam/uptime-kuma | 3001 | Service monitoring |
| Scrutiny | ghcr.io/analogj/scrutiny | 8082 | Drive health |
| Gluetun | qmcgaw/gluetun | 8000, 8081, 6881 | WireGuard VPN gateway |
| qBittorrent | linuxserver/qbittorrent | via Gluetun | VPN-isolated torrenting |

---

## VPN - WireGuard + ProtonVPN

qBittorrent runs inside Gluetun's network namespace (network_mode: service:gluetun).
Kernel-enforced kill switch - qBittorrent cannot reach the internet except through the VPN tunnel.

- Protocol: WireGuard (faster and lower CPU than OpenVPN)
- Provider: ProtonVPN Switzerland
- Port forwarding: NAT-PMP enabled (required for seeding)
- Credentials stored in /home/lenny/docker/.env (never committed to git)

Verify VPN working:

    docker exec qbittorrent wget -qO- https://ipinfo.io/ip
    curl -s https://ipinfo.io/ip

---

## Pi-hole

Network-wide ad blocking. See configs/pihole-setup.md for full setup notes.

- Version: v6
- Upstream DNS: Cloudflare 1.1.1.1 and 1.0.0.1
- DHCP: disabled (BT Hub handles DHCP)
- Listening mode: ALL (required for external queries in Docker)
- iCloud Private Relay: blocked automatically
- Per-device DNS set manually (BT Hub does not expose DNS settings)

Access: http://192.168.1.152:8080/admin

---

## Tailscale + Pi-hole DNS

Pi-hole DNS pushed to all Tailscale devices via admin console.
Ad blocking works on all devices even when away from home.
See configs/tailscale-pihole-dns.md for full setup notes.

- Tailscale IP: YOUR_TAILSCALE_IP
- MagicDNS: YOUR_MAGICDNS_HOSTNAME
- Ubuntu set to --accept-dns=false to prevent DNS loop

---

## Backup System (3-2-1)

    Every night at 2am:
    ├── Docker configs + Tailscale state → USB (7 days)
    ├── Portainer volume → USB (7 days)
    ├── Home Assistant backups pulled from Pi → USB
    └── All of the above → Google Drive

    Every Sunday at 3am:
    └── Full OS Timeshift snapshot → USB

- Backup script: scripts/backup.sh
- rclone remote: gdrive (Google Drive, OAuth)
- HA SSH key: ~/.ssh/pi_ha (Ubuntu to Pi, key auth only)
- Timeshift: weekly OS snapshots to /dev/sda1

---

## Home Assistant Pi

- OS: Home Assistant OS 17.2
- SSH add-on: Terminal and SSH v10.1.0
- SSH port: 22
- Auth: SSH keys only (set via Authorized Keys field in add-on config)
- Backups pulled nightly via rsync to Ubuntu then synced to Google Drive

SSH from Mac:
    ssh -i ~/.ssh/id_ed25519 -p 22 root@192.168.1.124

SSH from Ubuntu:
    ssh -i ~/.ssh/pi_ha -p 22 root@192.168.1.124

---

## System Management

- Cockpit: https://192.168.1.152:9090

Always take Timeshift snapshot before running system updates:

    sudo timeshift --create --tags W
    docker compose down
    sudo apt update && sudo apt upgrade -y
    docker compose up -d

---

## Access URLs

| Service | URL |
|---------|-----|
| Jellyfin | http://192.168.1.152:8096 |
| qBittorrent | http://192.168.1.152:8081 |
| Portainer | http://192.168.1.152:9000 |
| Homepage | http://192.168.1.152:3000 |
| Uptime Kuma | http://192.168.1.152:3001 |
| Scrutiny | http://192.168.1.152:8082 |
| Pi-hole | http://192.168.1.152:8080/admin |
| Nginx Proxy Manager | http://192.168.1.152:81 |
| Cockpit | https://192.168.1.152:9090 |
| Home Assistant | http://192.168.1.124:8123 |

Remote: same local IPs work when Tailscale connected (subnet routing enabled).

---

## Security

- SSH key-only auth on all remote connections
- Pi-hole blocks ads, trackers, telemetry network-wide
- iCloud Private Relay blocked at DNS level
- WireGuard VPN kill switch for torrenting
- rclone config and SSH keys: chmod 600
- Tailscale for remote access (no open ports)
- Brave browser with built-in ad blocking on client devices

---

## Known Issues and Lessons Learned

- Never use ~ in docker-compose volumes, use absolute paths
- Never enable Pi-hole DHCP while BT Hub DHCP is running, causes network lockout
- Pi-hole v6 ignores DNSMASQ_LISTENING env var, use FTLCONF_dns_listeningMode=all
- Never restart Gluetun rapidly, ProtonVPN rate-limits AUTH attempts
- Always recreate Gluetun and qBittorrent together:
    docker compose up -d --force-recreate gluetun qbittorrent
- BT Smart Hub 2 has no DNS settings, per-device config required
- WireGuard endpoint IP/port must NOT be set manually with ProtonVPN and Gluetun

---

## Pending

- [ ] Router upgrade (TP-Link Archer or Asus) for network-wide DNS via DHCP
- [ ] DNS over HTTPS (cloudflared alongside Pi-hole)
- [ ] Nginx Proxy Manager with custom domain and SSL
- [ ] Sonarr/Radarr ARR stack
- [ ] Hardware-accelerated transcoding (VAAPI)
- [ ] Migrate from WiFi to wired ethernet
- [ ] Run system updates (Timeshift snapshot first)
- [ ] Proxmox migration (Phase 3)

---

## Useful Commands

    docker ps
    docker logs <container> --tail 50
    docker compose restart <container>
    docker compose up -d --force-recreate gluetun qbittorrent
    cd ~/docker && docker compose pull && docker compose up -d
    docker exec qbittorrent wget -qO- https://ipinfo.io/ip
    sudo tailscale status
    /home/lenny/backup.sh
    cat /home/lenny/backup.log
    sudo timeshift --list

---

## Repo Structure

    Homelab/
    ├── docker-compose.yml
    ├── .env.example
    ├── .gitignore
    ├── configs/
    │   ├── homepage-services.yaml
    │   ├── pihole-setup.md
    │   └── tailscale-pihole-dns.md
    └── scripts/
        ├── backup.sh
        └── qbittorrent-port-updater.sh

---

## Credits

- Jellyfin: https://jellyfin.org
- LinuxServer.io: https://www.linuxserver.io
- Pi-hole: https://pi-hole.net
- Portainer: https://www.portainer.io
- Homepage: https://gethomepage.dev
- Uptime Kuma: https://github.com/louislam/uptime-kuma
- Scrutiny: https://github.com/AnalogJ/scrutiny
- Tailscale: https://tailscale.com
- Gluetun: https://github.com/qdm12/gluetun
- ProtonVPN: https://protonvpn.com
- rclone: https://rclone.org
- Timeshift: https://github.com/linuxmint/timeshift
