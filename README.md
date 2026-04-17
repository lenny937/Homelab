# Homelab
# Home Media Server & Homelab — Ubuntu Docker Stack

A self-hosted home media server and homelab built on Ubuntu running Docker Compose. Includes Jellyfin for media streaming, Portainer for container management, Uptime Kuma for monitoring, Scrutiny for drive health, Homepage as a unified dashboard, and Nginx Proxy Manager. Accessed remotely via Tailscale VPN with subnet routing.

## Overview

This project migrates a bare metal Jellyfin server to a Docker Compose stack while adding complementary homelab services. The setup prioritises clean separation of concerns, remote access without port forwarding, and integration with an existing Apple-centric smart home environment (Home Assistant, HomePod, Apple TV, HomeKit).

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
│   ┌────────────┐                            │
│   │ Watchtower │       Tailscale            │
│   └────────────┘       (subnet route)       │
│                                             │
└─────────────────────────────────────────────┘
                      │
                      │
              ┌───────┴────────┐
              │                │
        ┌─────▼────┐    ┌──────▼─────┐
        │ Raspberry│    │  BT Smart  │
        │ Pi (HA)  │    │   Hub 2    │
        └──────────┘    └────────────┘
```

## Stack Components

|Service            |Purpose                 |Port       |
|-------------------|------------------------|-----------|
|Jellyfin           |Media server            |8096       |
|Portainer          |Container GUI management|9000       |
|Homepage           |Unified dashboard       |3000       |
|Uptime Kuma        |Service monitoring      |3001       |
|Scrutiny           |Drive health monitoring |8082       |
|Nginx Proxy Manager|Reverse proxy           |80, 81, 443|
|Watchtower         |Auto-updater            |—          |

## Prerequisites

- Ubuntu 22.04 or later
- Docker and Docker Compose
- Tailscale account (for remote access)
- Existing media library

## Installation

### 1. Install Docker

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Create Directory Structure

```bash
mkdir -p ~/docker/{jellyfin/config,pihole/etc-pihole,pihole/etc-dnsmasq.d,nginx/data,nginx/letsencrypt,homepage,uptime-kuma,scrutiny}
cd ~/docker
```

### 3. Backup Existing Jellyfin (if migrating from bare metal)

```bash
mkdir -p ~/jellyfin-backup/config ~/jellyfin-backup/data
sudo cp -r /etc/jellyfin ~/jellyfin-backup/config
sudo cp -r /var/lib/jellyfin ~/jellyfin-backup/data

sudo systemctl stop jellyfin
sudo systemctl disable jellyfin
```

### 4. Docker Compose Configuration

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
      - /media:/media:ro

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
      - /home/lenny/docker/homepage:/app/config
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

volumes:
  portainer_data:
```

### 5. Launch the Stack

```bash
cd ~/docker
sudo docker compose up -d
```

## Post-Installation Configuration

### Jellyfin Setup

1. Navigate to `http://<server-ip>:8096`
1. Run through the setup wizard
1. Add libraries pointing to `/media/<folder>` (e.g., `/media/shows`)
1. Add plugin repository: **Dashboard → Plugins → Repositories**
- URL: `https://repo.jellyfin.org/files/plugin/manifest.json`
1. Install useful plugins:
- Intro Skipper (auto-skip intros)
- Jellyscrub (thumbnail previews)
- Open Subtitles (auto-download subtitles)
- Playback Reporting (watch stats)

### Open Subtitles Configuration

1. Create a free account at `https://www.opensubtitles.com`
1. In Jellyfin: **Dashboard → Plugins → Open Subtitles**
1. Enter credentials and save
1. Per-library config: **Dashboard → Libraries → [Library] → Manage Library → Subtitle Downloads**
1. Enable Open Subtitles provider and select language

### Homepage Configuration

Create `~/docker/homepage/services.yaml`:

```yaml
- Media:
    - Jellyfin:
        href: http://192.168.1.152:8096
        description: Media Server
        icon: jellyfin.png

- Management:
    - Portainer:
        href: http://192.168.1.152:9000
        description: Container Management
        icon: portainer.png
    - Uptime Kuma:
        href: http://192.168.1.152:3001
        description: Service Monitoring
        icon: uptime-kuma.png

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

### Scrutiny Drive Configuration

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

### Uptime Kuma Setup

1. Navigate to `http://<server-ip>:3001`
1. Create admin account
1. Add HTTP(s) monitors for each service:
- Jellyfin: `http://192.168.1.152:8096`
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

### Enable Subnet Routing

This allows remote devices to access the local network as if physically present:

```bash
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes
```

Then approve the subnet route in the Tailscale admin console:

- Go to `https://login.tailscale.com/admin/machines`
- Click your server → three dots → Edit route settings
- Approve `192.168.1.0/24`

### iPhone Configuration

In the Tailscale iOS app:

- Enable “Use Tailscale DNS”
- Enable “Accept routes”
- No Exit Node selected

With this setup, local IPs (e.g., `http://192.168.1.152:8096`) work from anywhere when Tailscale is connected.

## Problems Encountered & Solutions

### Issue 1: Jellyfin crash loop on first launch

