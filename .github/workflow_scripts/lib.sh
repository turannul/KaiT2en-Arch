export user=turannul

step() {
  local start=$SECONDS
  echo "==> $1"
  "$@"
  echo "    $1 $((SECONDS - start))s"
}

add_repo() {
  grep --quiet --fixed-strings "[$1]" /etc/pacman.conf && return
  printf '\n[%s]\nServer = %s\nSigLevel = Never\n' "$1" "$2" >> /etc/pacman.conf
}

add_repo_before_arch() {
  local name="$1"
  local server="$2"
  local tmp
  grep --quiet --fixed-strings "[$name]" /etc/pacman.conf && return

  tmp=$(mktemp)

  awk -v name="$name" -v server="$server" '
    /^\[core\]$/ && !added {
      print "[" name "]"
      print "Server = " server
      print "SigLevel = Never"
      print ""
      added=1
    }
    { print }
  ' /etc/pacman.conf > "$tmp"

  cat "$tmp" > /etc/pacman.conf
  rm --force "$tmp"
}

setup_cachy_repo() {
  sed --in-place 's/^Architecture = .*/Architecture = x86_64 x86_64_v3/' /etc/pacman.conf
  add_repo_before_arch cachyos-v3 https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/
  add_repo_before_arch cachyos-core-v3 https://mirror.cachyos.org/repo/x86_64_v3/cachyos-core-v3/
  add_repo_before_arch cachyos-extra-v3 https://mirror.cachyos.org/repo/x86_64_v3/cachyos-extra-v3/
  add_repo_before_arch cachyos https://mirror.cachyos.org/repo/x86_64/cachyos/
}

setup_t2_repo() {
  add_repo arch-mact2 https://mirror.funami.tech/arch-mact2/os/x86_64/
}

setup_my_repo() {
  add_repo turann-s-place https://turannul.github.io/KaiT2en-Arch/x86_64
}

sync_pacman() {
  pacman --files --refresh --noconfirm
  pacman --sync --refresh --noconfirm
}

setup_repos() {
  setup_my_repo
  sync_pacman
}

setup_repos_for_package() {
  local pkg refresh=0
  pkg=$(pkgname_of "$1")

  if [[ "$pkg" == *-t2 ]]; then
    setup_t2_repo
    refresh=1
  fi

  if [[ "$pkg" == *-cachy ]]; then
    setup_cachy_repo
    refresh=1
  fi

  if (( refresh )); then
    sync_pacman
  fi
}

all_pkgs() {
  find . -name PKGBUILD -not -path './.git/*' -not -path './gh-pages/*' -not -path './artifacts/*' -printf '%h\n' | sed 's|^\./||' | sort --unique
}

all_pkgnames() {
  find . -name PKGBUILD -not -path './.git/*' -not -path './gh-pages/*' -not -path './artifacts/*' -print0 | xargs --null sed --quiet 's/^[[:space:]]*pkgname=//p' | tr --delete "'\"" | tr '(), ' '\n\n\n\n\n' | sed '/^[[:space:]]*$/d' | sort --unique
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
  local want="$1" d
  for d in $(all_pkgs); do
    if [ "$(pkgname_of "$d")" = "$want" ]; then
      printf '%s' "$d"
      return
    fi
  done
  return 1
}

trust_git_dirs() {
  git config --global --add safe.directory '*'
}

create_user() {
  useradd --create-home "$user"
  chown --recursive "$user:$user" .
  trust_git_dirs
}

makepkg_as_user() {
  local d="$1"
  shift
  su --preserve-environment --command="cd $(printf '%q' "$d") && makepkg $(printf '%q ' "$@")" "$user"
}

import_key() {
  export GNUPGHOME="$GITHUB_WORKSPACE/.gnupg"
  mkdir --parents --mode=700 "$GNUPGHOME"
  gpg --batch --import <<<"${GPG_PRIVATE_KEY:?GPG_PRIVATE_KEY required}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    setup_repos)
      step setup_repos
      ;;
    setup_repos_for_package)
      step setup_repos_for_package "${2:?package directory required}"
      ;;
    *)
      echo "usage: bash lib.sh {setup_repos|setup_repos_for_package <package-dir>}" >&2
      exit 1
      ;;
  esac
fi
