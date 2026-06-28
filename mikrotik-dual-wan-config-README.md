# mikrotik-dual-wan-config

Production dual WAN configuration for MikroTik RB750Gr3 running RouterOS 7.23.1. PCC load balancing with automatic failover, persistent SD card logging, and DHCP gateway auto-renewal for dynamic ISPs.

## What's in this repo

| File | Description |
|------|-------------|
| `mikrotik-rb750gr3-config-guide.md` | Step-by-step deployment guide with explanations |
| `rb750gr3-final.rsc` | RouterOS export from the production router |

Router backups are excluded via `.gitignore`.

## Network

- **WAN1** — ether1, SSWL, static IP
- **WAN2** — ether2, JIO, DHCP
- **LAN** — bridge-lan (ether3 + ether4 + ether5), `192.168.10.0/24`

## Key features

- PCC load balancing across two ISPs
- Netwatch failover pinging gateway IPs (not public IPs)
- DHCP script on WAN2 to auto-update stale gateway on lease renewal
- FastTrack disabled so mangle rules apply to all connections
- `dst-address-type=!local` on PCC rules (RouterOS 7 requirement)
- Explicit routing tables with `fib` flag (RouterOS 7 requirement)
- SD card persistent logging with dedicated WAN failover log

## Using the RSC file

> **Adapt before importing.** IP addresses are specific to my ISPs and LAN. At minimum, update WAN1 static IP, WAN2 gateway, and LAN subnet to match your network.

```bash
# Copy rb750gr3-final.rsc to the router via Winbox Files, then:
/import file=rb750gr3-final.rsc
```

Start from a clean router (`/system reset-configuration no-defaults=yes`) to avoid rule conflicts.

## Full guide

[MikroTik Dual WAN RouterOS 7 – Production Setup Guide](https://www.techbreeze.in/mikrotik-dual-wan-routeros-7)

## Hardware

MikroTik RB750Gr3 · RouterOS 7.23.1 · 32GB microSD
