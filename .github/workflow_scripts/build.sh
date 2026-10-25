#!/usr/bin/env bash
set -e

key="${GPG_PRIVATE_KEY:?GPG_PRIVATE_KEY required}"
keyid="${GPG_KEY_ID:?GPG_KEY_ID required}"

setup_t2_repo() {
  if ! grep --quiet '\[arch-mact2\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[arch-mact2]
Server = https://arch-t2.slsrepo.com/
SigLevel = Never
EOF
  fi
}

setup_my_repo() {
  if ! grep --quiet '\[turann-s-place\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[turann-s-place]
Server = https://turannul.github.io/KaiT2en-Arch/x86_64
SigLevel = Never
EOF
  fi
}

sync_pacman() {
    pacman --files --refresh --noconfirm
    pacman --sync --refresh --noconfirm
}

install_base() {
  pacman --sync --refresh --sysupgrade --noconfirm --needed base-devel git
}

install_make_depends() {
  local p="$1" pkgbuild deps dep
  pkgbuild="$p/PKGBUILD"
  if [ ! -f "$pkgbuild" ]; then
    return 1
  fi
  deps=$(cd "$p" && makepkg --printsrcinfo 2>/dev/null | awk --field-separator=' = ' '/^\t(make|check)depends(_x86_64)? = /{print $2}' | sort --unique)
  if [ -z "$deps" ]; then
    return 0
  fi
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    ! pacman --query --info "$dep" &>/dev/null && pacman --refresh --noconfirm --needed "$dep"
  done <<< "$deps"
}

disable_debug() {
  sed --in-place --regexp-extended '/^[[:space:]]*OPTIONS=/ s/(^|[[:space:](])debug\b/\1!debug/g' /etc/makepkg.conf
  echo "makepkg options: $(grep --extended-regexp '^[[:space:]]*OPTIONS=' /etc/makepkg.conf)"
}

create_user() {
  useradd --create-home turannul
  mkdir --parents "$CARGO_HOME" "$npm_config_cache"
  chown --recursive turannul:turannul "$CARGO_HOME" "$npm_config_cache"
  chown --recursive turannul:turannul .
  echo "turannul ALL=(root) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/turannul
  chmod 440 /etc/sudoers.d/turannul
  git config --global --add safe.directory "$GITHUB_WORKSPACE"
}

import_key() {
  export GNUPGHOME="$GITHUB_WORKSPACE/.gnupg"
  mkdir --parents --mode=700 "$GNUPGHOME"
  echo "$key" | gpg --batch --import
  chown --recursive turannul:turannul "$GNUPGHOME"
}

run_makepkg() {
  su --preserve-environment --command="cd '$1' && makepkg --key '$keyid' --syncdeps --noconfirm --clean --cleanbuild --force --sign" turannul
}

build_and_sign() {
  local pkgdir="${1:?package directory required}"
  echo "==> setup_t2_repo"
  setup_t2_repo
  echo "==> setup_repo"
  setup_my_repo
  echo "==> sync_pacman"
  sync_pacman
  echo "==> install_base"
  install_base
  echo "==> install_make_depends"
  install_make_depends "$pkgdir"
  echo "==> disable_debug"
  disable_debug
  echo "==> create_user"
  create_user
  echo "==> import_key"
  import_key
  echo "==> run_makepkg"
  run_makepkg "$pkgdir"
}

build_and_sign "$@"
