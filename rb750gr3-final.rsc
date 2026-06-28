# 2026-06-27 03:01:57 by RouterOS 7.23.1
# software id = A3JT-ZQYE
#
# model = RB750Gr3
# serial number = HGC09HE5R8E
/interface bridge
add comment="LAN Bridge" name=bridge-lan
/interface ethernet
set [ find default-name=ether1 ] comment=WAN1-SSWL-Static
set [ find default-name=ether2 ] comment=WAN2-JIO-DHCP
set [ find default-name=ether3 ] comment=AP-ArcherC64
set [ find default-name=ether4 ] comment=Switch-tl-sg105e
set [ find default-name=ether5 ] comment=Spare
/disk
add parent=sd1 partition-number=1 partition-offset=1048576 partition-size=\
    31912361984 type=partition
/interface wireless security-profiles
set [ find default=yes ] supplicant-identity=MikroTik
/ip pool
add name=lan-pool ranges=192.168.10.100-192.168.10.200
/ip dhcp-server
add address-pool=lan-pool interface=bridge-lan lease-time=12h name=lan-dhcp
/routing table
add disabled=no fib name=WAN1
add disabled=no fib name=WAN2
/system logging action
set 1 disk-file-name=sd1-part1/syslog
add disk-file-name=sd1-part1/wan-failover name=wanlog target=disk
/interface bridge port
add bridge=bridge-lan interface=ether3
add bridge=bridge-lan interface=ether4
add bridge=bridge-lan interface=ether5
/ip address
add address=172.28.62.195/24 comment=WAN1 interface=ether1 network=\
    172.28.62.0
add address=192.168.10.1/24 comment=LAN interface=bridge-lan network=\
    192.168.10.0
/ip dhcp-client
add add-default-route=no comment="WAN2 JIO" interface=ether2 name=client1 \
    script="\
    \n        :local gw \$\"gateway-address\"\
    \n        :if (\$gw != \"\") do={\
    \n            /ip route set [find comment=\"WAN2 table default\"] gateway=\
    \$gw\
    \n            /ip route set [find comment=\"WAN2-main\"] gateway=\$gw\
    \n            /ip route set [find comment=\"WAN2 health check route\"] gat\
    eway=\$gw\
    \n            /log info (\"WAN2 DHCP: gateway updated to \" . \$gw)\
    \n        }\
    \n    " use-peer-dns=no
/ip dhcp-server lease
add address=192.168.10.2 comment=NVR-argus mac-address=98:AF:65:8B:D4:D1
add address=192.168.10.3 comment=Switch-tl-sg105e mac-address=\
    A8:29:48:58:3E:7B
add address=192.168.10.20 comment=Camera-Bedroom mac-address=\
    20:BB:BC:8F:5E:6F
add address=192.168.10.21 comment=Camera-Guestroom mac-address=\
    20:BB:BC:60:E6:99
add address=192.168.10.22 comment=Camera-HallRoom mac-address=\
    A0:FF:0C:A3:AF:A5
add address=192.168.10.4 comment=RE505X-extender mac-address=\
    10:5A:95:D3:40:73
add address=192.168.10.5 comment=ArcherC64-AP mac-address=7C:F1:7E:A9:9C:DF
/ip dhcp-server network
add address=192.168.10.0/24 comment=LAN dns-server=192.168.10.1 gateway=\
    192.168.10.1
/ip dns
set allow-remote-requests=yes cache-max-ttl=1d servers=8.8.8.8,1.1.1.1
/ip firewall filter
add action=accept chain=input comment="Accept established/related/untracked" \
    connection-state=established,related,untracked
add action=drop chain=input comment="Drop invalid" connection-state=invalid
add action=accept chain=input comment="Accept from LAN" in-interface=\
    bridge-lan
add action=accept chain=input comment="Accept loopback" in-interface=lo
add action=accept chain=input comment="Allow WAN1 ISP portal" in-interface=\
    ether1 src-address=10.254.254.8
add action=drop chain=input comment="Drop RFC1918 src on WAN1" in-interface=\
    ether1 src-address=10.0.0.0/8
