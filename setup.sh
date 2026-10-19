#!/usr/bin/env bash
# Run modules on any Arch system (chroot or live):  ./setup.sh [module ...]   (default: $MODULES)
source "$(dirname "$(readlink -f "$0")")/lib.sh"
need_root
mods=("$@")
if [[ ${#mods[@]} -eq 0 ]]; then read -ra mods <<< "$MODULES"; fi
for m in "${mods[@]}"; do
  f=$SCRIPT_DIR/modules/$m.sh
  [[ -f $f ]] || die "no such module: $m"
  log "module: $m"
  bash "$f" || { warn "module '$m' failed"; [[ ${KEEP_GOING:-0} == 1 ]] || exit 1; }
done
log "done: ${mods[*]}"
