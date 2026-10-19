#!/usr/bin/env bash
# Post-boot health check:  sudo ./setup.sh verify
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
for u in sshd NetworkManager avahi-daemon nftables smb nfsv4-server caddy postgresql afraid-ddns.timer; do
  printf '%-20s %s\n' "$u" "$(systemctl is-active "$u" 2>&1)"
done
echo; echo "--- external NTFS mounts"; findmnt -t ntfs3 || echo "(none mounted)"
echo; echo "--- root fs"; findmnt -no FSTYPE,OPTIONS / ; ls /.snapshots 2>/dev/null | tail -3
echo; echo "--- addresses / routes (wired should have the lowest metric)"; ip -br a; ip route | head
echo; echo "--- listening"; ss -tlnH | awk '{print $4}' | sort -u | tr '\n' ' '; echo
echo; echo "--- failed units"; systemctl --failed --no-legend || true
echo; echo "--- ddns (last runs)"; journalctl -u afraid-ddns -n 4 --no-pager 2>/dev/null || true