**Symptoms:** Container restarting with exit code 139, error about `.jellyfin-config` marker.

**Cause:** The official `jellyfin/jellyfin` image expects a specific directory structure incompatible with migrated bare metal paths.

**Solution:** Switched to `lscr.io/linuxserver/jellyfin:latest` which handles migrated configs cleanly. Used a fresh config directory and re-added libraries.

### Issue 2: Pi-hole port 53 conflict with systemd-resolved

**Symptoms:** Pi-hole fails to bind port 53.

**Cause:** Ubuntu’s `systemd-resolved` holds port 53 by default.

**Solution:** Disable the stub listener in `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNSStubListener=no
```

Then restart: `sudo systemctl restart systemd-resolved`

### Issue 3: Network lockout after disabling BT Hub DHCP

**Symptoms:** Disabled DHCP on BT Hub intending to use Pi-hole’s DHCP, then removed Pi-hole — all devices lost network connectivity.

**Cause:** No DHCP server on network. Pi-hole was the only provider.

**Solution:**

1. Access router from phone (still had cached IP)
1. Re-enable DHCP on BT Hub
1. Reboot router to restore default network state

**Lesson:** Don’t disable BT Hub DHCP without a fully working alternative in place. For future Pi-hole deployment, configure devices manually to use Pi-hole DNS rather than taking over DHCP.

### Issue 4: Watchtower API version error

**Symptoms:** Logs showed `client version 1.25 is too old. Minimum supported API version is 1.40`.

**Solution:** Added environment variable to compose file:

```yaml
environment:
  - DOCKER_API_VERSION=1.40
```

### Issue 5: Homepage “Host validation failed”

**Symptoms:** 500 Internal Error when accessing Homepage by IP.

**Solution:** Set the `HOMEPAGE_ALLOWED_HOSTS` environment variable in the compose file with comma-separated allowed addresses.

### Issue 6: Homepage config not loading

**Symptoms:** Custom `services.yaml` showing defaults instead.

**Cause:** Docker doesn’t expand `~` in volume paths.

**Solution:** Use absolute paths: `/home/lenny/docker/homepage:/app/config`

### Issue 7: Scrutiny not detecting NVMe drive

**Symptoms:** API summary empty despite successful smartctl scans.

**Cause:** Scrutiny’s auto-detection was scanning with empty device path.

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

### Issue 9: HomePod minis “Network Error” after DHCP disruption

**Symptoms:** HomePod minis showing network errors in Home app despite being functional.

**Cause:** Network disruption during Pi-hole experiment left them in a confused state.

**Solution:** Worked themselves out after 15-20 minutes as iPhone refreshed HomeKit state. Force-closing the Home app often helps.

### Issue 10: Local IP access through Tailscale not working

**Symptoms:** `http://192.168.1.152:8096` timing out when on mobile data via Tailscale.

**Cause:** Subnet route wasn’t being accepted by iPhone client.

**Solution:** In the iOS Tailscale app, toggle on “Accept routes” and “Use Tailscale DNS”.

## Network Configuration

- **Router:** BT Smart Hub 2 at `192.168.1.254` (DNS settings locked by BT, cannot be changed)
- **Ubuntu Server:** `192.168.1.152` (WiFi: `wlp2s0`)
- **Tailscale IP:** `100.104.31.59`
- **Home Assistant Pi:** `192.168.1.124`
- **Tailscale MagicDNS:** `lenny-lenovo-v15-g3-aba.taildd33e9.ts.net`

## Why Pi-hole Was Removed

Pi-hole was initially part of the stack but was removed because:

1. BT Smart Hub 2 does not allow DNS changes at the router level
1. Setting Pi-hole as DHCP server caused catastrophic network lockout
1. Alternative (per-device DNS config) was too cumbersome for the entire network

**Future alternative:** Run AdGuard Home on the dedicated Home Assistant Pi, or set up a dedicated Pi-hole device with more careful DHCP handoff planning.

## Firewall Configuration

If UFW is enabled, open the required ports:

```bash
sudo ufw allow 8096   # Jellyfin
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
sudo docker ps

# View container logs
sudo docker logs <container-name> --tail 50

# Restart a container
sudo docker restart <container-name>

# Update all containers
cd ~/docker && sudo docker compose pull && sudo docker compose up -d

# Check server IP
ip a | grep "inet 192"

# Check Tailscale status
sudo tailscale status
```

## Access URLs

### At Home (local network)

- Jellyfin: `http://192.168.1.152:8096`
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
- [ ] Set up automated backups of Docker volumes
- [ ] Add hardware-accelerated transcoding for Jellyfin (VAAPI/NVENC)
- [ ] Migrate from WiFi to wired ethernet for server stability
- [ ] Set up a static local IP for the server
- [ ] Implement SSL certificates for all services

## Credits & Resources

- [Jellyfin](https://jellyfin.org/)
- [LinuxServer.io](https://www.linuxserver.io/)
- [Portainer](https://www.portainer.io/)
- [Homepage](https://gethomepage.dev/)
- [Uptime Kuma](https://github.com/louislam/uptime-kuma)
- [Scrutiny](https://github.com/AnalogJ/scrutiny)
- [Tailscale](https://tailscale.com/)
