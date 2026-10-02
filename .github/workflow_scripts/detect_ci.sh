#!/usr/bin/env bash
set -e

git config --global --add safe.directory '*' 2>/dev/null || true

out() {
  echo "$1" >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

get_ref() {
  if [ "${EVENT_NAME:-push}" = "pull_request" ]; then
    echo "origin/${BASE_REF:-main}"
  elif [ -n "${BEFORE_REF}" ] && [ "${BEFORE_REF}" != "0000000000000000000000000000000000000000" ] && git rev-parse --verify "${BEFORE_REF}" >/dev/null 2>&1; then
    echo "${BEFORE_REF}"
  elif git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    echo "HEAD~1"
  else
    git hash-object -t tree /dev/null
  fi
}

get_pkgs() {
  local ref="$1"
  git diff --name-only "$ref" HEAD | while read -r f; do
    [ -z "$f" ] && continue
    local p="${f%%/*}"
    [ -d "$p" ] && [ -f "$p/PKGBUILD" ] && echo "$p"
  done | sort -u
}

main() {
  local ref pkgs matrix
  ref=$(get_ref)
  echo "Comparing changes against ref: $ref"
  pkgs=$(get_pkgs "$ref")

  if [ -z "$pkgs" ]; then
    echo "No package changes detected."
    out "has_packages=false"
    exit 0
  fi

  echo "Packages to build:"
  echo "$pkgs"

  matrix=$(echo "$pkgs" | jq -R -s -c 'split("\n")[:-1]')
  out "packages=$matrix"
  out "has_packages=true"
}

main "$@"
