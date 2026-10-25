#!/usr/bin/env bash
set -e

ws="${GITHUB_WORKSPACE:-$(pwd)}"
repo="${REPO_NAME:-turann-s-place}"
tok="${GH_TOKEN:?GH_TOKEN required}"
keyid="${GPG_KEY_ID:?GPG_KEY_ID required}"
updated_pkgs=""

install_tools() {
  pacman --sync --refresh --noconfirm --needed git gnupg
}

setup_git() {
  git config --global --add safe.directory '*'
}

import_key() {
  local key="${GPG_PRIVATE_KEY:?GPG_PRIVATE_KEY required}"
  export GNUPGHOME="$ws/.gnupg"
  mkdir --parents --mode=700 "$GNUPGHOME"
  echo "$key" | gpg --batch --import
}

clone_pages() {
  local ws="$1" tok="$2"
  cd "$ws"
  if git clone --depth 1 --branch gh-pages "https://actions-user:${tok}@github.com/turannul/KaiT2en-Arch.git" gh-pages; then
    cd gh-pages
  else
    mkdir --parents gh-pages && cd gh-pages
    git init --initial-branch=gh-pages
    git remote add origin "https://actions-user:${tok}@github.com/turannul/KaiT2en-Arch.git"
  fi
}

sync_pkgs() {
  mkdir --parents x86_64
  local pkg n
  while IFS= read -r pkg; do
    [ -f "$pkg" ] || continue
    n=$(basename "$pkg" | sed --regexp-extended 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
    echo "Updating $n in gh-pages..."
    cp "$pkg" x86_64/
    if [ -f "${pkg}.sig" ]; then
      cp "${pkg}.sig" x86_64/
    fi
  done < <(find ../artifacts -name '*.pkg.tar.zst')
}

publish_pages() {
  local repo="$1"
  rm --force "x86_64/${repo}".db* "x86_64/${repo}".files*
  repo-add --sign --key "${keyid}" "x86_64/${repo}.db.tar.zst" \
    $(printf '%s\n' x86_64/*.pkg.tar.zst | sort --version-sort)
  gpg --batch --armor --export "${keyid}" > key.asc
  git config user.name "actions-user"
  git config user.email "actions-user@users.noreply.github.com"
  git add --all
  if git diff --cached --quiet; then
    echo "No changes on gh-pages."
  else
    git commit --message="Update repository [skip ci]"
    git push --set-upstream origin gh-pages
  fi
}

find_pkgdir() {
  local want="$1" p d n
  while IFS= read -r p; do
    d=$(dirname "$p" | sed 's|^\./||')
    n=$(grep --extended-regexp '^pkgname=' "$d/PKGBUILD" | cut --delimiter='=' --fields=2 | tr --delete "'\"()")
    if [ "$n" = "$want" ]; then
      echo "$d"
      return 0
    fi
  done < <(find . -name PKGBUILD -not -path './gh-pages/*' -not -path './artifacts/*')
  return 1
}

sync_pkgbuilds() {
  updated_pkgs=""
  local p n dir
  while IFS= read -r p; do
    [ -f "$p" ] || continue
    n=$(grep --extended-regexp '^pkgname=' "$p" | cut --delimiter='=' --fields=2 | tr --delete "'\"()")
    if ! dir=$(find_pkgdir "$n"); then
      echo "skip: no local dir for $n" >&2
      continue
    fi
    if [ -f "$dir/PKGBUILD" ]; then
      if [ "$(sha256sum < "$p")" != "$(sha256sum < "$dir/PKGBUILD")" ]; then
        echo "chore: updated $dir/PKGBUILD..." >&2
        cp --force "$p" "$dir/PKGBUILD"
        updated_pkgs="${updated_pkgs:+$updated_pkgs }$n"
      fi
    fi
  done < <(find artifacts -name PKGBUILD)
  rm --recursive --force artifacts
}

emit_installed() {
  local files
  files=$(tar --list --file="$2" | grep --invert-match --extended-regexp '^\.(PKGINFO|MTREE|BUILDINFO|INSTALL)$|/$' || true)
  [ -n "$files" ] || return 0
  {
    echo "# $1"
    printf '%s\n' "$files"
    echo
  } >> installed_files.txt
}

gen_installed_files() {
  : > installed_files.txt
  local pkg n latest f m
  for pkg in gh-pages/x86_64/*.pkg.tar.zst; do
    [ -f "$pkg" ] || continue
    n=$(basename "$pkg" | sed --regexp-extended 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
    latest=$(for f in gh-pages/x86_64/*.pkg.tar.zst; do
      [ -f "$f" ] || continue
      m=$(basename "$f" | sed --regexp-extended 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
      [ "$m" = "$n" ] && echo "$f"
    done | sort --version-sort | tail --lines=1)
    [ "$latest" = "$pkg" ] || continue
    emit_installed "$n" "$pkg"
  done
}

commit_main() {
  local tok="$1" updated="$2"
  git config user.name "actions-user"
  git config user.email "actions-user@users.noreply.github.com"
  git remote set-url origin "https://actions-user:${tok}@github.com/turannul/KaiT2en-Arch.git"
  git add installed_files.txt $(find . -name PKGBUILD -not -path './gh-pages/*' -not -path './artifacts/*')
  if git diff --cached --quiet; then
    echo "No changes to commit on main."
  else
    local msg
    if [ -n "$updated" ]; then
      msg="chore: $updated updated. [skip ci]"
    else
      msg="chore: update installed_files.txt [skip ci]"
    fi
    git commit --message="$msg"
    git push origin main
  fi
}

prepare_repo() {
  echo "==> install_tools"
  install_tools
  echo "==> setup_git"
  setup_git
  echo "==> import_key"
  import_key
  echo "==> clone_pages"
  clone_pages "$ws" "$tok"
  echo "==> sync_pkgs"
  sync_pkgs
  echo "==> publish_pages"
  publish_pages "$repo"
  cd "$ws"
  echo "==> sync_pkgbuilds"
  sync_pkgbuilds
  echo "==> gen_installed_files"
  gen_installed_files
  echo "==> commit_main"
  commit_main "$tok" "$updated_pkgs"
}

prepare_repo
