# MikroTik RB750Gr3 — Dual-WAN Configuration Guide
### RouterOS 7.x (verified against official MikroTik v7 documentation)

## Network Summary

| Role | Interface | Mode | Details |
|------|-----------|------|---------|
| WAN1 | ether1 | Static | IP: `172.28.62.195/24` · GW: `172.28.62.1` (SSWL ISP) |
| WAN2 | ether2 | DHCP | IP: `192.168.29.148/24` · GW: `192.168.29.1` (JIO ISP) |
| LAN  | bridge-lan (ether3+4+5) | Bridge | `192.168.10.1/24` |
| AP | ether3 | Bridge port | ArcherC64 Access Point |
| Switch | ether4 | Bridge port | TP-Link tl-sg105e |
| Spare | ether5 | Bridge port | Available for future use |

> **Convention:** Every command block in this guide is meant to be pasted into the
> RouterOS terminal (SSH or Winbox Terminal). Lines beginning with `#` are comments
> and are safe to include — RouterOS ignores them.
>
> **v7 note:** `routing-mark=` (used in RouterOS v6) is replaced by `routing-table=`
> in v7. Routing tables must also be explicitly created before use.

---

## Step 1 — Factory Reset

Start from a clean slate to avoid conflicts with any existing configuration.

Connect to the router via Winbox or serial. Then:

```routeros
/system reset-configuration no-defaults=yes skip-backup=yes
```

The router will reboot. Reconnect after ~30 seconds.

> `no-defaults=yes` prevents RouterOS from loading its built-in Quick Set template —
> we want a completely blank canvas.

---

## Step 2 — Add Interface Comments

```routeros
/interface set ether1 comment="WAN1-SSWL-Static"
/interface set ether2 comment="WAN2-JIO-DHCP"
/interface set ether3 comment="AP-ArcherC64"
/interface set ether4 comment="Switch-tl-sg105e"
/interface set ether5 comment="Spare"
```

Verify:

```routeros
/interface print
```

---

## Step 3 — Assign WAN1 Static IP

```routeros
/ip address add \
    address=172.28.62.195/24 \
    interface=ether1 \
    comment="WAN1"
```

---

## Step 4 — Configure WAN2 DHCP Client

Add a DHCP client on ether2. Set `add-default-route=no` and `use-peer-dns=no`
because we will manage routes and DNS manually.

```routeros
/ip dhcp-client add \
    interface=ether2 \
    add-default-route=no \
    use-peer-dns=no \
    disabled=no \
    comment="WAN2 DHCP"
```

Wait a few seconds, then check:

```routeros
/ip dhcp-client print detail
```

Look for `status: bound` and note the `gateway` value — you will need it in
Steps 11 and 12.

> WAN2 values are already filled in throughout this guide:
> Gateway: `192.168.29.1` · Subnet: `192.168.29.0/24`

---

## Step 5 — Create LAN Bridge and Assign IP

Bridge ether3, ether4, and ether5 into a single LAN so the AP, switch, and spare port all share the same network.

```routeros
# Create bridge
/interface bridge add name=bridge-lan comment="LAN Bridge"

# Add ports
/interface bridge port add interface=ether3 bridge=bridge-lan
/interface bridge port add interface=ether4 bridge=bridge-lan
/interface bridge port add interface=ether5 bridge=bridge-lan

# Assign LAN IP to bridge
/ip address add \
    address=192.168.10.1/24 \
    interface=bridge-lan \
    comment="LAN"
```

> **Critical — bridge and firewall/mangle rules:** Once a physical interface
> becomes a bridge port (slave), **any existing firewall or mangle rule that
> references it by name becomes INVALID** and is silently skipped. RouterOS
> will show `in/out-interface matcher not possible when interface (etherX) is
> slave — use master instead (bridge-lan)`.
>
> After creating the bridge, all `in-interface=ether3` references in mangle
> and filter rules **must** be changed to `in-interface=bridge-lan`. If rules
> were added before the bridge, fix them with:
> ```routeros
> /ip firewall mangle set 0 in-interface=bridge-lan
> /ip firewall mangle set 1 in-interface=bridge-lan
> # (repeat for each affected rule number)
> ```
> Then **reboot the router** — invalid mangle rules can cause LAN→router and
> LAN→internet to silently fail even after the rules are fixed.

