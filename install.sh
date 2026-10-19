#!/usr/bin/env bash
# Arch live ISO (UEFI): wipe TARGET_DISK -> btrfs -> pacstrap -> setup.sh inside the chroot.
#   Unattended: ASSUME_YES=1 ADMIN_PASS='…' ./install.sh
source "$(dirname "$(readlink -f "$0")")/lib.sh"
need_root
[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode"
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "No internet (LAN cable in?)"

# interactive config (skip: ./install.sh --defaults, or ASSUME_YES=1). An existing config.local can be reused as-is.
if [[ ${1:-} != --defaults && ${ASSUME_YES:-0} != 1 ]]; then
  if [[ -f $SCRIPT_DIR/config.local ]]; then
    read -rp "Found config.local — use it as is? [Y/n]: " a
    if [[ ${a,,} == n* ]]; then bash "$SCRIPT_DIR/configure.sh"; fi
  else
    bash "$SCRIPT_DIR/configure.sh"
  fi
  if [[ -f $SCRIPT_DIR/config.local ]]; then source "$SCRIPT_DIR/config.local"; fi
fi
[[ -b $TARGET_DISK ]] || die "$TARGET_DISK not found"

# disk the live stick runs from — passed to storage so it never touches it
LIVE_DISK=""
src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
if [[ -n $src ]]; then
  # walk dm/partition parents up to the physical disk (Ventoy: /dev/mapper/ventoy -> sdb1 -> sdb)
  LIVE_DISK=$(lsblk -snpo NAME,TYPE "$src" 2>/dev/null | awk '$2=="disk"{print $1; exit}' || true)
fi

lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE "$TARGET_DISK"
if [[ ${ASSUME_YES:-0} != 1 ]]; then
  read -rp "ALL DATA on $TARGET_DISK will be destroyed. Type the device path to continue: " a
  [[ $a == "$TARGET_DISK" ]] || die "Aborted"
fi
if [[ -z $ADMIN_PASS ]]; then
  read -rsp "Password for $ADMIN_USER (login, sudo, Samba): " p1; echo
  read -rsp "Repeat: " p2; echo
  [[ -n $p1 && $p1 == "$p2" ]] || die "Passwords empty or different"
  ADMIN_PASS=$p1
fi

log "Clock + mirrors"
timedatectl set-ntp true
reflector -c "$MIRROR_COUNTRIES" -p https -l 10 -f 5 --save /etc/pacman.d/mirrorlist || warn "reflector failed; default mirrors"
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf

log "Partitioning $TARGET_DISK: 1G ESP + btrfs (@ @home @log @pg @snapshots)"
umount -R /mnt 2>/dev/null || true
wipefs -af "$TARGET_DISK"
sgdisk --zap-all "$TARGET_DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP -n2:0:0 -t2:8304 -c2:root "$TARGET_DISK"
partprobe "$TARGET_DISK"; udevadm settle
ESP=$(part "$TARGET_DISK" 1); ROOTP=$(part "$TARGET_DISK" 2)
mkfs.fat -F32 -n ESP "$ESP"
mkfs.btrfs -f -m dup -L root "$ROOTP"
mount "$ROOTP" /mnt
for sv in @ @home @log @pg @snapshots; do btrfs subvolume create "/mnt/$sv" >/dev/null; done
umount /mnt
O=noatime,compress=zstd:1
mount -o "$O,subvol=@" "$ROOTP" /mnt
mount --mkdir -o "$O,subvol=@home"      "$ROOTP" /mnt/home
mount --mkdir -o "$O,subvol=@log"       "$ROOTP" /mnt/var/log
mount --mkdir -o "$O,subvol=@pg"        "$ROOTP" /mnt/var/lib/postgres
mount --mkdir -o "$O,subvol=@snapshots" "$ROOTP" /mnt/.snapshots
mount --mkdir -o umask=0077 "$ESP" /mnt/boot

log "pacstrap (minimal — modules install their own packages)"
pacstrap -K /mnt base "$KERNEL" linux-firmware "$UCODE" btrfs-progs sudo zsh git curl nano
# no pinned subvolid, so a rolled-back @ still boots
genfstab -U /mnt | sed 's/subvolid=[0-9]*,//' >> /mnt/etc/fstab

log "Staging scripts"
install -d -m700 /mnt/root/arch-nas
cp -a "$SCRIPT_DIR"/. /mnt/root/arch-nas/
chmod +x /mnt/root/arch-nas/*.sh /mnt/root/arch-nas/modules/*.sh   # archives may lose exec bits
trap 'rm -f /mnt/root/arch-nas/.secrets' EXIT
( umask 077; printf 'ADMIN_PASS=%q\n' "$ADMIN_PASS" > /mnt/root/arch-nas/.secrets )

log "setup.sh in chroot: boot $MODULES"
# shellcheck disable=SC2086
arch-chroot /mnt env ROOT_UUID="$(blkid -s UUID -o value "$ROOTP")" EXCLUDE_DISKS="$TARGET_DISK $LIVE_DISK" \
  bash /root/arch-nas/setup.sh boot $MODULES

rm -f /mnt/root/arch-nas/.secrets
umount -R /mnt
log "Done. Remove the USB stick and reboot. Then: ssh $ADMIN_USER@$HOST_NAME.local   (sudo -i; cd arch-nas; ./setup.sh verify) — DNS tokens later: ./configure.sh web && ./setup.sh ddns caddy"
