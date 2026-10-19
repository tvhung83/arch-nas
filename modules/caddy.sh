#!/usr/bin/env bash
# Caddy: automatic Let's Encrypt, HTTP/2 + HTTP/3. Serves DOMAINS, or (default) every AFRAID_DOMAINS hostname.
# Hostnames whose DNS token is still the placeholder are served as plain http:// (no certificate attempts).
# Per-app routes go in /etc/caddy/conf.d/*.caddy and apply to all sites; split by host with a matcher, e.g.
#   @api host api.mooo.com
#   handle @api { reverse_proxy 127.0.0.1:8081 }
source "$(dirname "$(readlink -f "$0")")/../lib.sh"; need_root
: "${DOMAINS:=}" "${AFRAID_DOMAINS:=}" "${LE_EMAIL:=}" "${ACME_STAGING:=0}"
addrs=(); ph=0
if [[ -n $DOMAINS ]]; then
  read -ra addrs <<< "$DOMAINS"
else
  for e in $AFRAID_DOMAINS; do
    [[ $e == *=* ]] || continue
    if [[ ${e#*=} == "$PLACEHOLDER_TOKEN" ]]; then addrs+=("http://${e%%=*}"); ph=$((ph+1)); else addrs+=("${e%%=*}"); fi
  done
fi
[[ ${#addrs[@]} -gt 0 ]] || { warn "no domains (DOMAINS / AFRAID_DOMAINS) — skipping caddy"; exit 0; }
pkg caddy
install -d /etc/caddy/conf.d
printf -v site '%s, ' "${addrs[@]}"; site=${site%, }
{
  g=""
  if [[ -n $LE_EMAIL ]]; then g+=$'\temail '"$LE_EMAIL"$'\n'; fi
  if [[ $ACME_STAGING == 1 ]]; then g+=$'\tacme_ca https://acme-staging-v02.api.letsencrypt.org/directory\n'; fi
  if [[ -n $g ]]; then printf '{\n%s}\n\n' "$g"; fi
  printf '%s {\n\tencode zstd gzip\n\trespond /healthz "ok" 200\n\timport conf.d/*.caddy\n}\n' "$site"
} | put /etc/caddy/Caddyfile
log "caddy sites: $site"
if (( ph )); then warn "$ph hostname(s) still use the placeholder token → plain HTTP only. Later: ./configure.sh web && ./setup.sh ddns caddy"; fi
if [[ $ACME_STAGING == 1 ]]; then warn "ACME STAGING is ON: certificates are not trusted by browsers. When it works: set ACME_STAGING=0 and run ./setup.sh caddy"; fi
apply caddy