---

## Step 6 — Configure DNS

```routeros
/ip dns set \
    servers=8.8.8.8,1.1.1.1 \
    allow-remote-requests=yes \
    cache-max-ttl=1d
```

`allow-remote-requests=yes` lets LAN clients use the router (`192.168.10.1`) as their DNS server.

---

## Step 7 — DHCP Server for LAN

### Address Pool

```routeros
/ip pool add \
    name=lan-pool \
    ranges=192.168.10.100-192.168.10.200
```

Addresses below `.100` are reserved for static assignments (servers, APs, etc.).

### DHCP Server

```routeros
/ip dhcp-server add \
    name=lan-dhcp \
    interface=bridge-lan \
    address-pool=lan-pool \
    lease-time=12h \
    disabled=no
```

### DHCP Network Options

```routeros
/ip dhcp-server network add \
    address=192.168.10.0/24 \
    gateway=192.168.10.1 \
    dns-server=192.168.10.1 \
    comment="LAN"
```

---

## Step 8 — Firewall

> **Rule order matters.** Rules are evaluated top to bottom and stop at the
> first match. The order below is intentional — do not rearrange.

```routeros
/ip firewall filter

# --- INPUT chain ---

add chain=input \
    connection-state=established,related,untracked \
    action=accept \
    comment="Accept established/related/untracked"

add chain=input \
    connection-state=invalid \
    action=drop \
    comment="Drop invalid"

add chain=input \
    in-interface=bridge-lan \
    action=accept \
    comment="Accept from LAN"

add chain=input \
    in-interface=lo \
    action=accept \
    comment="Accept loopback"

# ISP portal exception — must be before RFC1918 drops
# because 10.254.254.8 is in the 10.0.0.0/8 range
add chain=input \
    src-address=10.254.254.8/32 \
    in-interface=ether1 \
    action=accept \
    comment="Allow WAN1 ISP portal"

# Drop RFC1918 source addresses arriving on WAN interfaces
# (spoofed or misconfigured packets that should never come from internet)
add chain=input src-address=10.0.0.0/8     in-interface=ether1 action=drop comment="Drop RFC1918 src on WAN1"
add chain=input src-address=172.16.0.0/12  in-interface=ether1 action=drop comment="Drop RFC1918 src on WAN1"
add chain=input src-address=192.168.0.0/16 in-interface=ether1 action=drop comment="Drop RFC1918 src on WAN1"
add chain=input src-address=10.0.0.0/8     in-interface=ether2 action=drop comment="Drop RFC1918 src on WAN2"
add chain=input src-address=172.16.0.0/12  in-interface=ether2 action=drop comment="Drop RFC1918 src on WAN2"
add chain=input src-address=192.168.0.0/16 in-interface=ether2 action=drop comment="Drop RFC1918 src on WAN2"

# ICMP rate limiting — prevents ICMP flood
add chain=input protocol=icmp limit=10,20:packet action=accept comment="Allow ICMP rate limited"
add chain=input protocol=icmp action=drop comment="Drop excess ICMP"

add chain=input \
    action=drop \
    comment="Drop all other input"


# --- FORWARD chain ---

add chain=forward \
    connection-state=established,related,untracked \
    action=accept \
    comment="Accept established/related/untracked"

add chain=forward \
    connection-state=invalid \
    action=drop \
    comment="Drop invalid"

add chain=forward \
    in-interface=bridge-lan \
    out-interface=ether1 \
    action=accept \
    comment="LAN to WAN1"

add chain=forward \
    in-interface=bridge-lan \
    out-interface=ether2 \
    action=accept \
    comment="LAN to WAN2"

# ISP portal exception for forwarded traffic
add chain=forward \
    src-address=10.254.254.8/32 \
    in-interface=ether1 \
    action=accept \
    comment="Allow WAN1 ISP portal"

# Drop RFC1918 source addresses on WAN interfaces (forward chain)
add chain=forward src-address=10.0.0.0/8     in-interface=ether1 action=drop comment="Drop RFC1918 src on WAN1"
add chain=forward src-address=172.16.0.0/12  in-interface=ether1 action=drop comment="Drop RFC1918 src on WAN1"
add chain=forward src-address=192.168.0.0/16 in-interface=ether1 action=drop comment="Drop RFC1918 src on WAN1"
add chain=forward src-address=10.0.0.0/8     in-interface=ether2 action=drop comment="Drop RFC1918 src on WAN2"
add chain=forward src-address=172.16.0.0/12  in-interface=ether2 action=drop comment="Drop RFC1918 src on WAN2"
add chain=forward src-address=192.168.0.0/16 in-interface=ether2 action=drop comment="Drop RFC1918 src on WAN2"

add chain=forward \
    action=drop \
    comment="Drop all other forward"
```

