#!/usr/bin/env bash
# AfraidDNS (FreeDNS) updater for any number of hostnames: AFRAID_DOMAINS="host=token host2=token2 ...".
# systemd timer every 5 min; one request per entry; tokens are never logged. Placeholder tokens (CHANGE_ME) are skipped.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${AFRAID_DOMAINS:=}"
[[ -n $AFRAID_DOMAINS ]] || { warn "AFRAID_DOMAINS empty — skipping ddns"; exit 0; }
pkg curl
{ echo "ENTRIES=\"$AFRAID_DOMAINS\""; echo "PLACEHOLDER=\"$PLACEHOLDER_TOKEN\""; } | MODE=600 put /etc/afraid-ddns.conf
if [[ " $AFRAID_DOMAINS " == *"=$PLACEHOLDER_TOKEN "* ]]; then warn "placeholder DNS token(s) present — those hosts are skipped until set: ./configure.sh web && ./setup.sh ddns caddy"; fi
MODE=755 put /usr/local/bin/afraid-ddns <<'EOF'
#!/usr/bin/env bash
set -u
source /etc/afraid-ddns.conf
rc=0
for e in $ENTRIES; do
  if [[ $e == *=* ]]; then host=${e%%=*}; tok=${e#*=}; else host="${e:0:4}..."; tok=$e; fi
  if [[ $tok == "$PLACEHOLDER" ]]; then echo "$host: token not set yet — skipped"; continue; fi
  if out=$(curl -4 -fsS --max-time 20 "https://sync.afraid.org/u/$tok/"); then echo "$host: $out"
  else echo "$host: update failed" >&2; rc=1; fi
done
exit $rc
EOF
put /etc/systemd/system/afraid-ddns.service <<'EOF'
[Unit]
Description=Update AfraidDNS records
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/afraid-ddns
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
NoNewPrivileges=yes
EOF
put /etc/systemd/system/afraid-ddns.timer <<'EOF'
[Unit]
Description=AfraidDNS update timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF
in_chroot || systemctl daemon-reload
apply afraid-ddns.timer
