#!/usr/bin/env bash

setup_arch_mact2_repo() {
  if ! grep -q '\[arch-mact2\]' /etc/pacman.conf; then
    echo "Adding arch-mact2 repository to pacman.conf..."
    cat >> /etc/pacman.conf <<'EOF'

[arch-mact2]
SigLevel = Never
Server = https://arch-t2.slsrepo.com/
EOF
    pacman -Sy --noconfirm
  fi
}

install_base() {
  pacman -Syu --noconfirm --needed base-devel git
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

install_kernel() {
  local p="$1"
  if grep -qE "['\"]linux-t2-headers['\"]" "$p/PKGBUILD"; then
    echo "Installing T2 kernel headers for $p..."
    setup_arch_mact2_repo
    pacman -S --noconfirm --needed linux-t2-headers
  elif grep -qE "['\"]linux-headers['\"]" "$p/PKGBUILD"; then
    echo "Installing kernel headers for $p..."
    pacman -S --noconfirm --needed linux-headers
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
  install_base
  install_cargo "$p"
  install_kernel "$p"
  install_npm "$p"
}

main "$@"