---

## Step 9 — NAT

```routeros
/ip firewall nat

add chain=srcnat \
    out-interface=ether1 \
    action=masquerade \
    comment="NAT WAN1"

add chain=srcnat \
    out-interface=ether2 \
    action=masquerade \
    comment="NAT WAN2"
```

> **NAT only needs two rules.** Policy-routing bypass rules (preventing PCC
> from marking packets bound for ISP subnets) belong in the **mangle**
> prerouting chain (Step 11) — not here. `action=accept` in NAT prerouting
> skips DNAT processing, which has no effect on routing decisions and would be
> a no-op since there are no DNAT rules in this setup.

---

## Step 10 — Create Routing Tables (v7 requirement)

In RouterOS 7, routing tables **must be explicitly created** before being
referenced in routes or mangle rules. This replaces the v6 behaviour where
tables were created implicitly by `routing-mark=`.

The `fib` flag pushes routes from this table into the Forwarding Information
Base so the router can actually forward packets using them.

```routeros
/routing table add name=WAN1 fib disabled=no
/routing table add name=WAN2 fib disabled=no
```

Verify:

```routeros
/routing table print
```

You should see `WAN1` and `WAN2` listed alongside the built-in `main` table.

---

## Step 11 — Load Balancing (Mangle / PCC)

Per Connection Classifier (PCC) splits new connections evenly across both WANs.
Once a connection is assigned to a WAN, all its packets follow the same path.

### How it works

1. A new connection from the LAN arrives.
2. PCC hashes the source+destination address pair, assigns it to bucket 0
   (WAN1) or bucket 1 (WAN2) — roughly 50/50.
3. A connection mark (`WAN1-conn` or `WAN2-conn`) is applied.
4. A routing mark (`WAN1` or `WAN2`) directs it to the correct routing table.
5. For subsequent packets of the same connection, the existing connection mark
   is read and the routing mark reapplied — no re-hashing.

### Important v7 caveat

`action=mark-routing` in the `prerouting` chain captures **all** traffic
entering the router, including traffic destined for the router itself. Without
`dst-address-type=!local`, the router would mark and misroute its own replies,
breaking LAN access to the router. This filter is mandatory in RouterOS v7.

