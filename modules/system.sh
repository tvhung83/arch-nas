#!/usr/bin/env bash
# Time, locale, hostname, pacman, zram swap, journald, trim, mirror refresh.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
pkg reflector zram-generator man-db rsync htop jq ethtool smartmontools gptfdisk dosfstools

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc || true
grep -q "^$LOCALE UTF-8" /etc/locale.gen || echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE"   > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOST_NAME"     > /etc/hostname
put /etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOST_NAME
EOF

sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 8/; s/^#Color/Color/' /etc/pacman.conf
put /etc/xdg/reflector/reflector.conf <<EOF
--save /etc/pacman.d/mirrorlist
--protocol https
--country $MIRROR_COUNTRIES
--latest 10
--sort rate
EOF
put /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
put /etc/sysctl.d/99-zram.conf <<EOF
vm.swappiness = 100
vm.page-cluster = 0
EOF
put /etc/systemd/journald.conf.d/size.conf <<EOF
[Journal]
Storage=persistent
SystemMaxUse=200M
EOF
enable fstrim.timer systemd-timesyncd reflector.timer
