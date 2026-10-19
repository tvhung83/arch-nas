#!/usr/bin/env bash
# Interactive config wizard:  ./configure.sh [section ...]
#   sections: system install access nas web db advanced      (default: all)
# Enter keeps the value in [brackets]; '-' clears it. Answers go to config.local (mode 600, git-ignored) which
# overrides config.env, so the published config.env never holds your secrets. Re-run any time, e.g. ./configure.sh web
source "$(dirname "$(readlink -f "$0")")/lib.sh"
[[ -t 0 ]] || die "configure.sh needs a terminal — edit config.local by hand instead"

: "${SSH_KEYS_URL:=}" "${SSH_PUBKEY:=}" "${WIFI_SSID:=}" "${WIFI_PSK:=}" "${MOUNT_NAMES:=}" "${TM_DIR:=}"
: "${AFRAID_DOMAINS:=}" "${DOMAINS:=}" "${LE_EMAIL:=}" "${DB_ENGINE:=postgresql}"
: "${SSH_PASSWORD_AUTH:=auto}" "${IPV6_MODE:=link-local}" "${LAN_CIDR6:=}" "${ACME_STAGING:=0}"

ask() {   # ask VAR "Question" [validator]
  local var=$1 q=$2 check=${3:-} cur a
  cur=${!var:-}
  while :; do
    read -rp "$q [${cur:-(empty)}]: " a
    if [[ $a == - ]]; then a=""; else a=${a:-$cur}; fi
    if [[ -z $check ]] || $check "$a"; then break; fi
    warn "invalid value, try again"
  done
  printf -v "$var" '%s' "$a"
}
ask_secret() {   # ask_secret VAR "Question"  (hidden input)
  local var=$1 q=$2 a st=empty
  if [[ -n ${!var:-} ]]; then st="set"; fi
  read -rsp "$q [$st]: " a; echo
  if [[ $a == - ]]; then printf -v "$var" ''; elif [[ -n $a ]]; then printf -v "$var" '%s' "$a"; fi
}
v_tz()   { [[ -f /usr/share/zoneinfo/$1 ]]; }
v_disk() { [[ -b $1 ]]; }
v_db()   { [[ $1 == postgresql || $1 == sqlite || $1 == none ]]; }
v_user() { [[ $1 =~ ^[a-z_][a-z0-9_-]*$ ]]; }
v_sshpw() { [[ $1 == auto || $1 == yes || $1 == no ]]; }
v_ipv6() { [[ $1 == link-local || $1 == auto ]]; }
v_01()   { [[ $1 == 0 || $1 == 1 ]]; }
v_host() { [[ $1 =~ ^[A-Za-z0-9-]+$ ]]; }
mask()   { if [[ $1 == "$PLACEHOLDER_TOKEN" ]]; then echo "$1"; else echo "${1:0:4}...(set)"; fi; }

