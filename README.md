# Home Media Server & Homelab — Ubuntu Docker Stack

A self-hosted home media server and homelab built on Ubuntu running Docker Compose. Includes Jellyfin for media streaming, qBittorrent with VPN isolation for secure torrenting, Portainer for container management, Uptime Kuma for monitoring, Scrutiny for drive health, Homepage as a unified dashboard, and Nginx Proxy Manager. Accessed remotely via Tailscale VPN with subnet routing.

## Overview

This project migrates a bare metal Jellyfin server to a Docker Compose stack while adding complementary homelab services. The setup prioritises clean separation of concerns, remote access without port forwarding, bulletproof VPN-isolated torrenting, and integration with an existing Apple-centric smart home environment (Home Assistant, HomePod, Apple TV, HomeKit).

## Architecture

```
┌─────────────────────────────────────────────┐
│     Ubuntu Server (Lenovo V15 G3 ABA)       │
│                                             │
│   ┌────────────┐  ┌──────────┐  ┌────────┐  │
│   │  Jellyfin  │  │Portainer │  │Homepage│  │
│   └────────────┘  └──────────┘  └────────┘  │
│   ┌────────────┐  ┌──────────┐  ┌────────┐  │
│   │Uptime Kuma │  │ Scrutiny │  │ Nginx  │  │
│   └────────────┘  └──────────┘  └────────┘  │
│   ┌────────────┐  ┌──────────────────────┐  │
│   │ Watchtower │  │ Gluetun (VPN) ──┐    │  │
│   └────────────┘  │    ↓            │    │  │
│                   │ qBittorrent ────┘    │  │
│                   └──────────────────────┘  │
│                      Tailscale              │
│                      (subnet route)         │
└─────────────────────────────────────────────┘
           │                  │
           │                  │
       ┌───▼───┐         ┌────▼─────┐
       │USB 2TB│         │Raspberry │
       │ Media │         │ Pi (HA)  │
       └───────┘         └──────────┘
```

## Stack Components

| Service             | Purpose                       | Port        |
|---------------------|-------------------------------|-------------|
| Jellyfin            | Media server                  | 8096        |
| qBittorrent         | Torrent client (VPN-isolated) | 8081        |
| Gluetun             | VPN gateway (ProtonVPN)       | —           |
| Portainer           | Container GUI management      | 9000        |
| Homepage            | Unified dashboard             | 3000        |
| Uptime Kuma         | Service monitoring            | 3001        |
| Scrutiny            | Drive health monitoring       | 8082        |
| Nginx Proxy Manager | Reverse proxy                 | 80, 81, 443 |
| Watchtower          | Auto-updater                  | —           |

## Storage

- **Internal NVMe** (`/dev/nvme0n1`, 476 GB): OS and Docker configs
- **USB 2 TB drive** (`/dev/sda1`): Media library and downloads
- **Mount point**: `/media/lenny/jellyfin-media` (under `/media/lenny/` so it shows in Files app sidebar)

```
/media/lenny/jellyfin-media/
├── media/
│   ├── Shows/          # Jellyfin library
│   └── Movies/         # Jellyfin library
└── downloads/          # qBittorrent downloads
    └── incomplete/
```

## Prerequisites

- Ubuntu 22.04 or later
- Docker and Docker Compose
- Tailscale account (for remote access)
- ProtonVPN Plus or Unlimited subscription (for port forwarding)
- 2 TB+ USB drive for media

## Installation

### 1. Install Docker

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Prepare USB drive (2 TB media storage)

```bash
# DESTRUCTIVE - verify device with lsblk first!
sudo wipefs -a /dev/sda
sudo fdisk /dev/sda        # g → n → Enter → Enter → Enter → w
sudo mkfs.ext4 -L jellyfin-media /dev/sda1

# Mount under /media/lenny/ so it shows in Files app
sudo mkdir -p /media/lenny/jellyfin-media
sudo blkid /dev/sda1       # note the UUID

# Add to /etc/fstab (use your UUID):
# UUID=xxxxxx  /media/lenny/jellyfin-media  ext4  defaults,nofail  0  2

sudo systemctl daemon-reload
sudo mount -a
sudo chown -R lenny:lenny /media/lenny/jellyfin-media

mkdir -p /media/lenny/jellyfin-media/media/{Shows,Movies}
mkdir -p /media/lenny/jellyfin-media/downloads/incomplete
```

### 3. Create directory structure

