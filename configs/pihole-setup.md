# Pi-hole Setup

Pi-hole v6 running in Docker for network-wide ad blocking.

## Key Configuration

Pi-hole v6 ignores the DNSMASQ_LISTENING environment variable.
Listening mode must be set via FTLCONF_dns_listeningMode=all in docker-compose.yml
OR directly in /etc/pihole/pihole.toml inside the container:

    docker exec pihole sed -i 's/listeningMode = "LOCAL"/listeningMode = "ALL"/' /etc/pihole/pihole.toml
    docker compose restart pihole

## Upstream DNS

- Primary: 1.1.1.1 (Cloudflare)
- Secondary: 1.0.0.1 (Cloudflare)

## DHCP

DHCP is disabled - BT Smart Hub 2 handles DHCP.
Never enable Pi-hole DHCP while router DHCP is running - causes network lockout.

## Per-Device DNS Configuration

BT Smart Hub 2 does not expose DNS settings in its UI. Set manually per device:

| Device | DNS 1 | DNS 2 | Notes |
|--------|-------|-------|-------|
| Mac | 192.168.1.152 | — | System Settings → Network → Wi-Fi → DNS |
| iPhone | 192.168.1.152 | 1.1.1.1 | Settings → Wi-Fi → Configure DNS → Manual |
| Huawei EMUI 12 | 192.168.1.152 | 1.1.1.1 | Must set static IP to expose DNS fields |
| Apple TV (tvOS) | 192.168.1.152 | — | Only one DNS entry supported |
| Hisense TV | 192.168.1.152 | 1.1.1.1 | Static IP: 192.168.1.168 |
| Fire TV Cube | 192.168.1.152 | 1.1.1.1 | Forget and reconnect to set static IP |

## iCloud Private Relay

Disable Private Relay on all Apple devices - it bypasses Pi-hole completely.
Pi-hole blocks mask.icloud.com automatically via:
dns.specialDomains.iCloudPrivateRelay = true

This prevents Private Relay re-enabling after OS updates.

## Special Domains Blocked

| Domain | Reason |
|--------|--------|
| mask.icloud.com | iCloud Private Relay |
| use-application-dns.net | Firefox DoH bypass |
| resolver.arpa | Designated resolver bypass |

## Access

- Web UI: http://192.168.1.152:8080/admin
- DNS port: 53
