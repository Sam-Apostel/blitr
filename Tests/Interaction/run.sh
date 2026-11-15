#!/bin/bash
# Interaction capture checks: two short scripts from Examples/Interactions.swift, run twice. The frame
# counts must match what the scripts imply and every output must be byte-identical between the runs.
# Run from the repository root after `swift build`:
#
#     Tests/Interaction/run.sh [output-directory]
set -u
cd "$(dirname "$0")/../.."
bin="$(swift build --show-bin-path)/swiftui-screenshot"
out="${1:-out/Interaction}"
failures=0
fail() { echo "FAIL  $*"; failures=$((failures + 1)); }

capture() {  # capture <run> : both scripts into $out/<run>
  local dir="$out/$1"
  rm -rf "$dir"; mkdir -p "$dir"
  "$bin" render Examples/Interactions.swift --preview Counter --open-fonts --scale 1 -o "$dir/counter.png" --json \
    --frames "$dir/counter-frames" --frames-every-step --filmstrip "$dir/counter-strip.png" \
    --steps 'tap "Increment"; tap "Increment"; tap "Decrement"; snapshot end' >"$dir/counter.json" 2>"$dir/counter.log" || fail "counter script ($1)"
  "$bin" render Examples/Interactions.swift --preview "Expanding Card" --open-fonts --scale 1 -o "$dir/card.png" --json \
    --animated "$dir/card.gif" --fps 20 --hold 0.5 --steps 'tap "Trip to Lisbon"' >"$dir/card.json" 2>"$dir/card.log" || fail "card script ($1)"
  "$bin" render Examples/Interactions.swift --preview "Expanding Card" --open-fonts --scale 1 -o "$dir/card-apng.png" --json \
    --animated "$dir/card.apng" --fps 20 --hold 0.5 --steps 'tap "Trip to Lisbon"' >/dev/null 2>&1 || fail "card APNG ($1)"
}

capture a
capture b

# Counter: start + 3 steps + the snapshot = 5 frames (PNG per step, the snapshot included).
n=$(ls "$out/a/counter-frames" | wc -l | tr -d " ")
[ "$n" = 5 ] && echo "ok    counter wrote 5 frames" || fail "counter wrote $n frames, expected 5"
grep -q '"frameCount":5' "$out/a/counter.json" && echo "ok    counter frameCount 5" || fail "counter frameCount: $(cat "$out/a/counter.json")"
# Card: the start hold, a spring of 0.74 s at 20 fps (15 frames, the last one the settled state held).
grep -q '"frameCount":16' "$out/a/card.json" && echo "ok    card frameCount 16" || fail "card frameCount: $(cat "$out/a/card.json")"
grep -q 'state changed, 15 frames' "$out/a/card.log" && echo "ok    card step log" || fail "card log: $(cat "$out/a/card.log")"
# The settled end of the animation is the plain render of the end state.
cmp -s "$out/a/card.png" "$out/a/card-apng.png" && echo "ok    end frames agree" || fail "card PNGs differ between runs with different outputs"

# Task.sleep on the virtual clock: delays within the settle time pass at once, no task is reported as
# unfinished, and a `wait` step wakes the 5 s slideshow timer (a different frame).
mkdir -p "$out/tasks"
"$bin" render Examples/TaskTiming.swift --open-fonts --scale 1 -o "$out/tasks/tasks.png" >"$out/tasks/tasks.log" 2>&1 || fail "task timing render"
"$bin" render Examples/TaskTiming.swift --open-fonts --scale 1 -o "$out/tasks/tasks-wait.png" --steps 'wait 5' >"$out/tasks/tasks-wait.log" 2>&1 || fail "task timing wait"
grep -q "did not finish" "$out/tasks/tasks.log" && fail "a .task was reported unfinished: $(cat "$out/tasks/tasks.log")" || echo "ok    sleeping tasks settle"
cmp -s "$out/tasks/tasks.png" "$out/tasks/tasks-wait.png" && fail "wait 5 did not wake the timer" || echo "ok    wait wakes sleeping tasks"

# Determinism: same input, same bytes.
for f in $(cd "$out/a" && find . -type f ! -name '*.log' ! -name '*.json' | sort); do
  cmp -s "$out/a/$f" "$out/b/$f" || fail "$f differs between two runs"
done
[ "$failures" = 0 ] && echo "ok    outputs byte-identical across runs"
exit $((failures > 0))
