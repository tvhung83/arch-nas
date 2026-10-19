#!/usr/bin/env bash
# Samba (SMB3): one share per drive mounted under NAS_DIR (read from /etc/fstab, so unplugged drives keep their share).
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${TM_DIR:=}" "${TM_MAX_SIZE:=1T}"
pkg samba avahi
mapfile -t mounts < <(awk -v d="$NAS_DIR/" 'index($2,d)==1{print $2}' /etc/fstab)
{
cat <<EOF
[global]
  server string = $HOST_NAME
  workgroup = WORKGROUP
  server role = standalone server
  security = user
  map to guest = Never
  server min protocol = SMB2_02
  disable netbios = yes
  smb ports = 445
  load printers = no
  printcap name = /dev/null
  disable spoolss = yes
  log file = /var/log/samba/%m.log
  max log size = 1000
  use sendfile = yes
  aio read size = 16384
  aio write size = 16384
  vfs objects = fruit streams_xattr
  fruit:metadata = stream
  fruit:model = MacSamba
  fruit:posix_rename = yes
  fruit:veto_appledouble = no
  fruit:nfs_aces = no
  fruit:wipe_intentionally_left_blank_rfork = yes
  fruit:delete_empty_adfiles = yes
EOF
for mp in "${mounts[@]}"; do
  cat <<EOF

[${mp##*/}]
  path = $mp
  read only = no
  valid users = @nas
EOF
done
if [[ -n $TM_DIR ]]; then cat <<EOF

[timemachine]
  path = $TM_DIR
  read only = no
  valid users = @nas
  fruit:time machine = yes
  fruit:time machine max size = $TM_MAX_SIZE
EOF
fi
} | put /etc/samba/smb.conf

put /etc/avahi/services/smb.service <<'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service><type>_smb._tcp</type><port>445</port></service>
</service-group>
EOF
if [[ -n $ADMIN_PASS ]]; then
  printf '%s\n%s\n' "$ADMIN_PASS" "$ADMIN_PASS" | smbpasswd -s -a "$ADMIN_USER"
elif ! pdbedit -L 2>/dev/null | grep -q "^$ADMIN_USER:"; then
  warn "Set the Samba password: sudo smbpasswd -a $ADMIN_USER"
fi
apply smb
