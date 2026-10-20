#!/usr/bin/env bash

setup_environment() {
  set -e
  git config --global --add safe.directory '*'
}

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
  local KEEP=20
  mkdir -p x86_64
  for pkg in $(find ../artifacts -name '*.pkg.tar.zst'); do
    [ -f "$pkg" ] || continue
    local n
    n=$(basename "$pkg" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
    echo "Updating $n in gh-pages..."
    cp "$pkg" x86_64/
    local matches
    matches=$(for old in x86_64/*.pkg.tar.zst; do
      [ -f "$old" ] || continue
      case "$(basename "$old")" in *-debug-*) continue ;; esac
      local old_n
      old_n=$(basename "$old" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
      [ "$old_n" = "$n" ] && echo "$old"
    done | sort -V)
    local count
    count=$(printf '%s\n' "$matches" | grep -c .)
    while [ "$count" -gt "$KEEP" ]; do
      rm -f "$(printf '%s\n' "$matches" | sed -n '1p')"
      matches=$(printf '%s\n' "$matches" | sed '1d')
      count=$((count - 1))
    done
  done
}

publish_pages() {
  local repo="$1"

  repo-add "x86_64/${repo}.db.tar.gz" $(printf '%s\n' x86_64/*.pkg.tar.zst | sort -V)

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

find_pkgdir() {
  local want="$1" p d n
  for p in $(find . -name PKGBUILD -not -path './gh-pages/*' -not -path './artifacts/*'); do
    d=$(dirname "$p" | sed 's|^\./||')
    n=$(grep -E '^pkgname=' "$d/PKGBUILD" | cut -d= -f2 | tr -d "'\"()")
    [ "$n" = "$want" ] && { echo "$d"; return 0; }
  done
  return 1
}

sync_pkgbuilds() {
  local updated=""
  for p in $(find artifacts -name PKGBUILD); do
    [ -f "$p" ] || continue
    local n dir=""
    n=$(grep -E '^pkgname=' "$p" | cut -d= -f2 | tr -d "'\"()")
    if ! dir=$(find_pkgdir "$n"); then
      echo "skip: no local dir for $n" >&2
      continue
    fi
    if [ -f "$dir/PKGBUILD" ]; then
      if [ "$(sha256sum < "$p")" != "$(sha256sum < "$dir/PKGBUILD")" ]; then
        echo "chore: updated $dir/PKGBUILD..." >&2
        cp -f "$p" "$dir/PKGBUILD"
        updated="${updated:+$updated, }$dir"
      fi
    fi
  done
  rm -rf artifacts
  echo "$updated"
}

emit_installed() {
  {
    echo "# $1"
    tar -tf "$2" | grep -vE '^\.(PKGINFO|MTREE|BUILDINFO|INSTALL)$|/$'
    echo
  } >> installed_files.txt
}

gen_installed_files() {
  : > installed_files.txt
  for pkg in gh-pages/x86_64/*.pkg.tar.zst; do
    [ -f "$pkg" ] || continue
    case "$(basename "$pkg")" in *-debug-* | *-meta-*) continue ;; esac
    local n
    n=$(basename "$pkg" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
    local latest
    latest=$(for f in gh-pages/x86_64/*.pkg.tar.zst; do
      [ -f "$f" ] || continue
      local m
      m=$(basename "$f" | sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$//')
      [ "$m" = "$n" ] && echo "$f"
    done | sort -V | tail -n 1)
    [ "$latest" = "$pkg" ] || continue
    emit_installed "$n" "$pkg"
  done
}

fmt_upd() {
  local input="$1"
  if [ -z "$input" ]; then
    echo ""
    return 0
  fi
  local -a parts=()
  IFS=',' read -ra parts <<< "$input"
  local parents="" i d parent
  for i in "${!parts[@]}"; do
    d="$(echo "${parts[$i]}" | sed 's/^ *//;s/ *$//')"
    parts[$i]="$d"
    if [[ "$d" == */* ]]; then
      parent="${d%%/*}"
    else
      parent="$d"
    fi
    case " $parents " in
      *" $parent "*) ;;
      *) parents="$parents $parent" ;;
    esac
  done
  parents="$(echo "$parents" | sed 's/^ *//')"
  local result="" members base
  for parent in $parents; do
    members=""
    for i in "${!parts[@]}"; do
      d="${parts[$i]}"
      if [[ "$d" == "$parent" ]]; then
        base="$d"
      elif [[ "$d" == "$parent"/* ]]; then
        base="${d#*/}"
      else
        continue
      fi
      if [ -z "$members" ]; then
        if [[ "$d" == */* ]]; then
          members="$parent/$base"
        else
          members="$base"
        fi
      else
        members="$members $base"
      fi
    done
    if [ -z "$result" ]; then
      result="$members"
    else
      result="$result, $members"
    fi
  done
  echo "$result"
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
      msg="chore: $(fmt_upd "$updated") updated. [skip ci]"
    else
      msg="chore: update installed_files.txt [skip ci]"
    fi
    git commit -m "$msg"
    git push origin main
  fi
}

main() {
  setup_environment

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
