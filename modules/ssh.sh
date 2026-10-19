#!/usr/bin/env bash
# sshd: no root login. Keys from SSH_PUBKEY / SSH_KEYS_URL are MERGED into ~/.ssh/authorized_keys (never removed).
# SSH_PASSWORD_AUTH=auto: password login goes off once any key exists. no: force key-only (refuses without a key). yes: allow.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${SSH_KEYS_URL:=}" "${SSH_PUBKEY:=}" "${SSH_PASSWORD_AUTH:=auto}"
pkg openssh
home=/home/$ADMIN_USER; ak=$home/.ssh/authorized_keys
install -d -m700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$home/.ssh"
keys=""
if [[ -n $SSH_PUBKEY ]]; then keys+="$SSH_PUBKEY"$'\n'; fi
if [[ -n $SSH_KEYS_URL ]]; then keys+="$(curl -fsSL "$SSH_KEYS_URL" || true)"$'\n'; fi
{ cat "$ak" 2>/dev/null || true; printf '%s' "$keys"; } | sed '/^[[:space:]]*$/d' | sort -u > "$ak.new"
mv "$ak.new" "$ak"; chown "$ADMIN_USER:$ADMIN_USER" "$ak"; chmod 600 "$ak"
case $SSH_PASSWORD_AUTH in
  auto) if [[ -s $ak ]]; then pwauth=no; else pwauth=yes; warn "No SSH key found — password login left ON (add a key, then ./setup.sh ssh)"; fi ;;
  no)   [[ -s $ak ]] || die "SSH_PASSWORD_AUTH=no but $ak has no keys — refusing (you would lock yourself out)"; pwauth=no ;;
  yes)  pwauth=yes ;;
  *)    die "SSH_PASSWORD_AUTH must be auto|yes|no" ;;
esac
{
  echo "PermitRootLogin no"
  echo "PasswordAuthentication $pwauth"
  echo "KbdInteractiveAuthentication no"
  if [[ $pwauth == no ]]; then echo "AuthenticationMethods publickey"; fi
} | put /etc/ssh/sshd_config.d/10-nas.conf
apply sshd
