#!/usr/bin/env bash
# The regression loop: renders every .swift file under Tests/Corpus and Examples
# with --all --scheme both --open-fonts (Apple TV for *TV* files) into OUT_DIR, one directory per source file.
# Every render is at the same moment and time zone, so clocks and timelines draw the same on every run and host.
#   scripts/regression.sh OUT_DIR [--jobs N] [extra render options...]
# Compare two runs with: scripts/regression.sh --compare BEFORE_DIR AFTER_DIR
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = --compare ]; then
  before="$2"; after="$3"; changed=0
  while IFS= read -r file; do
    rel="${file#"$before"/}"
    if [ ! -f "$after/$rel" ]; then echo "missing  $rel"; changed=1
    elif ! cmp -s "$file" "$after/$rel"; then echo "changed  $rel"; changed=1; fi
  done < <(find "$before" -name '*.png' | sort)
  while IFS= read -r file; do
    rel="${file#"$after"/}"; [ -f "$before/$rel" ] || { echo "new      $rel"; changed=1; }
  done < <(find "$after" -name '*.png' | sort)
  [ "$changed" = 0 ] && echo "identical"
  exit 0
fi

out="${1:?usage: scripts/regression.sh OUT_DIR [--jobs N] [render options...]}"; shift
jobs=4
if [ "${1:-}" = --jobs ]; then jobs="$2"; shift 2; fi
bin="$(cd "$root" && swift build --show-bin-path)"
mkdir -p "$out"
cd "$root"
find Tests/Corpus Examples -name '*.swift' | sort |
  xargs -P "$jobs" -I{} bash -c '
    file="$1"; shift; bin="$1"; shift; out="$1"; shift
    device=(); case "$file" in *TV*) device=(--device apple-tv) ;; esac
    dir="$out/${file%.swift}"
    if ! log=$("$bin/blitr" render "$file" --all --scheme both --open-fonts --date 2026-06-01T09:41:00Z --time-zone UTC "${device[@]}" --out-dir "$dir" "$@" 2>&1); then
      echo "FAILED $file"; echo "$log" | tail -20; mkdir -p "$dir"; touch "$dir/FAILED"
    fi' _ {} "$bin" "$out" "$@"
echo "rendered $(find "$out" -name '*.png' | wc -l | tr -d ' ') images into $out"
# A file that failed to render is a regression.
if [ -n "${REGRESSION_STRICT:-}" ] && find "$out" -name FAILED | grep -q .; then exit 1; fi
