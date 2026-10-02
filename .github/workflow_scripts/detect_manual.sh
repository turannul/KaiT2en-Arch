#!/usr/bin/env bash
set -e

out() {
  echo "$1" >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

all_pkgs() {
  for d in */; do
    [ -f "$d/PKGBUILD" ] && echo "${d%/}"
  done | sort -u
}

main() {
  local t="${TARGET:-all}"

  if [ "$t" = "all" ] || [ -z "$t" ]; then
    local pkgs matrix
    pkgs=$(all_pkgs)
    matrix=$(echo "$pkgs" | jq -R -s -c 'split("\n")[:-1]')
    out "packages=$matrix"
    out "has_packages=true"
  elif [ -d "$t" ] && [ -f "$t/PKGBUILD" ]; then
    local matrix
    matrix=$(jq -n -c --arg pkg "$t" '[$pkg]')
    out "packages=$matrix"
    out "has_packages=true"
  else
    echo "Package $t not found."
    out "has_packages=false"
    exit 0
  fi
}

main "$@"
