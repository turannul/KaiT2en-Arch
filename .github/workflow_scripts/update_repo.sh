#!/usr/bin/env bash
set -e

git config --global --add safe.directory '*' 2>/dev/null || true

clone_pages() {
  local ws="$1" tok="$2"

  cd "$ws"
  if git clone --depth 1 --branch gh-pages "https://actions-user:${tok}@github.com/turannul/KaiT2en-Arch.git" gh-pages; then
    cd gh-pages
  else
    mkdir -p gh-pages && cd gh-pages
    git init -b gh-pages
    git remote add origin "https://actions-user:${tok}@github.com/turannul/KaiT2en-Arch.git"
  fi
}

sync_pkgs() {
  mkdir -p x86_64
  for pkg in $(find ../artifacts -name '*.pkg.tar.zst'); do
    [ -f "$pkg" ] || continue
    case "$(basename "$pkg")" in *-debug-*) continue ;; esac
    local n
    n=$(basename "$pkg" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
    echo "Updating $n in gh-pages..."

    for old in x86_64/*.pkg.tar.zst; do
      [ -f "$old" ] || continue
      local old_n
      old_n=$(basename "$old" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
      [ "$old_n" = "$n" ] && rm -f "$old"
    done
    cp "$pkg" x86_64/
  done
}

publish_pages() {
  local repo="$1"

  repo-add "x86_64/${repo}.db.tar.gz" x86_64/*.pkg.tar.zst

  git config user.name "actions-user"
  git config user.email "actions-user@users.noreply.github.com"
  git add -A
  if git diff --cached --quiet; then
    echo "No changes on gh-pages."
  else
    git commit -m "Update repository [skip ci]"
    git push -u origin gh-pages
  fi
}

sync_pkgbuilds() {
  local updated=""
  for p in $(find artifacts -name PKGBUILD); do
    [ -f "$p" ] || continue
    local n dir=""
    n=$(grep -E '^pkgname=' "$p" | cut -d= -f2 | tr -d "'\"()")
    if [ -d "$n" ]; then
      dir="$n"
    else
      local c
      c=$(basename "$(dirname "$p")" | sed 's/^pkg-//')
      [ -d "$c" ] && dir="$c"
    fi
    if [ -n "$dir" ] && [ -f "$dir/PKGBUILD" ]; then
      if [ "$(sha256sum < "$p")" != "$(sha256sum < "$dir/PKGBUILD")" ]; then
        echo "chore: updated $dir/PKGBUILD..."
        cp -f "$p" "$dir/PKGBUILD"
        updated="${updated:+$updated, }$dir"
      fi
    fi
  done
  rm -rf artifacts
  echo "$updated"
}

gen_installed_files() {
  : > installed_files.txt
  for pkg in gh-pages/x86_64/*.pkg.tar.zst; do
    [ -f "$pkg" ] || continue
    case "$(basename "$pkg")" in *-debug-* | *-meta-*) continue ;; esac
    local n
    n=$(basename "$pkg" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
    {
      echo "# $n"
      tar -tf "$pkg" | grep -vE '^\.(PKGINFO|MTREE|BUILDINFO|INSTALL)$|/$'
      echo
    } >> installed_files.txt
  done
}

commit_main() {
  local tok="$1" updated="$2"

  git config user.name "actions-user"
  git config user.email "actions-user@users.noreply.github.com"
  git remote set-url origin "https://actions-user:${tok}@github.com/turannul/KaiT2en-Arch.git"
  git add '*/PKGBUILD' installed_files.txt

  if git diff --cached --quiet; then
    echo "No changes to commit on main."
  else
    local msg
    if [ -n "$updated" ]; then
      msg="chore: $updated updated. [skip ci]"
    else
      msg="chore: update installed_files.txt [skip ci]"
    fi
    git commit -m "$msg"
    git push origin main
  fi
}

main() {
  local ws="${GITHUB_WORKSPACE:-$(pwd)}"
  local repo="${REPO_NAME:-turann-s-place}"
  local tok="${GH_TOKEN:-}"

  git config --global --add safe.directory "$ws"
  git config --global --add safe.directory "$ws/gh-pages"

  clone_pages "$ws" "$tok"
  sync_pkgs
  publish_pages "$repo"

  cd "$ws"
  local updated
  updated=$(sync_pkgbuilds)
  gen_installed_files
  commit_main "$tok" "$updated"
}

main "$@"
