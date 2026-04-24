# Tailscale + Pi-hole DNS Integration

Pi-hole DNS is pushed to all Tailscale-connected devices via the Tailscale admin console.
This means ad blocking works on all devices even when away from home.

## Setup

### 1. Prevent Ubuntu using itself as DNS via Tailscale

    sudo tailscale up --accept-dns=false --accept-routes --advertise-routes=192.168.1.0/24

### 2. Tailscale Admin Console

Go to: https://login.tailscale.com/admin/dns

- Add nameserver → Custom → YOUR_TAILSCALE_IP (run: tailscale ip -4)
- Enable Override local DNS
- Enable Use with exit node
- MagicDNS stays enabled — handles tailnet hostnames, Pi-hole handles everything else

## Result

Away from home + Tailscale connected:
- MagicDNS resolves tailnet hostnames
- Pi-hole handles all other DNS queries
- Ad blocking works everywhere

At home:
- Devices use Pi-hole directly via 192.168.1.152
- Ad blocking works

## Network Details

| Name | Value |
|------|-------|
| Ubuntu Tailscale IP | run: tailscale ip -4 |
| MagicDNS hostname | check: tailscale status |
| Pi-hole local IP | 192.168.1.152 |