```routeros
/ip firewall mangle

# ---------------------------------------------------------------
# PREROUTING — bypass policy routing for directly-connected ISP
# subnets and special destinations to prevent routing loops.
# ---------------------------------------------------------------

# Bypass for WAN1 ISP portal (must be via WAN1 only)
add chain=prerouting \
    in-interface=bridge-lan \
    dst-address=10.254.254.8/32 \
    action=accept \
    comment="Bypass PCC: WAN1 ISP portal (prerouting)"

add chain=prerouting \
    in-interface=bridge-lan \
    dst-address=172.28.62.0/24 \
    action=accept \
    comment="Bypass policy routing: WAN1 subnet"

add chain=prerouting \
    in-interface=bridge-lan \
    dst-address=192.168.29.0/24 \
    action=accept \
    comment="Bypass policy routing: WAN2 subnet"


# ---------------------------------------------------------------
# INPUT — mark new connections arriving from each WAN.
# This ensures replies leave via the same interface they came in on.
# ---------------------------------------------------------------
add chain=input \
    connection-state=new \
    in-interface=ether1 \
    action=mark-connection \
    new-connection-mark=WAN1-conn \
    passthrough=yes \
    comment="Mark new inbound WAN1 connections"

add chain=input \
    connection-state=new \
    in-interface=ether2 \
    action=mark-connection \
    new-connection-mark=WAN2-conn \
    passthrough=yes \
    comment="Mark new inbound WAN2 connections"


# ---------------------------------------------------------------
# OUTPUT — bypass PCC for WAN subnets and ISP portal so the
# router's own pings (Netwatch) exit via the correct interface.
# These MUST come before the PCC output rules below.
# ---------------------------------------------------------------
add chain=output \
    dst-address=10.254.254.8/32 \
    action=accept \
    comment="Bypass PCC: WAN1 ISP portal"

add chain=output \
    dst-address=172.28.62.0/24 \
    action=accept \
    comment="Bypass PCC: WAN1 subnet (output)"

add chain=output \
    dst-address=192.168.29.0/24 \
    action=accept \
    comment="Bypass PCC: WAN2 subnet (output)"


# ---------------------------------------------------------------
# OUTPUT — PCC for the router's own outbound connections.
# connection-mark=no-mark ensures only unmarked new connections
# are classified; established connections already carry a mark.
# ---------------------------------------------------------------
add chain=output \
    connection-mark=no-mark \
    connection-state=new \
    per-connection-classifier=both-addresses:2/0 \
    action=mark-connection \
    new-connection-mark=WAN1-conn \
    passthrough=yes \
    comment="WAN1-pcc router output"

add chain=output \
    connection-mark=no-mark \
    connection-state=new \
    per-connection-classifier=both-addresses:2/1 \
    action=mark-connection \
    new-connection-mark=WAN2-conn \
    passthrough=yes \
    comment="WAN2-pcc router output"


# ---------------------------------------------------------------
# PREROUTING — PCC for LAN outbound connections.
# connection-state=new: only classify new connections.
# connection-mark=no-mark: skip connections already marked above.
# dst-address-type=!local: CRITICAL — prevents marking traffic
# destined for the router itself, which would break LAN→router
# connectivity (DNS, DHCP, Winbox, SSH).
# ---------------------------------------------------------------
add chain=prerouting \
    connection-mark=no-mark \
    connection-state=new \
    dst-address-type=!local \
    in-interface=bridge-lan \
    per-connection-classifier=both-addresses:2/0 \
    action=mark-connection \
    new-connection-mark=WAN1-conn \
    passthrough=yes \
    comment="WAN1-pcc LAN"

add chain=prerouting \
    connection-mark=no-mark \
    connection-state=new \
    dst-address-type=!local \
    in-interface=bridge-lan \
    per-connection-classifier=both-addresses:2/1 \
    action=mark-connection \
    new-connection-mark=WAN2-conn \
    passthrough=yes \
    comment="WAN2-pcc LAN"


# ---------------------------------------------------------------
# Apply routing marks based on connection marks.
# This tells the routing engine which table to look up.
# ---------------------------------------------------------------
add chain=output \
    connection-mark=WAN1-conn \
    action=mark-routing \
    new-routing-mark=WAN1 \
    passthrough=yes \
    comment="Route WAN1-conn via WAN1 table (output)"

add chain=prerouting \
    connection-mark=WAN1-conn \
    in-interface=bridge-lan \
    action=mark-routing \
    new-routing-mark=WAN1 \
    passthrough=yes \
    comment="Route WAN1-conn via WAN1 table (prerouting)"

add chain=output \
    connection-mark=WAN2-conn \
    action=mark-routing \
    new-routing-mark=WAN2 \
    passthrough=yes \
    comment="Route WAN2-conn via WAN2 table (output)"

add chain=prerouting \
    connection-mark=WAN2-conn \
    in-interface=bridge-lan \
    action=mark-routing \
    new-routing-mark=WAN2 \
    passthrough=yes \
    comment="Route WAN2-conn via WAN2 table (prerouting)"
```

