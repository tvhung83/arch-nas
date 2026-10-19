#!/usr/bin/env bash
# Run on your dev machine (needs git + the gh CLI, logged in). Publishes the COMMITTED files as the fixed GitHub
# release "stable" (asset arch-nas.tar.gz, top folder arch-nas/) and optionally creates a short link to it.
#   ./tools/release.sh                               # build + upload only
#   ./tools/release.sh --alias n150nas               # …+ tinyurl.com/n150nas  (needs: export TINYURL_TOKEN=…)
#   ./tools/release.sh --alias n150nas --via isgd    # …+ is.gd/n150nas        (no account)
# Without TINYURL_TOKEN it prints the manual steps instead (tinyurl.com's web form has a custom-alias field).
# Every short link is verified end to end: the script downloads it and checks that it really is the archive.
# (Written for macOS bash 3.2 as well: no bash-4-only features.)
set -euo pipefail
cd "$(dirname "$0")/.."
alias=""; via=tinyurl
while [[ $# -gt 0 ]]; do
  case $1 in
    --alias) alias=${2:?usage: --alias <name>}; shift 2 ;;
    --via)   via=${2:?usage: --via tinyurl|isgd}; shift 2 ;;
    *) echo "unknown argument: $1"; exit 1 ;;
  esac
done

case $via in tinyurl|isgd) ;; *) echo "unknown --via '$via' (tinyurl|isgd)"; exit 1 ;; esac
git diff --quiet HEAD -- || { echo "Uncommitted changes — commit first (the release contains committed files only)."; exit 1; }
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git archive --format=tar.gz --prefix=arch-nas/ -o "$tmp/arch-nas.tar.gz" HEAD   # honours .gitattributes: no tools/, no secrets
gh release view stable >/dev/null 2>&1 || gh release create stable --title stable --notes "rolling release used by the live-ISO one-liner"
gh release upload stable "$tmp/arch-nas.tar.gz" --clobber
url="https://github.com/$repo/releases/download/stable/arch-nas.tar.gz"
echo "Published: $url"

verify() {   # verify <short-url>: must download as our archive
  local first
  first=$(curl -fsSL "$1" | tar tzf - 2>/dev/null | head -1 || true)
  if [[ $first == arch-nas/ ]]; then echo "✔ $1 downloads the archive"; return 0; fi
  echo "✘ $1 does NOT return the archive (got '${first:-nothing}') — the shortener may be showing an interstitial/blocking the link."
  return 1
}

short=""
if [[ -n $alias ]]; then
  case $via in
    tinyurl)
      if [[ -z ${TINYURL_TOKEN:-} ]]; then
        echo "No TINYURL_TOKEN set. Manual route (no API needed):"
        echo "  1. open https://tinyurl.com  2. paste: $url  3. custom alias: $alias"
        echo "  (or create a free API token in TinyURL → Settings → API, then re-run with TINYURL_TOKEN=…)"
        echo "Then verify:  curl -fsSL tinyurl.com/$alias | tar tz | head -1     # expect: arch-nas/"
        exit 0
      fi
      resp=$(curl -sS -X POST https://api.tinyurl.com/create \
        -H "Authorization: Bearer $TINYURL_TOKEN" -H 'Content-Type: application/json' \
        -d "{\"url\":\"$url\",\"domain\":\"tinyurl.com\",\"alias\":\"$alias\"}")
      short=$(printf '%s' "$resp" | sed -n 's/.*"tiny_url" *: *"\([^"]*\)".*/\1/p' | tr -d '\\')
      if [[ -z $short ]]; then echo "TinyURL error: $resp"; exit 1; fi
      if [[ $short != "https://tinyurl.com/$alias" ]]; then echo "! alias '$alias' was not granted (taken?) — TinyURL returned $short"; fi
      ;;
    isgd)
      short=$(curl -sS -G https://is.gd/create.php -d format=simple --data-urlencode "url=$url" --data-urlencode "shorturl=$alias")
      case $short in https://*) ;; *) echo "is.gd error: $short"; exit 1 ;; esac
      ;;
    *) echo "unknown --via '$via' (tinyurl|isgd)"; exit 1 ;;
  esac
  echo "Short link: $short"
  if verify "$short"; then
    echo "Live ISO:  curl -fsSL ${short#https://} | tar xz && cd arch-nas && bash install.sh"
  else
    echo "Fallback:  curl -fsSL $url | tar xz && cd arch-nas && bash install.sh   (or serve the archive from your Mac)"
    exit 1
  fi
else
  echo "Live ISO:  curl -fsSL $url | tar xz && cd arch-nas && bash install.sh"
fi
