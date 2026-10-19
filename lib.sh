#!/usr/bin/env bash
# Shared helpers + global defaults. Every script sources this; config.env overrides.
# Module-specific knobs get their own `: "${VAR:=default}"` inside the module.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f $SCRIPT_DIR/config.env ]];   then source "$SCRIPT_DIR/config.env";   fi   # public defaults
if [[ -f $SCRIPT_DIR/config.local ]]; then source "$SCRIPT_DIR/config.local"; fi   # your answers (git-ignored)
if [[ -f $SCRIPT_DIR/.secrets ]];     then source "$SCRIPT_DIR/.secrets";     fi   # install-time only

PLACEHOLDER_TOKEN=CHANGE_ME     # a DNS token that is "not set yet": ddns skips it, caddy serves plain HTTP for that host

: "${HOST_NAME:=nas}" "${ADMIN_USER:=admin}" "${TIMEZONE:=UTC}" "${LOCALE:=en_US.UTF-8}" "${KEYMAP:=us}"
: "${MIRROR_COUNTRIES:=VN,SG,HK,JP}" "${TARGET_DISK:=/dev/sda}" "${KERNEL:=linux-lts}" "${UCODE:=intel-ucode}"
: "${NAS_GID:=1500}" "${NAS_DIR:=/srv/nas}"
: "${LAN_CIDR:=10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16}" "${ADMIN_PASS:=}"
: "${MODULES:=system users ssh network shell storage firewall samba nfs caddy ddns database rustapps snapshots}"

c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
log()  { printf '%s==>%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s!!%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die()  { printf '%sxx%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die "run as root"; }

pkg()       { pacman -S --needed --noconfirm "$@"; }
enable()    { systemctl enable "$@"; }
in_chroot() { systemd-detect-virt --chroot --quiet; }
apply()     { systemctl enable "$@"; in_chroot || systemctl restart "$@"; }   # enable (+restart if live)
put()       { install -D -m "${MODE:-644}" /dev/stdin "$1"; }                  # MODE=600 put /path <<EOF
part()      { if [[ $1 == *[0-9] ]]; then echo "${1}p$2"; else echo "${1}$2"; fi; }
ask_yes()   { [[ ${ASSUME_YES:-0} == 1 ]] && return 0; local a; read -rp "$1 [type 'yes']: " a; [[ $a == yes ]]; }

trap 'die "failed at line $LINENO: $BASH_COMMAND"' ERR