```bash
mkdir -p ~/docker/{jellyfin/config,gluetun,qbittorrent/config,nginx/data,nginx/letsencrypt,uptime-kuma,scrutiny}
mkdir -p /docker/homepage   # note: root-level for Homepage
cd ~/docker
```

### 4. Backup existing Jellyfin (if migrating from bare metal)

```bash
mkdir -p ~/jellyfin-backup/config ~/jellyfin-backup/data
sudo cp -r /etc/jellyfin ~/jellyfin-backup/config
sudo cp -r /var/lib/jellyfin ~/jellyfin-backup/data

sudo systemctl stop jellyfin
sudo systemctl disable jellyfin
```

### 5. Configure ProtonVPN credentials

Get your OpenVPN credentials from https://account.protonvpn.com → Account → OpenVPN / IKEv2 credentials. These are **different** from your Proton login.

Create `~/docker/.env`:

```
OPENVPN_USER=your_openvpn_username+pmp
OPENVPN_PASSWORD=your_openvpn_password
```

The `+pmp` suffix enables port forwarding (required for proper seeding).

### 6. Docker Compose configuration

Create `~/docker/docker-compose.yml`:

```yaml
services:

  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    network_mode: host
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    volumes:
      - /home/lenny/docker/jellyfin/config:/config
      - /media/lenny/jellyfin-media/media:/media:ro

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - DOCKER_API_VERSION=1.40
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * *

  nginx:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - ./nginx/data:/data
      - ./nginx/letsencrypt:/etc/letsencrypt

  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - HOMEPAGE_ALLOWED_HOSTS=192.168.1.152:3000,100.104.31.59:3000
    volumes:
      - /docker/homepage:/app/config
      - /var/run/docker.sock:/var/run/docker.sock

  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - ./uptime-kuma:/app/data

  scrutiny:
    image: ghcr.io/analogj/scrutiny:master-omnibus
    container_name: scrutiny
    restart: unless-stopped
    ports:
      - "8082:8080"
    volumes:
      - /run/udev:/run/udev:ro
      - ./scrutiny:/opt/scrutiny/config
    cap_add:
      - SYS_RAWIO
      - SYS_ADMIN
    devices:
      - /dev/nvme0n1:/dev/nvme0n1
      - /dev/sda:/dev/sda

  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "8000:8000"       # Gluetun control API
      - "8081:8081"       # qBittorrent Web UI
      - "6881:6881"       # torrent TCP
      - "6881:6881/udp"   # torrent UDP
    environment:
      - VPN_SERVICE_PROVIDER=protonvpn
      - VPN_TYPE=openvpn
      - OPENVPN_USER=${OPENVPN_USER}
      - OPENVPN_PASSWORD=${OPENVPN_PASSWORD}
      - SERVER_COUNTRIES=Switzerland,Netherlands
      - VPN_PORT_FORWARDING=on
      - VPN_PORT_FORWARDING_PROVIDER=protonvpn
      - TZ=Europe/London
    volumes:
      - /home/lenny/docker/gluetun:/gluetun
    healthcheck:
      test: /gluetun-entrypoint healthcheck
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
      - WEBUI_PORT=8081
    volumes:
      - /home/lenny/docker/qbittorrent/config:/config
      - /media/lenny/jellyfin-media/downloads:/downloads

volumes:
  portainer_data:
```

### 7. Launch the stack

```bash
cd ~/docker
docker compose up -d
```

Wait 60 seconds for Gluetun to connect, then verify VPN is working:

```bash
docker exec qbittorrent wget -qO- https://ipinfo.io/ip   # should be Swiss
curl -s https://ipinfo.io/ip                              # should be your UK IP
docker exec gluetun cat /tmp/gluetun/forwarded_port       # note this port
```

## VPN-Isolated Torrenting

qBittorrent runs inside Gluetun's network namespace (`network_mode: service:gluetun`). This is a Linux kernel feature — qBittorrent physically cannot reach the internet except through the VPN tunnel. If Gluetun dies, qBittorrent has no network at all.

### Security features

- **Kernel-enforced kill switch** — no leak possible if VPN drops
- **DNS over TLS** via Cloudflare (ISP cannot see tracker domains)
- **IPv6 blocked** at the kernel level
- **ProtonVPN port forwarding** via `+pmp` suffix (required for seeding)
- **Auto port sync** — systemd service keeps qBittorrent's port matched to Proton's rotating forwarded port

### qBittorrent settings

First login: get the temp password with `docker logs qbittorrent 2>&1 | grep "temporary password"`, then log in at `http://192.168.1.152:8081` with `admin` / that password. **Change the password immediately.**

