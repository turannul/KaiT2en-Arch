#!/usr/bin/env bash

set -e
cd "$(dirname "$0")/../.."
source ".github/workflow_scripts/lib.sh"

gen_target_menu() {
  local yml=.github/workflows/pipeline.yml n targets
  sed --in-place '/^        options:/,$ { /^          - /d }' "$yml"
  targets=$(for d in $(all_pkgs); do
      case "$d" in *deprecated*) continue ;; esac
      pkgname_of "$d"
      echo
    done | sort --reverse --unique)
  targets=$(printf '%s\nall\nautodetect\n' "$targets")
  while IFS= read -r n; do
    sed --in-place "/^        options:/a\\\\          - $n" "$yml"
  done <<<"$targets"
}

gen_target_menu
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/pipeline.yml"))'
changed=$(git diff --name-only -- .github/workflows/pipeline.yml)
if [ -n "$changed" ]; then
  echo "pipeline.yml updated - commit and push it with your own credentials"
else
  echo "pipeline.yml already up to date"
fi
