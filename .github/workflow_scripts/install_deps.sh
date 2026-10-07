#!/usr/bin/env bash

setup_makepkg() {
  if [ -w /etc/makepkg.conf ] && ! grep -q '!debug' /etc/makepkg.conf; then
    echo 'OPTIONS+=(!debug)' >> /etc/makepkg.conf
  fi
}

install_base() {
  pacman -Sy --noconfirm --needed base-devel git
}

install_cargo() {
  local p="$1"
  if grep -qE "['\"]cargo['\"]" "$p/PKGBUILD"; then
    echo "Installing Rust/Cargo toolchain for $p..."
    pacman -S --noconfirm --needed rust cargo

    if grep -qE "['\"]gtk4['\"]" "$p/PKGBUILD"; then
      echo "Installing GTK4 and Libadwaita for $p..."
      pacman -S --noconfirm --needed gtk4 libadwaita
    fi
    if grep -qE "['\"]lv2['\"]" "$p/PKGBUILD"; then
      echo "Installing LV2 for $p..."
      pacman -S --noconfirm --needed lv2
    fi
    if grep -qE "['\"]libinput['\"]" "$p/PKGBUILD"; then
      echo "Installing libinput and fonts for $p..."
      pacman -S --noconfirm --needed libinput adwaita-fonts
    fi
  fi
}

install_npm() {
  local p="$1"
  if grep -qE "['\"]npm['\"]" "$p/PKGBUILD"; then
    echo "Installing Node.js and graphics libraries for $p..."
    pacman -S --noconfirm --needed nodejs npm python cairo libdrm librsvg pango cava brightnessctl gcc make pkgconf
  fi
}

main() {
  set -e
  local p="${1:-}"
  [ -z "$p" ] && { echo "Package name required"; exit 1; }

  echo "Resolving dependencies for $p..."
  setup_makepkg
  install_base
  install_cargo "$p"
  install_npm "$p"
}

main "$@"