add action=drop chain=input comment="Drop RFC1918 src on WAN1" in-interface=\
    ether1 src-address=172.16.0.0/12
add action=drop chain=input comment="Drop RFC1918 src on WAN1" in-interface=\
    ether1 src-address=192.168.0.0/16
add action=drop chain=input comment="Drop RFC1918 src on WAN2" in-interface=\
    ether2 src-address=10.0.0.0/8
add action=drop chain=input comment="Drop RFC1918 src on WAN2" in-interface=\
    ether2 src-address=172.16.0.0/12
add action=drop chain=input comment="Drop RFC1918 src on WAN2" in-interface=\
    ether2 src-address=192.168.0.0/16
add action=accept chain=input comment="Allow ICMP rate limited" limit=\
    10,20:packet protocol=icmp
add action=drop chain=input comment="Drop excess ICMP" protocol=icmp
add action=drop chain=input comment="Drop all other input"
add action=accept chain=forward comment=\
    "Accept established/related/untracked" connection-state=\
    established,related,untracked
add action=drop chain=forward comment="Drop invalid" connection-state=invalid
add action=accept chain=forward comment="LAN to WAN1" in-interface=bridge-lan \
    out-interface=ether1
add action=accept chain=forward comment="LAN to WAN2" in-interface=bridge-lan \
    out-interface=ether2
add action=accept chain=forward comment="Allow WAN1 ISP portal" in-interface=\
    ether1 src-address=10.254.254.8
add action=drop chain=forward comment="Drop RFC1918 src on WAN1" \
    in-interface=ether1 src-address=10.0.0.0/8
add action=drop chain=forward comment="Drop RFC1918 src on WAN1" \
    in-interface=ether1 src-address=172.16.0.0/12
add action=drop chain=forward comment="Drop RFC1918 src on WAN1" \
    in-interface=ether1 src-address=192.168.0.0/16
add action=drop chain=forward comment="Drop RFC1918 src on WAN2" \
    in-interface=ether2 src-address=10.0.0.0/8
add action=drop chain=forward comment="Drop RFC1918 src on WAN2" \
    in-interface=ether2 src-address=172.16.0.0/12
add action=drop chain=forward comment="Drop RFC1918 src on WAN2" \
    in-interface=ether2 src-address=192.168.0.0/16
add action=drop chain=forward comment="Drop all other forward"
/ip firewall mangle
add action=accept chain=prerouting comment=\
    "Bypass PCC: WAN1 ISP portal (prerouting)" dst-address=10.254.254.8 \
    in-interface=bridge-lan
add action=accept chain=prerouting comment=\
    "Bypass policy routing: WAN1 subnet" dst-address=172.28.62.0/24 \
    in-interface=bridge-lan
add action=accept chain=prerouting comment=\
    "Bypass policy routing: WAN2 subnet" dst-address=192.168.29.0/24 \
    in-interface=bridge-lan
add action=mark-connection chain=input comment=\
    "Mark new inbound WAN1 connections" connection-state=new in-interface=\
    ether1 new-connection-mark=WAN1-conn
add action=mark-connection chain=input comment=\
    "Mark new inbound WAN2 connections" connection-state=new in-interface=\
    ether2 new-connection-mark=WAN2-conn
add action=accept chain=output comment="Bypass PCC: WAN1 ISP portal" \
    dst-address=10.254.254.8
add action=accept chain=output comment="Bypass PCC: WAN1 subnet (output)" \
    dst-address=172.28.62.0/24
add action=accept chain=output comment="Bypass PCC: WAN2 subnet (output)" \
    dst-address=192.168.29.0/24
add action=mark-connection chain=output comment="WAN1-pcc router output" \
    connection-mark=no-mark connection-state=new new-connection-mark=\
    WAN1-conn per-connection-classifier=both-addresses:2/0
add action=mark-connection chain=output comment="WAN2-pcc router output" \
    connection-mark=no-mark connection-state=new new-connection-mark=\
    WAN2-conn per-connection-classifier=both-addresses:2/1
add action=mark-connection chain=prerouting comment="WAN1-pcc LAN" \
    connection-mark=no-mark connection-state=new dst-address-type=!local \
    in-interface=bridge-lan new-connection-mark=WAN1-conn \
    per-connection-classifier=both-addresses:2/0
