#!/usr/bin/env bash
# External NTFS drives -> mounted READ-WRITE at $NAS_DIR/<name> (name = slug of the NTFS label).
# Nothing here formats, partitions, repairs or writes to those drives, so they stay plain NTFS and
# portable. Idempotent; works in the installer chroot and on a running system. Re-run after plugging a new drive.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${EXCLUDE_DISKS:=}" "${MOUNT_NAMES:=}"
declare -A used=()

slug() { local s; s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n_-' '-' | sed 's/^-*//; s/-*$//'); echo "${s:-disk}"; }
fstab_set() { sed -i "\|[[:space:]]$1[[:space:]]|d" /etc/fstab; echo "$2" >> /etc/fstab; }

id "$ADMIN_USER" >/dev/null 2>&1 || die "user '$ADMIN_USER' does not exist — run ./setup.sh users first"
uid=$(id -u "$ADMIN_USER"); gid=$(id -g "$ADMIN_USER")      # ntfs3 only accepts numeric ids; files appear as <user>:<user>
install -d "$NAS_DIR"
while read -r m; do used[${m##*/}]=1; done < <(awk -v d="$NAS_DIR/" 'index($2,d)==1{print $2}' /etc/fstab)

found=0
while read -r dev; do
  [[ " $TARGET_DISK $EXCLUDE_DISKS " == *" $dev "* ]] && continue
  while read -r p fs; do
    [[ $fs == ntfs ]] || continue
    label=$(blkid -s LABEL -o value "$p" 2>/dev/null || true)
    case $label in Ventoy|VTOYEFI) continue ;; esac            # never touch the installer stick
    uuid=$(blkid -s UUID -o value "$p")
    mp=$(awk -v u="UUID=$uuid" -v d="$NAS_DIR/" '$1==u && index($2,d)==1{print $2; exit}' /etc/fstab)
    if [[ -z $mp ]]; then                                       # new drive: pick a stable name
      name=$(slug "$label")
      for kv in $MOUNT_NAMES; do if [[ ${kv%%=*} == "$uuid" ]]; then name=${kv#*=}; fi; done
      base=$name; i=2; while [[ -n ${used[$name]:-} ]]; do name=$base-$i; i=$((i+1)); done
      used[$name]=1; mp=$NAS_DIR/$name
    fi
    mkdir -p "$mp"
    # immutable while unmounted: if the drive is missing, clients can't fill the SSD through an empty dir
    if ! mountpoint -q "$mp"; then chattr +i "$mp" || warn "could not chattr +i $mp"; fi
    fstab_set "$mp" "UUID=$uuid $mp ntfs3 rw,noatime,windows_names,nofail,x-systemd.device-timeout=20,uid=$uid,gid=$gid,fmask=0113,dmask=0002 0 0"
    in_chroot || systemctl daemon-reload
    mountpoint -q "$mp" || mount "$mp" \
      || warn "$p did not mount rw — NTFS is probably flagged dirty (Windows fast-startup/hibernate). Shut Windows down fully once. This script never runs ntfsfix."
    log "$p ('$label') -> $mp"
    found=$((found+1))
  done < <(lsblk -lnpo NAME,FSTYPE "$dev")
done < <(lsblk -dnpo NAME,TRAN | awk '$2=="usb"{print $1}')
(( found )) || warn "No NTFS USB drive found. Plug the boxes in and run: sudo ./setup.sh storage samba nfs"

# Safe-removal helper: ntfs3 marks the volume dirty while mounted, so unmount before unplugging
# (otherwise Windows will offer to run chkdsk when you move the drive).
MODE=755 put /usr/local/bin/nas-eject <<EOF
#!/usr/bin/env bash
set -e
systemctl stop smb nfsv4-server 2>/dev/null || true
for m in \$(findmnt -rno TARGET -t ntfs3 | grep '^$NAS_DIR/'); do umount "\$m" && echo "unmounted \$m"; done
sync; echo "Safe to unplug. After re-plugging: sudo mount -a && sudo systemctl restart nfsv4-server smb (or just reboot)"
EOF
