setup_cachy_repo() {
  if ! grep --quiet '^Architecture.*x86_64_v3' /etc/pacman.conf; then
    sed -i 's/^Architecture = .*/Architecture = x86_64 x86_64_v3/' /etc/pacman.conf
  fi
  if ! grep --quiet '\[cachyos-v3\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[cachyos-v3]
Server = https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/
SigLevel = Never

EOF
  fi
}

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