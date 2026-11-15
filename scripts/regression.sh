#!/usr/bin/env bash
# The regression loop: renders every file in Tests/Corpus, Examples, Examples/ApiGaps and Examples/Frameworks
# with --all --scheme both --open-fonts (Apple TV for *TV* files) into OUT_DIR, one directory per source file.
#   scripts/regression.sh OUT_DIR [--jobs N] [extra render options...]
# Compare two runs with: scripts/regression.sh --compare BEFORE_DIR AFTER_DIR
# ContainersLayout (live clock) and Interactions-Loading (TimelineView) differ between runs and are skipped
# in the comparison.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = --compare ]; then
  before="$2"; after="$3"; changed=0
  while IFS= read -r file; do
    rel="${file#"$before"/}"
    case "$rel" in *ContainersLayout*|*Interactions-Loading*) continue ;; esac
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
ls Tests/Corpus/*.swift Examples/*.swift Examples/ApiGaps/*.swift Examples/Frameworks/*.swift | sort |
  xargs -P "$jobs" -I{} bash -c '
    file="$1"; shift; bin="$1"; shift; out="$1"; shift
    device=(); case "$file" in *TV*) device=(--device apple-tv) ;; esac
    dir="$out/${file%.swift}"
    if ! log=$("$bin/swiftui-screenshot" render "$file" --all --scheme both --open-fonts "${device[@]}" --out-dir "$dir" "$@" 2>&1); then
      echo "FAILED $file"; echo "$log" | tail -20
    fi' _ {} "$bin" "$out" "$@"
echo "rendered $(find "$out" -name '*.png' | wc -l | tr -d ' ') images into $out"
