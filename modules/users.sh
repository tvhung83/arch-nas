#!/usr/bin/env bash
# Admin user (zsh, wheel, nas group), sudo, root locked once the admin has a password.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
pkg sudo zsh
getent group nas >/dev/null || groupadd -g "$NAS_GID" nas
id "$ADMIN_USER" &>/dev/null || useradd -m -G wheel,nas -s /usr/bin/zsh "$ADMIN_USER"
if [[ -n $ADMIN_PASS ]]; then echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd; else warn "ADMIN_PASS not set — password unchanged"; fi
MODE=440 put /etc/sudoers.d/10-wheel <<< '%wheel ALL=(ALL:ALL) ALL'
if [[ $(passwd -S "$ADMIN_USER" | awk '{print $2}') == P ]]; then passwd -l root >/dev/null; fi
