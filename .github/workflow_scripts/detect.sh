#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_environment() {
    setup_my_repo
    setup_cachy_repo
    setup_t2_repo
    sync_pacman
    pacman --sync --refresh --noconfirm git nodejs
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
    out "packages=[]"
    return 0
  fi

  echo "Packages to build:"
  echo "$pkgs"

  local matrix
  matrix="[$(echo "$pkgs" | awk 'NF { if (n++) printf ","; a=$1; gsub("/", "-", a); printf "{\"dir\":\"%s\",\"artifact\":\"pkg-%s\"}", $1, a }')]"
  out "packages=$matrix"
}

all_pkgs() {
  find . -name PKGBUILD -not -path './.git/*' | while read -r p; do
    dirname "$p" | sed 's|^\./||'
  done | sort --unique
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

pkgname_of() {
  local d="$1" n
  n=$(sed --quiet 's/^[[:space:]]*pkgname=//p' "$d/PKGBUILD" | head --lines=1)
  n=${n#(}
  n=${n%)}
  n=${n%%[[:space:]]*}
  n=$(printf '%s' "$n" | tr --delete "'\"")
  printf '%s' "$n"
}

find_pkg_dir() {
  local want="$1" p d
  while IFS= read -r p; do
    d=$(dirname "$p" | sed 's|^\./||')
    if [ "$(pkgname_of "$d")" = "$want" ]; then
      printf '%s' "$d"
      return 0
    fi
  done < <(find . -name PKGBUILD -not -path './.git/*' | sort)
  return 1
}

pkgver_of() {
  local d="$1" v
  v=$(cd "$d" && makepkg --printsrcinfo 2>/dev/null | awk --field-separator=' = ' '/^[[:space:]]*pkgver = /{print $2; exit}')
  if [ -z "$v" ]; then
    v=$(sed --quiet 's/^[[:space:]]*pkgver=//p' "$d/PKGBUILD" | head --lines=1)
    v=$(printf '%s' "$v" | tr --delete "'\"[:space:]")
  fi
  printf '%s' "$v"
}

run_makepkg_nobuild() {
  local d="$1"
  if [ "$(id --user)" -eq 0 ]; then
    if ! grep --quiet '^turannul:' /etc/passwd; then
      useradd --create-home turannul
      chown --recursive turannul:turannul .
    fi
    su --preserve-environment --command="cd '$d' && makepkg --nobuild --cleanbuild --nodeps --noprepare --skippgpcheck" turannul </dev/null
  else
    (cd "$d" && makepkg --nobuild --cleanbuild --nodeps --noprepare --skippgpcheck) </dev/null
  fi
}

check_pkgver() {
  local d="$1" before after tmp
  echo "== checking $d =="

  before=$(pkgver_of "$d")
  if [ -z "$before" ]; then
    echo "WARNING: cannot read pkgver for $d, skipping."
    return 1
  fi

  tmp=$(mktemp)
  cp "$d/PKGBUILD" "$tmp"

  if ! run_makepkg_nobuild "$d"; then
    echo "WARNING: pkgver check failed for $d, skipping."
    cp "$tmp" "$d/PKGBUILD"
    rm --force "$tmp"
    return 1
  fi

  after=$(pkgver_of "$d")
  if [ -z "$after" ]; then
    echo "WARNING: cannot determine expected pkgver for $d, skipping."
    cp "$tmp" "$d/PKGBUILD"
    rm --force "$tmp"
    return 1
  fi

  echo "   committed: $before"
  echo "   expected:  $after"

  if [ "$before" = "$after" ]; then
    cp "$tmp" "$d/PKGBUILD"
    rm --force "$tmp"
    return 1
  fi

  echo "   -> outdated"
  rm --force "$tmp"
  return 0
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
  local -a pkgbuilds=()
  local p d result=""

  mapfile -t pkgbuilds < <(find . -name PKGBUILD -not -path './.git/*' | sort)
  for p in "${pkgbuilds[@]}"; do
    d=$(dirname "$p" | sed 's|^\./||')
    grep --quiet 'pkgver()' "$d/PKGBUILD" || continue
    if check_pkgver "$d" >&2; then
      result="${result:+$result$'\n'}$d"
    fi
  done

  printf '%s' "$result"
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
