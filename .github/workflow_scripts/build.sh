#!/usr/bin/env bash
set -e

: "${GPG_PRIVATE_KEY:?GPG_PRIVATE_KEY required}"
keyid="${GPG_KEY_ID:?GPG_KEY_ID required}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_base() {
  pacman --sync --refresh --sysupgrade --noconfirm --needed base-devel git
}

disable_debug() {
  sed --in-place --regexp-extended '/^[[:space:]]*OPTIONS=/ s/(^|[[:space:](])debug\b/\1!debug/g' /etc/makepkg.conf
  echo "makepkg options: $(grep --extended-regexp '^[[:space:]]*OPTIONS=' /etc/makepkg.conf)"
}

grant_pacman() {
  echo "$user ALL=(root) NOPASSWD: /usr/bin/pacman" > "/etc/sudoers.d/$user"
  chmod 440 "/etc/sudoers.d/$user"
}

run_makepkg() {
  makepkg_as_user "$1" --key "$keyid" --syncdeps --noconfirm --clean --cleanbuild --force --sign
}

build_and_sign() {
  local pkgdir="${1:?package directory required}"
  step setup_repos
  step install_base
  step disable_debug
  step import_key
  step create_user
  step grant_pacman
  step run_makepkg "$pkgdir"
}

build_and_sign "$@"
