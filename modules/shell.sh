#!/usr/bin/env bash
# zsh + zimfw for ADMIN_USER.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
pkg zsh git curl
home=/home/$ADMIN_USER
[[ -d $home/.zim ]] && { log "zimfw already installed"; exit 0; }
runuser -u "$ADMIN_USER" -- env HOME="$home" zsh -c \
  'cd ~ && curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh' \
  || warn "zimfw install failed — rerun: ./setup.sh shell"
