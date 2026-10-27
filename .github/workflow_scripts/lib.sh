user=turannul

step() {
  echo "==> $1"
  "$@"
}

setup_cachy_repo() {
  sed --in-place 's/^Architecture = .*/Architecture = x86_64 x86_64_v3/' /etc/pacman.conf
  cat >> /etc/pacman.conf <<'EOF'

[cachyos-v3]
Server = https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/
SigLevel = Never

EOF
}

setup_t2_repo() {
  cat >> /etc/pacman.conf <<'EOF'

[arch-mact2]
Server = https://arch-t2.slsrepo.com/
SigLevel = Never
EOF
}

setup_my_repo() {
  cat >> /etc/pacman.conf <<'EOF'

[turann-s-place]
Server = https://turannul.github.io/KaiT2en-Arch/x86_64
SigLevel = Never
EOF
}

sync_pacman() {
  pacman --files --refresh --noconfirm
  pacman --sync --refresh --noconfirm
}

setup_repos() {
  setup_t2_repo
  setup_cachy_repo
  setup_my_repo
  sync_pacman
}

all_pkgs() {
  find . -name PKGBUILD -not -path './.git/*' -not -path './gh-pages/*' -not -path './artifacts/*' -printf '%h\n' | sed 's|^\./||' | sort --unique
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
    [ "$(pkgname_of "$d")" = "$want" ] && { printf '%s' "$d"; return; }
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