Verify:

```routeros
/ip firewall mangle print
```

---

## Step 12 — Routing

We create three sets of routes:

| Set | Purpose |
|-----|---------|
| **Per-WAN routing tables** | Used by mangle-marked connections to exit a specific WAN |
| **Main table default routes** | Fallback for unmatched traffic; WAN1 preferred |
| **Health-check host routes** | Force Netwatch pings through a specific WAN interface |

> Replace `192.168.29.1` with the gateway IP from Step 4.

### Per-WAN Routing Tables

In RouterOS 7 these use `routing-table=` (not `routing-mark=` as in v6).

```routeros
/ip route

add dst-address=0.0.0.0/0 \
    gateway=172.28.62.1 \
    routing-table=WAN1 \
    distance=1 \
    comment="WAN1 table default"

add dst-address=0.0.0.0/0 \
    gateway=192.168.29.1 \
    routing-table=WAN2 \
    distance=1 \
    comment="WAN2 table default"
```

### Main Table Default Routes

These handle traffic that carries no routing mark (e.g. the router's own DNS
queries if both output PCC marks somehow miss) and act as the final safety net
during failover.

```routeros
add dst-address=0.0.0.0/0 \
    gateway=172.28.62.1 \
    distance=1 \
    comment="WAN1-main"

add dst-address=0.0.0.0/0 \
    gateway=192.168.29.1 \
    distance=2 \
    comment="WAN2-main"
```

### Health-Check Host Routes

These /32 host routes pin Netwatch pings to a specific physical WAN interface,
regardless of the main routing table state. This is what makes health checks
test actual internet reachability, not just gateway reachability.

```routeros
add dst-address=8.8.8.8/32 \
    gateway=172.28.62.1 \
    comment="WAN1 health check route"

add dst-address=10.254.254.8/32 \
    gateway=172.28.62.1 \
    comment="WAN1 ISP portal"

add dst-address=1.1.1.1/32 \
    gateway=192.168.29.1 \
    comment="WAN2 health check route"
```

Verify all routes:

```routeros
/ip route print
```

Expected: 6 routes (2 per-WAN table, 2 main, 2 health-check) plus the
automatically added connected routes for each IP address.

---

## Step 13 — Health Checks and Automatic Failover (Netwatch)

Netwatch pings a target IP every 10 seconds. After 3 consecutive failures the
`down` script runs; when pings succeed again the `up` script runs.

We monitor the **WAN gateway IPs** directly (not public IPs like 8.8.8.8).
This is the most reliable approach because:
- When the physical link goes down, the gateway becomes immediately unreachable
  and Netwatch triggers DOWN correctly.
- When the gateway itself fails, Netwatch also triggers DOWN.

> **Why not ping 8.8.8.8/1.1.1.1?** When a WAN's physical link drops, the
> /32 host route for that public IP becomes inactive. Netwatch then falls
> through to the other WAN's default route, gets a reply through the *working*
> WAN, and incorrectly reports the failed WAN as "up". Gateway IPs don't have
> this problem — they are only reachable via their own physical interface.

### What the scripts do

**WAN goes down:**
- Disable the routing-table route for that WAN (mangle-marked connections stop
  using it and fall back to the main table).
- Disable the PCC mangle rules for that WAN (no new connections get assigned
  to the failed WAN).
- Promote the surviving WAN in the main table to `distance=1`.

