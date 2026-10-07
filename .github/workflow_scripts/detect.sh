#!/usr/bin/env bash

setup_environment() {
  set -e
  git config --global --add safe.directory '*'
}

out() {
  echo "$1" >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

emit_matrix() {
  local pkgs="$1"
  if [ -z "$pkgs" ]; then
    echo "No packages to build."
    out "has_packages=false"
    out "packages=[]"
    exit 0
  fi

  echo "Packages to build:"
  echo "$pkgs"

  local matrix
  matrix="[$(echo "$pkgs" | awk 'NF { if (n++) printf ","; printf "\"%s\"", $1 }')]"
  out "packages=$matrix"
  out "has_packages=true"
}

all_pkgs() {
  for d in */; do
    [ -f "$d/PKGBUILD" ] && echo "${d%/}"
  done | sort -u
}

detect_manual() {
  local t="${TARGET:-${1:-all}}"
  if [ "$t" = "all" ] || [ -z "$t" ]; then
    emit_matrix "$(all_pkgs)"
  elif [ -d "$t" ] && [ -f "$t/PKGBUILD" ]; then
    emit_matrix "$t"
  else
    echo "Package '$t' not found."
    out "has_packages=false"
    out "packages=[]"
    exit 0
  fi
}

detect_ci() {
  local ref
  if [ "${EVENT_NAME:-${GITHUB_EVENT_NAME}}" = "pull_request" ]; then
    ref="origin/${BASE_REF:-main}"
  elif [ -n "${BEFORE_REF}" ] && [ "${BEFORE_REF}" != "0000000000000000000000000000000000000000" ] && git rev-parse --verify -q "${BEFORE_REF}"; then
    ref="${BEFORE_REF}"
  elif git rev-parse --verify -q HEAD~1; then
    ref="HEAD~1"
  else
    ref=$(git hash-object -t tree /dev/null)
  fi

  echo "Comparing changes against ref: $ref"
  local pkgs
  pkgs=$(git diff --name-only "$ref" HEAD | while read -r f; do
    [ -z "$f" ] && continue
    local p="${f%%/*}"
    [ -d "$p" ] && [ -f "$p/PKGBUILD" ] && echo "$p"
  done | sort -u)

  emit_matrix "$pkgs"
}

setup_schedule_cache() {
  if [ ! -d /tmp/KaiT2en-Fedora.git ]; then
    echo "Caching KaiT2en-Fedora git repo..."
    git clone --mirror https://github.com/kaiT2en/KaiT2en-Fedora.git /tmp/KaiT2en-Fedora.git
    chmod -R a+rX /tmp/KaiT2en-Fedora.git
    git config --system url."/tmp/KaiT2en-Fedora.git".insteadOf "https://github.com/kaiT2en/KaiT2en-Fedora.git"
    git config --system url."/tmp/KaiT2en-Fedora.git".insteadOf "https://github.com/kaiT2en/KaiT2en-Fedora"
  fi
}

check_pkgver() {
  local d="$1"
  echo "== checking $d =="
  if [ "$(id -u)" -eq 0 ]; then
    if ! grep -q '^turannul:' /etc/passwd; then
      useradd -m turannul
      chown -R turannul:turannul .
    fi
    su -p turannul -c "cd '$d' && makepkg --nobuild --nodeps --noprepare --skippgpcheck"
  else
    (cd "$d" && makepkg --nobuild --nodeps --noprepare --skippgpcheck)
  fi
}

detect_schedule() {
  setup_schedule_cache
  for d in */; do
    [ -f "$d/PKGBUILD" ] || continue
    grep -q 'pkgver()' "$d/PKGBUILD" || continue
    check_pkgver "$d"
  done

  local pkgs
  pkgs=$(git status -s '*/PKGBUILD' | awk '{print $2}' | cut -d/ -f1 | sort -u)
  emit_matrix "$pkgs"
}

main() {
  setup_environment
  local mode="${1:-${EVENT_NAME:-${GITHUB_EVENT_NAME:-push}}}"

  case "$mode" in
    workflow_dispatch|manual)
      detect_manual "${TARGET:-${2:-all}}"
      ;;
    schedule)
      detect_schedule
      ;;
    push|pull_request|ci|*)
      detect_ci
      ;;
  esac
}

main "$@"
