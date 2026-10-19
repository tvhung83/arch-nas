#!/usr/bin/env bash
# Hardened systemd template for self-contained Rust binaries:
#   binary /opt/apps/<name>/<name>, env /etc/apps/<name>.env, start with: systemctl enable --now app@<name>
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${APPS_DIR:=/opt/apps}"
install -d -m755 "$APPS_DIR" /etc/apps
put /etc/systemd/system/app@.service <<EOF
[Unit]
Description=Rust app %i
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
DynamicUser=yes
StateDirectory=apps/%i
WorkingDirectory=%S/apps/%i
EnvironmentFile=-/etc/apps/%i.env
ExecStart=$APPS_DIR/%i/%i
Restart=on-failure
RestartSec=3
MemoryMax=1G
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
EOF
in_chroot || systemctl daemon-reload