**WAN recovers:**
- Re-enable the routing-table route.
- Re-enable the PCC mangle rules.
- Restore the correct distances in the main table.

### WAN1 Netwatch Entry

```routeros
/tool netwatch add \
    host=172.28.62.1 \
    interval=10s \
    timeout=3s \
    up-script={
        /log info "WAN1 UP - restoring routes and mangle rules"
        /ip route enable [find comment="WAN1 table default"]
        /ip route set [find comment="WAN1-main"] distance=1
        /ip route set [find comment="WAN2-main"] distance=2
        /ip firewall mangle enable [find comment~"WAN1-pcc"]
    } \
    down-script={
        /log info "WAN1 DOWN - disabling routes and mangle rules"
        /ip route disable [find comment="WAN1 table default"]
        /ip route set [find comment="WAN1-main"] distance=10
        /ip route set [find comment="WAN2-main"] distance=1
        /ip firewall mangle disable [find comment~"WAN1-pcc"]
    } \
    comment="WAN1 health check"
```

### WAN2 Netwatch Entry

```routeros
/tool netwatch add \
    host=192.168.29.1 \
    interval=10s \
    timeout=3s \
    up-script={
        /log info "WAN2 UP - restoring routes and mangle rules"
        /ip route enable [find comment="WAN2 table default"]
        /ip route set [find comment="WAN2-main"] distance=2
        /ip firewall mangle enable [find comment~"WAN2-pcc"]
    } \
    down-script={
        /log info "WAN2 DOWN - disabling routes and mangle rules"
        /ip route disable [find comment="WAN2 table default"]
        /ip route set [find comment="WAN2-main"] distance=10
        /ip firewall mangle disable [find comment~"WAN2-pcc"]
    } \
    comment="WAN2 health check"
```

Verify:

```routeros
/tool netwatch print
```

---

## Step 14 — Handle WAN2 DHCP Gateway Changes

If the ISP renews WAN2 with a different gateway IP, the routes from Step 12
become stale. This DHCP client script updates them automatically on every
lease renewal.

```routeros
/ip dhcp-client set [find interface=ether2] \
    script={
        :local gw $"gateway-address"
        :if ($gw != "") do={
            /ip route set [find comment="WAN2 table default"] gateway=$gw
            /ip route set [find comment="WAN2-main"] gateway=$gw
            /ip route set [find comment="WAN2 health check route"] gateway=$gw
            /log info ("WAN2 DHCP: gateway updated to " . $gw)
        }
    }
```

---

## Step 15 — Verification

Work through each check in order. Fix any failures before moving on.

### Interfaces and IPs

```routeros
/ip address print
```

Expected: `172.28.62.195/24` on ether1, an ISP-assigned address on ether2,
`192.168.10.1/24` on bridge-lan.

### Routing tables exist

```routeros
/routing table print
```

Expected: `WAN1` and `WAN2` with `fib` flag, plus `main`.

### WAN gateway pings

```routeros
/ping 172.28.62.1 count=4
/ping 192.168.29.1 count=4
```

Both should return 4 replies.

### Internet via WAN1 (pinned by /32 host route)

```routeros
/ping 8.8.8.8 count=4
```

Expected: 4 replies, exiting via WAN1.

### Internet via WAN2 (pinned by /32 host route)

```routeros
/ping 1.1.1.1 count=4
```

Expected: 4 replies, exiting via WAN2.

### DNS resolution

```routeros
/ip dns cache flush
/resolve google.com
```

Expected: an IP address resolved via `192.168.10.1`.

### DHCP server

Connect a LAN client. On the router:

```routeros
/ip dhcp-server lease print
```

Expected: leases in the `192.168.10.100–200` range for dynamic clients, and `bound` status for statically assigned devices.

### Netwatch status

```routeros
/tool netwatch print
```

Expected: both entries show `status: up`.

### Load balancing