sec_system() {
  log "System"
  ask HOST_NAME "Hostname" v_host
  ask TIMEZONE "Timezone (e.g. Asia/Ho_Chi_Minh)" v_tz
  ask LOCALE "Locale"
  ask KEYMAP "Console keymap"
  ask MIRROR_COUNTRIES "Pacman mirror countries (comma-separated codes)"
}
sec_install() {
  log "Install target"
  lsblk -dpno NAME,SIZE,MODEL,TRAN || true
  ask TARGET_DISK "Disk to install on — WILL BE WIPED" v_disk
  local vendor hint=""
  vendor=$(awk -F': *' '/^vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null || true)
  case $vendor in AuthenticAMD) hint=amd-ucode ;; GenuineIntel) hint=intel-ucode ;; esac
  if [[ -n $hint && ! -f $SCRIPT_DIR/config.local ]]; then UCODE=$hint; fi
  ask UCODE "CPU microcode package (detected CPU: ${vendor:-unknown})"
  ask KERNEL "Kernel package (linux-lts or linux)"
}
sec_access() {
  log "Login, SSH and network"
  ask ADMIN_USER "Admin (non-root) username" v_user
  ask SSH_KEYS_URL "SSH public keys URL (e.g. https://github.com/<user>.keys)"
  ask SSH_PUBKEY "…or paste one SSH public key line"
  ask SSH_PASSWORD_AUTH "SSH password login: auto (off once a key exists) | no (key-only, needs a key) | yes" v_sshpw
  ask WIFI_SSID "Wi-Fi SSID (blank = wired only)"
  if [[ -n $WIFI_SSID ]]; then ask_secret WIFI_PSK "Wi-Fi password"; fi
  ask LAN_CIDR "Networks allowed to reach SSH/SMB/NFS (comma-separated IPv4 CIDRs)"
  ask IPV6_MODE "IPv6 on the NAS: link-local (LAN-only, recommended) | auto" v_ipv6
  if [[ $IPV6_MODE == auto ]]; then ask LAN_CIDR6 "Your LAN's global IPv6 prefix for the firewall, e.g. 2001:db8:1:2::/64 (blank = none)"; fi
}
sec_nas() {
  log "NAS"
  ask MOUNT_NAMES "Rename mounts as <ntfs-uuid>=name pairs (blank = use NTFS labels)"
  ask TM_DIR "Time Machine directory on a Linux filesystem (blank = none)"
}
sec_web() {
  log "Web + AfraidDNS"
  echo "Token = the part after /u/ in the FreeDNS 'Direct URL'. ${PLACEHOLDER_TOKEN} = not set yet (safe: skipped, HTTP only)."
  echo "Current hostnames: ${AFRAID_DOMAINS:-(none)}"
  local a e h t cur new=""
  read -rp "  [k] keep   [t] update tokens of current hostnames   [r] replace the list   — choice [k]: " a
  case ${a,,} in
    t) for e in $AFRAID_DOMAINS; do
         if [[ $e == *=* ]]; then h=${e%%=*}; cur=${e#*=}; else h=$e; cur=$PLACEHOLDER_TOKEN; fi
         read -rp "  token for $h [$(mask "$cur")]: " t
         new+="$h=${t:-$cur} "
       done
       AFRAID_DOMAINS=${new% } ;;
    r) while :; do
         read -rp "  hostname (blank = done): " h
         [[ -n $h ]] || break
         read -rp "  token for $h [$PLACEHOLDER_TOKEN]: " t
         new+="$h=${t:-$PLACEHOLDER_TOKEN} "
       done
       AFRAID_DOMAINS=${new% } ;;
  esac
  if [[ -z $AFRAID_DOMAINS ]]; then AFRAID_DOMAINS="yourhost.mooo.com=$PLACEHOLDER_TOKEN"; warn "no hostnames — using placeholder $AFRAID_DOMAINS"; fi
  ask DOMAINS "Domains Caddy should serve (blank = every AfraidDNS hostname above)"
  ask LE_EMAIL "Let's Encrypt contact email (optional)"
  ask ACME_STAGING "Use Let's Encrypt STAGING (untrusted test certs, no real rate limits)? 0 = no, 1 = yes" v_01
}
sec_db() {
  log "Database"
  ask DB_ENGINE "Database: postgresql | sqlite | none" v_db
}
sec_advanced() {
  log "Advanced"
  ask MODULES "Modules to run, in order"
}

sections=("$@")
if [[ ${#sections[@]} -eq 0 ]]; then sections=(system install access nas web db advanced); fi
for s in "${sections[@]}"; do
  case $s in
    system) sec_system ;; install) sec_install ;; access) sec_access ;; nas) sec_nas ;;
    web) sec_web ;; db) sec_db ;; advanced) sec_advanced ;;
    *) die "unknown section: $s (system install access nas web db advanced)" ;;
  esac
done

VARS=(HOST_NAME TIMEZONE LOCALE KEYMAP MIRROR_COUNTRIES TARGET_DISK UCODE KERNEL ADMIN_USER SSH_KEYS_URL SSH_PUBKEY
      SSH_PASSWORD_AUTH WIFI_SSID WIFI_PSK LAN_CIDR IPV6_MODE LAN_CIDR6 ACME_STAGING MOUNT_NAMES TM_DIR AFRAID_DOMAINS DOMAINS LE_EMAIL DB_ENGINE MODULES)
(
  umask 077
  { echo "# written by configure.sh on $(date -Iseconds) — overrides config.env. Do not commit."
    for v in "${VARS[@]}"; do printf '%s=%q\n' "$v" "${!v:-}"; done
  } > "$SCRIPT_DIR/config.local"
)
log "Saved $SCRIPT_DIR/config.local"
if [[ " ${sections[*]} " == *" web "* ]]; then log "Apply DNS/HTTPS changes with:  ./setup.sh ddns caddy"; fi
