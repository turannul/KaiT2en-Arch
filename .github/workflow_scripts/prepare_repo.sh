#!/usr/bin/env bash
set -e

: "${GPG_PRIVATE_KEY:?GPG_PRIVATE_KEY required}"
tok="${GH_TOKEN:?GH_TOKEN required}"
keyid="${GPG_KEY_ID:?GPG_KEY_ID required}"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ws="$GITHUB_WORKSPACE"
repo="${REPO_NAME:-turann-s-place}"
remote="https://actions-user:${tok}@github.com/turannul/KaiT2en-Arch.git"
updated_pkgs=""

install_tools() {
  pacman --sync --refresh --noconfirm --needed git gnupg diffutils
}

setup_git() {
  trust_git_dirs
  git config --global user.name "actions-user"
  git config --global user.email "actions-user@users.noreply.github.com"
}

clone_pages() {
  cd "$ws"
  git clone --depth 1 --branch gh-pages "$remote" gh-pages || {
    git init --initial-branch=gh-pages gh-pages
    git -C gh-pages remote add origin "$remote"
  }
  cd gh-pages
}

sync_pkgs() {
  mkdir --parents x86_64
  [ -d ../artifacts ] || return 0
  find ../artifacts -name '*.pkg.tar.zst*' -exec cp --verbose --target-directory=x86_64 {} +
}

prune_orphans() {
  local f n removed=0 total=0
  local -a keep=() orphans=()
  mapfile -t keep < <(cd "$ws" && all_pkgnames)
  if [ "${#keep[@]}" -lt 5 ]; then
    echo "prune: refusing, only ${#keep[@]} package name(s) found on main"
    return 0
  fi
  for f in x86_64/*.pkg.tar.zst; do
    [ -f "$f" ] || continue
    total=$((total + 1))
    n=$(pkgfile_name "$f")
    printf '%s\n' "${keep[@]}" | grep --quiet --line-regexp -- "$n" || orphans+=("$f")
  done
  if [ $(( ${#orphans[@]} * 2 )) -gt "$total" ]; then
    echo "prune: refusing, ${#orphans[@]} of $total archive(s) look orphaned"
    return 0
  fi
  [ "${#orphans[@]}" -gt 0 ] || { echo "prune: no orphans"; return 0; }
  for f in "${orphans[@]}"; do
    n=$(pkgfile_name "$f")
    echo "prune: $n has no PKGBUILD, dropping archive"
    rm --force --verbose "$f" "$f.sig"
    removed=$((removed + 1))
  done
  echo "pruned $removed orphaned archive(s)"
}

commit_push() {
  git diff --cached --quiet && { echo "No changes to commit on $2."; return; }
  git commit --message="$1"
  git push --set-upstream origin "$2"
}

publish_pages() {
  rm --force "x86_64/${repo}".db* "x86_64/${repo}".files*
  repo-add --sign --key "$keyid" "x86_64/${repo}.db.tar.zst" \
    $(printf '%s\n' x86_64/*.pkg.tar.zst | sort --version-sort)
  gpg --batch --armor --export "$keyid" > key.asc
  git add --all
  commit_push "Update repository [skip ci]" gh-pages
}

pkgver_of_file() {
  awk '/^pkgver=/{print $2; exit}' "$1"
}

pkgrel_of_file() {
  awk '/^pkgrel=/{print $2; exit}' "$1"
}

sync_pkgbuilds() {
  local p n dir cur new
  while IFS= read -r p; do
    n=$(pkgname_of "$(dirname "$p")")
    dir=$(find_pkg_dir "$n") || { echo "skip: no local dir for $n" >&2; continue; }
    cur="$(pkgver_of_file "$dir/PKGBUILD")-$(pkgrel_of_file "$dir/PKGBUILD")"
    new="$(pkgver_of_file "$p")-$(pkgrel_of_file "$p")"
    [ "$cur" = "$new" ] && continue
    if [ "$new" != "$(printf '%s\n%s\n' "$cur" "$new" | sort --version-sort | tail -1)" ]; then
      echo "skip: built $n ($new) is older than local ($cur)" >&2
      continue
    fi
    echo "chore: updated $dir/PKGBUILD..." >&2
    cp --force "$p" "$dir/PKGBUILD"
    updated_pkgs="${updated_pkgs:+$updated_pkgs }$n"
  done < <(find artifacts -name PKGBUILD)
  rm --recursive --force artifacts
}

pkgfile_name() {
  basename "$1" | sed --regexp-extended 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//'
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
  local pkg n latest f
  for pkg in gh-pages/x86_64/*.pkg.tar.zst; do
    [ -f "$pkg" ] || continue
    n=$(pkgfile_name "$pkg")
    latest=$(for f in gh-pages/x86_64/*.pkg.tar.zst; do
      [ -f "$f" ] || continue
      [ "$(pkgfile_name "$f")" = "$n" ] && echo "$f"
    done | sort --version-sort | tail --lines=1)
    [ "$latest" = "$pkg" ] || continue
    emit_installed "$n" "$pkg"
  done
}

commit_main() {
  local what="${updated_pkgs:+$updated_pkgs updated.}"
  git remote set-url origin "$remote"
  git add installed_files.txt $(all_pkgs | sed 's|$|/PKGBUILD|')
  commit_push "chore: ${what:-update installed_files.txt} [skip ci]" main
}

prepare_repo() {
  step install_tools
  step setup_git
  step import_key
  step clone_pages
  step sync_pkgs
  step prune_orphans
  step publish_pages
  cd "$ws"
  step sync_pkgbuilds
  step gen_installed_files
  step commit_main
}

prepare_repo
