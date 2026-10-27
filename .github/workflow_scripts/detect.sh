#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_environment() {
    setup_repos
    pacman --sync --refresh --noconfirm git nodejs
    set -e
    create_user
}

out() {
  echo "$1" >> "$GITHUB_OUTPUT"
}

emit_matrix() {
  echo "Packages to build:"
  echo "${1:-none}"
  out "packages=[$(awk 'NF { if (n++) printf ","; a=$1; gsub("/", "-", a); printf "{\"dir\":\"%s\",\"artifact\":\"pkg-%s\"}", $1, a }' <<<"$1")]"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

pkgver_of() {
  makepkg_as_user "$1" --printsrcinfo </dev/null | awk --field-separator=' = ' '/^[[:space:]]*pkgver = /{print $2}'
}

run_makepkg_nobuild() {
  makepkg_as_user "$1" --nobuild --cleanbuild --nodeps --noprepare --skippgpcheck </dev/null >/dev/null 2>&1
}

# return: 0 = outdated, 1 = up to date, 2 = error
check_pkgver() {
  local d="$1" local_ver upstream_ver
  echo "== checking $d =="

  local_ver=$(pkgver_of "$d")
  run_makepkg_nobuild "$d" && upstream_ver=$(pkgver_of "$d")

  echo "   local: ${local_ver:-?}"
  echo "   upstream: ${upstream_ver:-?}"

  [ -n "$local_ver" ] && [ -n "$upstream_ver" ] || { echo "   -> error"; return 2; }
  [ "$local_ver" != "$upstream_ver" ] || { echo "   -> up to date"; return 1; }

  echo "   -> outdated"
}

setup_upstream_cache() {
  local cache=/tmp/KaiT2en-Fedora.git
  if [ ! -d "$cache" ]; then
    echo "Caching KaiT2en-Fedora git repo..." >&2
    git clone --mirror https://github.com/kaiT2en/KaiT2en-Fedora.git "$cache"
    chmod --recursive a+rX "$cache"
  else
    echo "Refreshing KaiT2en-Fedora git cache..." >&2
    git --git-dir="$cache" remote update --prune
  fi
  git config --system --replace-all url."$cache".insteadOf "https://github.com/kaiT2en/KaiT2en-Fedora.git"
  git config --system --add url."$cache".insteadOf "https://github.com/kaiT2en/KaiT2en-Fedora"
}

outdated_pkgs() {
  setup_upstream_cache
  local d rc
  for d in $(all_pkgs); do
    grep --quiet 'pkgver()' "$d/PKGBUILD" || continue
    rc=0
    check_pkgver "$d" >&2 || rc=$?
    case $rc in
      0) echo "$d" ;;
      2) echo "::warning::version check failed for $d" >&2 ;;
    esac
  done
}

changed_pkgs() {
  local ref="$1"
  if [ -z "$ref" ] || [ "$ref" = "0000000000000000000000000000000000000000" ] || ! git rev-parse --verify --quiet "$ref" >/dev/null; then
    if git rev-parse --verify --quiet HEAD~1 >/dev/null; then
      ref="HEAD~1"
    else
      ref=$(git hash-object -t tree /dev/null)
    fi
  fi

  echo "Comparing changes against ref: $ref" >&2
  git diff --name-only "$ref" HEAD | while read -r f; do
    [ -z "$f" ] && continue
    local d
    d=$(dirname "$f")
    [ -f "$d/PKGBUILD" ] && echo "$d"
  done | sort --unique
}

detect_changed() {
  local ref="origin/${BASE_REF:-main}"
  if ! git rev-parse --verify --quiet "$ref" >/dev/null; then
    echo "Fetching $ref..."
    git fetch --no-tags origin "+${BASE_REF:-main}:${ref}" || true
  fi
  emit_matrix "$(changed_pkgs "$ref")"
}

detect_outdated() {
  emit_matrix "$(outdated_pkgs)"
}

detect_manual() {
  local t p d valid="" inv=""
  t=$(trim "${TARGET:-${1:-}}")

  if [ -z "$t" ]; then
    setup_environment
    echo "No target given, checking all packages for outdated versions..."
    detect_outdated
    return
  fi

  if [ "$t" = "all" ]; then
    emit_matrix "$(all_pkgs)"
    return
  fi

  for p in ${t//,/ }; do
    p=$(trim "$p")
    [ -z "$p" ] && continue
    if [ "$p" = "all" ]; then
      emit_matrix "$(all_pkgs)"
      return
    fi
    if d=$(find_pkg_dir "$p"); then
      valid="${valid:+$valid$'\n'}$d"
    elif [ -d "$p" ] && [ -f "$p/PKGBUILD" ]; then
      valid="${valid:+$valid$'\n'}$p"
    else
      inv="${inv:+$inv, }$p"
    fi
  done
  if [ -n "$inv" ]; then
    echo "Package(s) not found: $inv"
  fi
  if [ -z "$valid" ]; then
    out "packages=[]"
    return
  fi
  emit_matrix "$(printf '%s\n' "$valid" | sort --unique)"
}

main() {
  local mode="${1:-${EVENT_NAME:-${GITHUB_EVENT_NAME:-push}}}"

  case "$mode" in
    workflow_dispatch|manual)
      detect_manual "${TARGET:-${2:-}}"
      ;;
    schedule)
      setup_environment
      detect_outdated
      ;;
    pull_request)
      setup_environment
      detect_changed
      ;;
    push|ci|*)
      setup_environment
      detect_outdated
      ;;
  esac
}

main "$@"
