#!/usr/bin/env bash
# NetworkManager (wired metric 100 beats Wi-Fi 600) + Avahi/mDNS so <host>.local resolves.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${WIFI_SSID:=}" "${WIFI_PSK:=}"
pkg networkmanager avahi nss-mdns
nm=/etc/NetworkManager/system-connections
MODE=600 put $nm/wired.nmconnection <<EOF
[connection]
id=wired
uuid=$(cat /proc/sys/kernel/random/uuid)
type=ethernet
autoconnect-priority=100

[ipv4]
method=auto
route-metric=100

[ipv6]
method=auto
route-metric=100
EOF
if [[ -n $WIFI_SSID ]]; then
  MODE=600 put $nm/wifi.nmconnection <<EOF
[connection]
id=wifi
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
autoconnect-priority=10

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PSK

[ipv4]
method=auto
route-metric=600

[ipv6]
method=auto
route-metric=600
EOF
fi
sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' /etc/nsswitch.conf
enable NetworkManager
in_chroot || nmcli connection reload || true
apply avahi-daemon
