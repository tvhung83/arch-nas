#!/usr/bin/env bash
# nftables: LAN reaches everything; the internet reaches only WAN_TCP / WAN_UDP.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${WAN_TCP:=80, 443}" "${WAN_UDP:=443}"
pkg nftables
put /etc/nftables.conf <<EOF
#!/usr/bin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ct state invalid drop
    meta l4proto { icmp, ipv6-icmp } accept
    tcp dport { $WAN_TCP } accept
    udp dport { $WAN_UDP } accept
    ip saddr { $LAN_CIDR } accept
    ip6 saddr { fe80::/10, fc00::/7 } accept
  }
  chain forward { type filter hook forward priority 0; policy drop; }
}
EOF
apply nftables
