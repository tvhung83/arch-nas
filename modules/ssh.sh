#!/usr/bin/env bash
# sshd: no root login; key-only if a key is found (SSH_PUBKEY / SSH_KEYS_URL), else password stays ON.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${SSH_KEYS_URL:=}" "${SSH_PUBKEY:=}"
pkg openssh
home=/home/$ADMIN_USER; ak=$home/.ssh/authorized_keys
install -d -m700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$home/.ssh"
keys=""
if [[ -n $SSH_PUBKEY ]]; then keys+="$SSH_PUBKEY"$'\n'; fi
if [[ -n $SSH_KEYS_URL ]]; then keys+="$(curl -fsSL "$SSH_KEYS_URL" || true)"$'\n'; fi
{ cat "$ak" 2>/dev/null || true; printf '%s' "$keys"; } | sed '/^[[:space:]]*$/d' | sort -u > "$ak.new"
mv "$ak.new" "$ak"; chown "$ADMIN_USER:$ADMIN_USER" "$ak"; chmod 600 "$ak"
pwauth=yes
if [[ -s $ak ]]; then pwauth=no; else warn "No SSH key found — password login left ON"; fi
put /etc/ssh/sshd_config.d/10-nas.conf <<EOF
PermitRootLogin no
PasswordAuthentication $pwauth
KbdInteractiveAuthentication no
EOF
apply sshd