add action=mark-connection chain=prerouting comment="WAN2-pcc LAN" \
    connection-mark=no-mark connection-state=new dst-address-type=!local \
    in-interface=bridge-lan new-connection-mark=WAN2-conn \
    per-connection-classifier=both-addresses:2/1
add action=mark-routing chain=output comment=\
    "Route WAN1-conn via WAN1 table (output)" connection-mark=WAN1-conn \
    new-routing-mark=WAN1
add action=mark-routing chain=prerouting comment=\
    "Route WAN1-conn via WAN1 table (prerouting)" connection-mark=WAN1-conn \
    in-interface=bridge-lan new-routing-mark=WAN1
add action=mark-routing chain=output comment=\
    "Route WAN2-conn via WAN2 table (output)" connection-mark=WAN2-conn \
    new-routing-mark=WAN2
add action=mark-routing chain=prerouting comment=\
    "Route WAN2-conn via WAN2 table (prerouting)" connection-mark=WAN2-conn \
    in-interface=bridge-lan new-routing-mark=WAN2
/ip firewall nat
add action=masquerade chain=srcnat comment="NAT WAN1" out-interface=ether1
add action=masquerade chain=srcnat comment="NAT WAN2" out-interface=ether2
/ip route
add comment="WAN1 table default" disabled=no distance=1 dst-address=0.0.0.0/0 \
    gateway=172.28.62.1 routing-table=WAN1
add comment="WAN2 table default" disabled=no distance=1 dst-address=0.0.0.0/0 \
    gateway=192.168.29.1 routing-table=WAN2
add comment=WAN1-main distance=1 dst-address=0.0.0.0/0 gateway=172.28.62.1
add comment=WAN2-main distance=2 dst-address=0.0.0.0/0 gateway=192.168.29.1
add comment="WAN1 health check route" dst-address=8.8.8.8/32 gateway=\
    172.28.62.1
add comment="WAN2 health check route" dst-address=1.1.1.1/32 gateway=\
    192.168.29.1
add comment="WAN1 ISP portal" dst-address=10.254.254.8/32 gateway=172.28.62.1
/system clock
set time-zone-name=Asia/Kolkata
/system identity
set name=KOL-LB
/system logging
add action=disk topics=info
add action=wanlog comment="WAN failover events to SD" topics=script
/tool netwatch
add comment="WAN1 health check" down-script="\
    \n        /log info \"WAN1 DOWN - disabling routes and mangle rules\"\
    \n        /ip route disable [find comment=\"WAN1 table default\"]\
    \n        /ip route set [find comment=\"WAN1-main\"] distance=10\
    \n        /ip route set [find comment=\"WAN2-main\"] distance=1\
    \n        /ip firewall mangle disable [find comment~\"WAN1-pcc\"]\
    \n    " host=172.28.62.1 interval=10s timeout=3s type=simple up-script="\
    \n        /log info \"WAN1 UP - restoring routes and mangle rules\"\
    \n        /ip route enable [find comment=\"WAN1 table default\"]\
    \n        /ip route set [find comment=\"WAN1-main\"] distance=1\
    \n        /ip route set [find comment=\"WAN2-main\"] distance=2\
    \n        /ip firewall mangle enable [find comment~\"WAN1-pcc\"]\
    \n    "
add comment="WAN2 health check" down-script="\
    \n        /log info \"WAN2 DOWN - disabling routes and mangle rules\"\
    \n        /ip route disable [find comment=\"WAN2 table default\"]\
    \n        /ip route set [find comment=\"WAN2-main\"] distance=10\
    \n        /ip firewall mangle disable [find comment~\"WAN2-pcc\"]\
    \n    " host=192.168.29.1 interval=10s timeout=3s type=simple up-script="\
    \n        /log info \"WAN2 UP - restoring routes and mangle rules\"\
    \n        /ip route enable [find comment=\"WAN2 table default\"]\
    \n        /ip route set [find comment=\"WAN2-main\"] distance=2\
    \n        /ip firewall mangle enable [find comment~\"WAN2-pcc\"]\
    \n    "
