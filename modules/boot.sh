#!/usr/bin/env bash
# INSTALL-ONLY (run by install.sh, not in $MODULES): initramfs + systemd-boot on a btrfs root.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${ROOT_UUID:?run via install.sh}" "${ROOT_FLAGS:=rootflags=subvol=@}" "${KERNEL_ARGS:=quiet usbcore.autosuspend=-1}"
pkg "$KERNEL" "$UCODE"
sed -i "s/^PRESETS=.*/PRESETS=('default')/" "/etc/mkinitcpio.d/$KERNEL.preset"
rm -f "/boot/initramfs-$KERNEL-fallback.img"
mkinitcpio -P
bootctl install || warn "bootctl install reported an error (efivars in chroot?) — check after reboot"
put /boot/loader/loader.conf <<EOF
default arch.conf
timeout 2
editor no
EOF
put /boot/loader/entries/arch.conf <<EOF
title   Arch Linux ($KERNEL)
linux   /vmlinuz-$KERNEL
initrd  /$UCODE.img
initrd  /initramfs-$KERNEL.img
options root=UUID=$ROOT_UUID $ROOT_FLAGS rw $KERNEL_ARGS
EOF
enable systemd-boot-update.service