Open two sessions from two different LAN clients and visit
`https://api.ipify.org`. With healthy PCC distribution the two sessions will
show different public IPs, confirming each went through a different WAN.

> With a small number of clients, both sessions may occasionally hit the same
> WAN. PCC distributes by connection hash, so distribution evens out over many
> connections.

### Failover test — unplug WAN1

1. Disconnect the WAN1 cable (or `/interface disable ether1`).
2. Wait ~30 seconds for three missed Netwatch intervals.
3. Check: `/log print` — you should see `WAN1 DOWN`.
4. Ping from a LAN client — connectivity should be maintained through WAN2.
5. Reconnect WAN1. After the next successful Netwatch interval you should see
   `WAN1 UP` and load balancing resumes.

Repeat for WAN2.

---

## Step 16 — SD Card Logging (Optional)

A 32GB microSD card is installed at `sd1-part1`. RouterOS automatically mounts
it as NTFS. To write system logs to the SD card persistently across reboots:

```routeros
/system logging action set disk disk-file-name=sd1-part1/syslog
/system logging add action=disk topics=info
```

This is useful for diagnosing issues after the fact — the in-memory log clears
on reboot, but the SD card log persists.

### WAN Failover Logging

To capture WAN UP/DOWN events (triggered by the Netwatch failover scripts) to a
dedicated log file on the SD card:

```routeros
/system logging action add name=wanlog target=disk disk-file-name=sd1-part1/wan-failover
/system logging add action=wanlog topics=script comment="WAN failover events to SD"
```

> **Important:** The action name must not contain hyphens. `wanlog` works;
> `wan-log` will fail with "action name can contain only letters and numbers".

After this, every time Netwatch triggers a failover script you will see timestamped
entries in `sd1-part1/wan-failover.0.txt` (RouterOS adds the `.0.txt` suffix).
View live log: `log print where topics~"script"`

---

## Step 17 — Backup

Save backups to both the SD card and download them off the router.

```routeros
# Text export — human-readable, can be used to restore manually
/export file=sd1-part1/rb750gr3-final

# Binary backup — includes passwords, restores with one click in Winbox
/system backup save name=sd1-part1/rb750gr3-final
```

Download both files via **Winbox → Files → sd1-part1** → select file → Download.
Store copies off the router (PC, NAS, or cloud).

> To restore from binary backup: Winbox → Files → Upload the `.backup` file →
> System → Backup → Restore.

---

## Reference: Configuration Map

```
ether1 (WAN1 — SSWL, Static)
    IP:             172.28.62.195/24
    GW:             172.28.62.1
    Routing table:  WAN1  (/routing table fib)
    Route:          0.0.0.0/0 via 172.28.62.1 [routing-table=WAN1]
                    0.0.0.0/0 via 172.28.62.1 [main, distance=1]
    NAT:            srcnat masquerade out-interface=ether1
    Health check:   ping 172.28.62.1 (WAN1 gateway) every 10s

ether2 (WAN2 — JIO, DHCP)
    IP:             192.168.29.148/24 (assigned by ISP)
    GW:             192.168.29.1
    Routing table:  WAN2  (/routing table fib)
    Route:          0.0.0.0/0 via 192.168.29.1 [routing-table=WAN2]
                    0.0.0.0/0 via 192.168.29.1 [main, distance=2]
    NAT:            srcnat masquerade out-interface=ether2
    Health check:   ping 192.168.29.1 (WAN2 gateway) every 10s

bridge-lan (LAN Bridge — ether3 + ether4 + ether5)
    ether3:         AP-ArcherC64
    ether4:         Switch-tl-sg105e
    ether5:         Spare
    IP:             192.168.10.1/24
    DHCP pool:      192.168.10.100–200
    DNS:            192.168.10.1 → 8.8.8.8, 1.1.1.1

Static DHCP leases:
    192.168.10.2    98:AF:65:8B:D4:D1   NVR (argus)
    192.168.10.3    A8:29:48:58:3E:7B   Switch (tl-sg105e)
    192.168.10.4    10:5A:95:D3:40:73   RE505X Range Extender
    192.168.10.5    7C:F1:7E:A9:9C:DF   ArcherC64 Access Point
    192.168.10.20   20:BB:BC:8F:5E:6F   Camera - Bedroom
    192.168.10.21   20:BB:BC:60:E6:99   Camera - Guestroom
    192.168.10.22   A0:FF:0C:A3:AF:A5   Camera - Hall Room

Special routes:
    10.254.254.8/32 via 172.28.62.1     WAN1 ISP portal (always via WAN1)

Load balancing:
    Method:         PCC (both-addresses, 2 buckets)
    New LAN conns:  prerouting, connection-mark=no-mark, connection-state=new,
                    dst-address-type=!local
    Fallback:       Main routing table (WAN1 preferred, WAN2 backup)

Failover:
    WAN down:       disable routing-table route + PCC mangle rules
                    promote surviving WAN to distance=1 in main table
    WAN up:         re-enable route + rules, restore distances
    Trigger:        Netwatch pinging gateway IP every 10s
```