| Tab                 | Setting                            | Value                                                          |
|---------------------|------------------------------------|----------------------------------------------------------------|
| Web UI → Security   | Cookie Secure flag                 | ❌ OFF (we're on HTTP, not HTTPS)                              |
| Web UI → Security   | Host header validation             | ❌ OFF                                                         |
| Web UI → Security   | Clickjacking protection            | ❌ OFF                                                         |
| Connection          | Port used for incoming connections | Proton's forwarded port                                        |
| Connection          | Use UPnP / NAT-PMP                 | ❌ OFF                                                         |
| Downloads           | Default Save Path                  | `/downloads`                                                   |
| Downloads           | Keep incomplete torrents in        | `/downloads/incomplete`                                        |
| Downloads           | Pre-allocate disk space            | ❌ OFF                                                         |
| BitTorrent          | DHT, PeX, LSD                      | ✅ ON                                                          |
| BitTorrent          | Encryption mode                    | Allow                                                          |
| Advanced            | Network interface                  | **Any interface** (do NOT set to `tun0` — breaks on reconnect) |
| Advanced            | Optional IP address                | All addresses                                                  |

### Port auto-updater

ProtonVPN rotates the forwarded port every few hours. The script at `scripts/qbittorrent-port-updater.sh` keeps qBittorrent in sync automatically via its Web API.

Install as systemd service:

```bash
cp scripts/qbittorrent-port-updater.sh /home/lenny/docker/
# Edit and set QBIT_PASS to your qBittorrent password
nano /home/lenny/docker/qbittorrent-port-updater.sh
chmod +x /home/lenny/docker/qbittorrent-port-updater.sh
chmod 600 /home/lenny/docker/qbittorrent-port-updater.sh

sudo cp scripts/qbit-port-updater.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable qbit-port-updater
sudo systemctl start qbit-port-updater
```

### Verify bulletproof

```bash
# qBittorrent's IP must be Swiss
docker exec qbittorrent wget -qO- https://ipinfo.io/ip
# Home IP must be different
curl -s https://ipinfo.io/ip
# All routes via tun0
docker exec qbittorrent ip route | grep tun0
```

**Real-world swarm test:** Go to https://ipleak.net/ → "Torrent Address detection" → click the magnet → load in qBittorrent → wait 60 s → refresh. IP shown must be your Swiss VPN IP, not your home IP.

## Post-Installation Configuration

### Jellyfin setup

1. Navigate to `http://<server-ip>:8096`
2. Run through the setup wizard
3. Add libraries pointing to `/media/Shows`, `/media/Movies` (the container sees these paths)
4. Add plugin repository: **Dashboard → Plugins → Repositories**
   - URL: `https://repo.jellyfin.org/files/plugin/manifest.json`
5. Install useful plugins:
   - Intro Skipper (auto-skip intros)
   - Jellyscrub (thumbnail previews)
   - Open Subtitles (auto-download subtitles)
   - Playback Reporting (watch stats)

### Open Subtitles configuration

1. Create a free account at `https://www.opensubtitles.com`
2. In Jellyfin: **Dashboard → Plugins → Open Subtitles**
3. Enter credentials and save
4. Per-library config: **Dashboard → Libraries → [Library] → Manage Library → Subtitle Downloads**
5. Enable Open Subtitles provider and select language

### Homepage configuration

Create `/docker/homepage/services.yaml`:

```yaml
- Media:
    - Jellyfin:
        href: http://192.168.1.152:8096
        description: Media Server
        icon: jellyfin.png
    - qBittorrent:
        href: http://192.168.1.152:8081
        description: Torrent client (VPN)
        icon: qbittorrent.png

- Management:
    - Portainer:
        href: http://192.168.1.152:9000
        description: Container Management
        icon: portainer.png
    - Uptime Kuma:
        href: http://192.168.1.152:3001
        description: Service Monitoring
        icon: uptime-kuma.png

- Network:
    - Gluetun:
        href: http://192.168.1.152:8000
        description: VPN gateway (Proton CH)
        icon: gluetun.png

- System:
    - Scrutiny:
        href: http://192.168.1.152:8082
        description: Drive Health
        icon: scrutiny.png

- Home:
    - Home Assistant:
        href: http://192.168.1.124:8123
        description: Home Automation
        icon: home-assistant.png
```

### Scrutiny drive configuration

For NVMe drives, Scrutiny requires an explicit collector config. Create `~/docker/scrutiny/collector.yaml`:

```yaml
version: 1
devices:
  - file: /dev/nvme0n1
    type: nvme
    device: nvme0n1
```

Run the collector manually to trigger the first scan:

```bash
sudo docker exec scrutiny /opt/scrutiny/bin/scrutiny-collector-metrics run
```

USB drives often report limited SMART data due to the USB-to-SATA bridge — this is a hardware limitation, not a config issue.

### Uptime Kuma setup

1. Navigate to `http://<server-ip>:3001`
2. Create admin account
3. Add HTTP(s) monitors for each service:
   - Jellyfin: `http://192.168.1.152:8096`
   - qBittorrent: `http://192.168.1.152:8081`
   - Portainer: `http://192.168.1.152:9000`
   - Homepage: `http://192.168.1.152:3000`
   - Scrutiny: `http://192.168.1.152:8082`
   - Home Assistant: `http://192.168.1.124:8123`

## Remote Access with Tailscale

### Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Enable subnet routing

```bash
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes
```

Then approve the subnet route in the Tailscale admin console:
- Go to `https://login.tailscale.com/admin/machines`
- Click your server → three dots → Edit route settings
- Approve `192.168.1.0/24`

### iPhone configuration

In the Tailscale iOS app:
- Enable "Use Tailscale DNS"
- Enable "Accept routes"
- No Exit Node selected

With this setup, local IPs (e.g., `http://192.168.1.152:8096`) work from anywhere when Tailscale is connected.

## Problems Encountered & Solutions

### Issue 1: Jellyfin crash loop on first launch

**Symptoms:** Container restarting with exit code 139, error about `.jellyfin-config` marker.

**Cause:** The official `jellyfin/jellyfin` image expects a specific directory structure incompatible with migrated bare metal paths.

**Solution:** Switched to `lscr.io/linuxserver/jellyfin:latest` which handles migrated configs cleanly. Used a fresh config directory and re-added libraries.

### Issue 2: Pi-hole port 53 conflict with systemd-resolved

**Symptoms:** Pi-hole fails to bind port 53.

**Cause:** Ubuntu's `systemd-resolved` holds port 53 by default.

**Solution:** Disable the stub listener in `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNSStubListener=no
```

Then restart: `sudo systemctl restart systemd-resolved`

### Issue 3: Network lockout after disabling BT Hub DHCP

**Symptoms:** Disabled DHCP on BT Hub intending to use Pi-hole's DHCP, then removed Pi-hole — all devices lost network connectivity.

**Cause:** No DHCP server on network. Pi-hole was the only provider.

**Solution:**
1. Access router from phone (still had cached IP)
2. Re-enable DHCP on BT Hub
3. Reboot router to restore default network state

**Lesson:** Don't disable BT Hub DHCP without a fully working alternative in place.

### Issue 4: Watchtower API version error

**Symptoms:** Logs showed `client version 1.25 is too old. Minimum supported API version is 1.40`.

**Solution:** Added environment variable to compose file:

```yaml
environment:
  - DOCKER_API_VERSION=1.40
```

### Issue 5: Homepage "Host validation failed"

**Symptoms:** 500 Internal Error when accessing Homepage by IP.

**Solution:** Set the `HOMEPAGE_ALLOWED_HOSTS` environment variable in the compose file with comma-separated allowed addresses.

### Issue 6: Homepage config not loading — docker doesn't expand `~`

**Symptoms:** Custom `services.yaml` showing defaults instead.

**Cause:** Docker doesn't expand `~` in volume paths.

**Solution:** Use absolute paths: `/home/lenny/docker/homepage:/app/config`. This same issue later caused a Jellyfin config disaster (Issue 11).

### Issue 7: Scrutiny not detecting NVMe drive

**Symptoms:** API summary empty despite successful smartctl scans.

**Cause:** Scrutiny's auto-detection was scanning with empty device path.

**Solution:** Created explicit `collector.yaml` specifying the device, then ran the collector manually.

### Issue 8: Tailscale MagicDNS not resolving after Pi-hole setup

**Symptoms:** Hostnames like `<server>.ts.net` failing to resolve.

**Cause:** `systemd-resolved` was disabled, which Tailscale relies on for DNS.

**Solution:**

```bash
sudo systemctl enable systemd-resolved --now
sudo rm /etc/resolv.conf
sudo ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo tailscale set --accept-dns=true
```

### Issue 9: HomePod minis "Network Error" after DHCP disruption

**Symptoms:** HomePod minis showing network errors despite being functional.

**Solution:** Resolved after 15–20 minutes as iPhone refreshed HomeKit state. Force-closing the Home app often helps.

### Issue 10: Local IP access through Tailscale not working

**Symptoms:** `http://192.168.1.152:8096` timing out on mobile data via Tailscale.

**Cause:** Subnet route wasn't being accepted by iPhone client.

**Solution:** In the iOS Tailscale app, toggle on "Accept routes" and "Use Tailscale DNS".

### Issue 11: Jellyfin "server mismatch" after container update (the `~` disaster)

**Symptoms:** After container changes, Jellyfin clients showed "server mismatch" and prompted for fresh setup — libraries, users, watch history all gone.

**Cause:** Same issue as Issue 6 but more catastrophic. Original compose had `~/docker/jellyfin/config:/config`. When Docker ran with sudo, `~` resolved to `/root/`, creating a fresh empty config at `/root/docker/jellyfin/config/`. Jellyfin booted with no config and generated a new server ID.

**Solution:** Recover the original config from `/root/docker/jellyfin/` and update compose to use absolute paths. Then:

```bash
docker compose stop jellyfin
sudo cp -a /root/docker/jellyfin/config /home/lenny/docker/jellyfin/config
sudo chown -R lenny:lenny /home/lenny/docker/jellyfin/config
docker compose start jellyfin
```

**Rule:** Never use `~` in docker-compose volumes. Always absolute paths.

### Issue 12: ProtonVPN AUTH_FAILED retry loop

**Symptoms:** Gluetun logs show `AUTH_FAILED` repeatedly, VPN can't connect.

**Cause:** Proton rate-limits authentication after repeated failed attempts (usually from rapid container restarts during testing).

**Solution:**
1. `docker compose stop gluetun` to stop hammering Proton
2. Wait 15–30 minutes for rate limit to clear
3. Regenerate OpenVPN credentials at account.protonvpn.com
4. Update `.env` with new password
5. `docker compose up -d gluetun qbittorrent`

**Rule:** Never restart Gluetun more than once every few minutes.

### Issue 13: qBittorrent settings don't persist after restart

**Symptoms:** Password, port, download paths revert after container restart.

**Cause:** Two `qBittorrent.conf` files existed from migration:
- `/home/lenny/docker/qbittorrent/config/qBittorrent.conf` (stale)
- `/home/lenny/docker/qbittorrent/config/qBittorrent/qBittorrent.conf` (container uses this)

The container read from the nested one but writes went to the outer one.

**Solution:**

```bash
docker compose stop qbittorrent
rm /home/lenny/docker/qbittorrent/config/qBittorrent.conf
rm /home/lenny/docker/qbittorrent/config/qBittorrent-data.conf
sudo chown -R 1000:1000 /home/lenny/docker/qbittorrent
docker compose start qbittorrent
```

Verify password saves:

```bash
grep "Password_PBKDF2" /home/lenny/docker/qbittorrent/config/qBittorrent/qBittorrent.conf
```

Should show a long hash.

### Issue 14: qBittorrent Web UI login just reloads page

**Symptoms:** Correct credentials but page reloads with login form.

**Causes (in order of likelihood):**
1. Stale cookie from earlier failed attempts
2. Cookie Secure flag ON but accessing over HTTP
3. Host header validation ON

**Solutions:**
1. Try incognito window first (confirms cookie issue)
2. Clear site data for `192.168.1.152:8081`
3. Disable Cookie Secure flag and Host header validation in Web UI settings

### Issue 15: qBittorrent Web UI port conflict

**Symptoms:** Logs show `Unable to bind to IP: *, port: XXXXX. Reason: The bound address is already in use`.

**Cause:** Web UI port was accidentally set to the torrent forwarded port. Both trying to bind the same port.

**Solution:**

```bash
docker compose stop qbittorrent
sed -i 's/WebUI\\Port=.*/WebUI\\Port=8081/' /home/lenny/docker/qbittorrent/config/qBittorrent/qBittorrent.conf
docker compose start qbittorrent
```

### Issue 16: Gluetun healthcheck restart loop

**Symptoms:** Logs show `startup check: all check tries failed: lookup github.com: i/o timeout`, Gluetun keeps restarting.

**Cause:** Gluetun's healthcheck tries to reach external domains before DNS is fully initialised.

**Solution:** Add healthcheck with longer start period:

```yaml
healthcheck:
  test: /gluetun-entrypoint healthcheck
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

### Issue 17: qBittorrent loses network after `--force-recreate gluetun`

**Symptoms:** `wget: bad address 'ipinfo.io'` after Gluetun is recreated.

**Cause:** `--force-recreate` gives Gluetun a new container ID. qBittorrent was bound to the old one.

**Solution:** Always recreate both together:

```bash
docker compose up -d --force-recreate gluetun qbittorrent
```

Or use plain `restart` which preserves container IDs:

```bash
docker compose restart gluetun
```

## Network Configuration

- **Router:** BT Smart Hub 2 at `192.168.1.254` (DNS settings locked by BT)
- **Ubuntu Server:** `192.168.1.152` (WiFi: `wlp2s0`)
- **Tailscale IP:** `100.104.31.59`
- **Home Assistant Pi:** `192.168.1.124`
- **Tailscale MagicDNS:** `lenny-lenovo-v15-g3-aba.taildd33e9.ts.net`

## Why Pi-hole was removed

Pi-hole was initially part of the stack but was removed because:

1. BT Smart Hub 2 does not allow DNS changes at the router level
2. Setting Pi-hole as DHCP server caused catastrophic network lockout
3. Alternative (per-device DNS config) was too cumbersome for the entire network

**Future alternative:** Run AdGuard Home on the dedicated Home Assistant Pi, or set up a dedicated Pi-hole device with more careful DHCP handoff planning.

## Firewall Configuration

If UFW is enabled, open the required ports:

```bash
sudo ufw allow 8096   # Jellyfin
sudo ufw allow 8081   # qBittorrent
sudo ufw allow 9000   # Portainer
sudo ufw allow 3000   # Homepage
sudo ufw allow 3001   # Uptime Kuma
sudo ufw allow 8082   # Scrutiny
sudo ufw allow in on tailscale0
sudo ufw reload
```

## Useful Commands

```bash
# Check all containers
docker ps

# View container logs
docker logs <container-name> --tail 50

# Restart a container (preserves container ID)
docker compose restart <container-name>

# Recreate gluetun and qbittorrent together (new container IDs)
docker compose up -d --force-recreate gluetun qbittorrent

# Update all containers
cd ~/docker && docker compose pull && docker compose up -d

# Check VPN status
docker exec qbittorrent wget -qO- https://ipinfo.io/ip
docker exec gluetun cat /tmp/gluetun/forwarded_port

# Check server IP
ip a | grep "inet 192"

# Check Tailscale status
sudo tailscale status
```

## Access URLs

### At home (local network)

- Jellyfin: `http://192.168.1.152:8096`
- qBittorrent: `http://192.168.1.152:8081`
- Portainer: `http://192.168.1.152:9000`
- Homepage: `http://192.168.1.152:3000`
- Uptime Kuma: `http://192.168.1.152:3001`
- Scrutiny: `http://192.168.1.152:8082`
- Home Assistant: `http://192.168.1.124:8123`

### Remote (Tailscale connected)

With subnet routing enabled, the same local IPs work remotely. Alternatively, use the Tailscale IP `100.104.31.59` or MagicDNS hostname.

## Client Recommendations

- **Apple TV:** Official Jellyfin app (free) or Infuse 7 (premium Apple-native experience)
- **Fire Stick:** Sideload Jellyfin Android TV APK from jellyfin.org (the Amazon Store version is outdated)
- **iOS:** Official Jellyfin app or Infuse 7
- **Desktop:** Web interface at `:8096`

## Future Improvements

- [ ] Set up Nginx Proxy Manager with a custom domain for public access without VPN
- [ ] Move Pi-hole/AdGuard Home to dedicated hardware
- [ ] Set up automated backups of Docker volumes (including the 2 TB USB drive)
- [ ] Add hardware-accelerated transcoding for Jellyfin (VAAPI/NVENC)
- [ ] Migrate from WiFi to wired ethernet for server stability
- [ ] Set up a static local IP for the server
- [ ] Implement SSL certificates for all services
- [ ] Automation — move completed torrents from `/downloads` into Jellyfin libraries with Sonarr/Radarr

## Credits & Resources

- [Jellyfin](https://jellyfin.org/)
- [LinuxServer.io](https://www.linuxserver.io/)
- [Portainer](https://www.portainer.io/)
- [Homepage](https://gethomepage.dev/)
- [Uptime Kuma](https://github.com/louislam/uptime-kuma)
- [Scrutiny](https://github.com/AnalogJ/scrutiny)
- [Tailscale](https://tailscale.com/)
- [Gluetun](https://github.com/qdm12/gluetun) — the VPN container doing the heavy lifting
- [ProtonVPN](https://protonvpn.com/)
