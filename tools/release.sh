#!/usr/bin/env bash
# Run on your dev machine (needs git + the gh CLI, logged in). Publishes the COMMITTED files as the fixed
# GitHub release "stable" (asset arch-nas.tar.gz, top folder arch-nas/) and optionally makes an is.gd short link.
#   ./tools/release.sh                  # build + upload
#   ./tools/release.sh --alias n150nas  # …and create is.gd/n150nas (first time only; the URL never changes)
set -euo pipefail
cd "$(dirname "$0")/.."
alias=""; if [[ ${1:-} == --alias ]]; then alias=${2:?usage: --alias <name>}; fi
git diff --quiet HEAD -- || { echo "Uncommitted changes — commit first (the release contains committed files only)."; exit 1; }
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git archive --format=tar.gz --prefix=arch-nas/ -o "$tmp/arch-nas.tar.gz" HEAD   # honours .gitattributes: no tools/, no secrets
gh release view stable >/dev/null 2>&1 || gh release create stable --title stable --notes "rolling release used by the live-ISO one-liner"
gh release upload stable "$tmp/arch-nas.tar.gz" --clobber
url="https://github.com/$repo/releases/download/stable/arch-nas.tar.gz"
echo "Published: $url"
if [[ -n $alias ]]; then
  echo "is.gd says:"
  curl -sS -G https://is.gd/create.php -d format=simple --data-urlencode "url=$url" --data-urlencode "shorturl=$alias"; echo
  echo "Live ISO:  curl -fsSL is.gd/$alias | tar xz && cd arch-nas && bash install.sh"
else
  echo "Live ISO:  curl -fsSL $url | tar xz && cd arch-nas && bash install.sh"
fi