---

## Key RouterOS v7 Differences From v6

| Feature | RouterOS v6 | RouterOS v7 |
|---------|-------------|-------------|
| Create routing table | Implicit (created when referenced) | **Must explicitly create:** `/routing table add name=X fib` |
| Route to specific table | `routing-mark=X` in `/ip route` | `routing-table=X` in `/ip route` |
| Mangle routing mark | `new-routing-mark=X` | **Unchanged** — still `new-routing-mark=X` |
| Local traffic protection | Optional | **Mandatory:** add `dst-address-type=!local` to prerouting PCC rules |

---

## Troubleshooting Quick Reference

| Symptom | Check |
|---------|-------|
| No internet on LAN | `/ip route print` — are both defaults present and active? |
| Can't reach router from LAN (192.168.10.1) | `/ip firewall mangle print without-paging` — look for `I` (INVALID) flags. Fix each with `/ip firewall mangle set N in-interface=bridge-lan`, then reboot. |
| NAT rules showing INVALID after bridge creation | Same as mangle — `/ip firewall nat set N in-interface=bridge-lan` for each affected rule. |
| Mangle rules showing INVALID after bridge creation | Physical interfaces become bridge slaves — all mangle/filter rules referencing them by name must be updated to use `bridge-lan` instead. See Step 5 warning. |
| Fixed mangle rules but still no LAN access | Reboot the router — `/system reboot`. A reboot is required after fixing invalid mangle rules. |
| One WAN not working | `/tool netwatch print` — is that WAN showing `up`? |
| DNS not resolving | `/ip dns print` — is `allow-remote-requests=yes`? |
| All traffic going one WAN | `/ip firewall mangle print` — are both sets of PCC rules enabled? |
| ISP portal (10.254.254.8) not loading | Check mangle rules 0 and 5 — bypass rules for the ISP portal must exist in both prerouting and output chains. |
| WAN2 Netwatch falsely DOWN | OUTPUT chain PCC rules may be routing health-check pings through the wrong WAN — ensure output bypass rules exist before PCC rules (Step 11). |
| WAN2 gateway stale | `/ip dhcp-client print detail` — check gateway; DHCP script should auto-fix |
| Routing tables missing | `/routing table print` — re-run Step 10 if WAN1/WAN2 not listed |
| Firewall rules unreachable (added after drop-all) | New rules appended with plain `add` land below the catch-all drop rule and are never evaluated. Always use `place-before=N` where N is the position of the drop-all rule, or delete and re-add in the correct order. |
| ISP portal blocked by RFC1918 rules | The portal IP `10.254.254.8` falls in the `10.0.0.0/8` range. The `Accept WAN1 ISP portal` rule **must** appear before the RFC1918 drop rules in both input and forward chains. |
| `wan-log` logging action fails | Logging action names cannot contain hyphens. Use `wanlog` (no hyphen), not `wan-log`. |
