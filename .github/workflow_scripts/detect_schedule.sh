#!/usr/bin/env bash
set -e

out() {
  echo "$1" >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

check_pkg() {
  local d="$1"
  echo "== checking $d =="
  if [ "$(id -u)" -eq 0 ]; then
    su -p turannul -c "cd '$d' && makepkg --nobuild --nodeps --noprepare --skippgpcheck"
  else
    (cd "$d" && makepkg --nobuild --nodeps --noprepare --skippgpcheck)
  fi
}

check_all() {
  for d in */; do
    [ -f "$d/PKGBUILD" ] || continue
    grep -q 'pkgver()' "$d/PKGBUILD" || continue
    check_pkg "$d"
  done
}

get_pkgs() {
  git status -s '*/PKGBUILD' | awk '{print $2}' | cut -d/ -f1 | sort -u
}

main() {
  check_all

  local pkgs matrix
  pkgs=$(get_pkgs)

  if [ -z "$pkgs" ]; then
    echo "No package updates detected."
    out "has_packages=false"
    exit 0
  fi

  echo "Updated packages:"
  echo "$pkgs"

  matrix=$(echo "$pkgs" | jq -R -s -c 'split("\n")[:-1]')
  out "packages=$matrix"
  out "has_packages=true"
}

main "$@"
