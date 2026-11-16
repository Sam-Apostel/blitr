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

# Device state from the command line: --locale sets formats and the currency, --location grants access and reports it.
mkdir -p "$out/state"
"$bin" render Examples/DeviceState.swift --open-fonts --layout fit -o "$out/state/us.png" --accessibility-tree "$out/state/us.json" >/dev/null 2>&1 || fail "device state render"
"$bin" render Examples/DeviceState.swift --open-fonts --layout fit --locale nl_BE --location 51.0543,3.7174 -o "$out/state/be.png" --accessibility-tree "$out/state/be.json" >/dev/null 2>&1 || fail "device state render with flags"
grep -q '1,234.50' "$out/state/us.json" && grep -q 'not determined' "$out/state/us.json" && echo "ok    default device state" || fail "default device state: $(grep -o '"label": "[^"]*"' "$out/state/us.json" | head -4)"
grep -q '1.234,50' "$out/state/be.json" && grep -q '51.0543, 3.7174' "$out/state/be.json" && echo "ok    --locale and --location" || fail "--locale/--location: $(grep -o '"label": "[^"]*"' "$out/state/be.json" | head -4)"

# --crop: one part of the screen, by rectangle in points or by an element's label, at the device's scale.
"$bin" render Tests/Corpus/01_Settings.swift --open-fonts -o "$out/state/crop-rect.png" --crop 0,180,393,200 >"$out/state/crop.log" 2>&1 || fail "crop render"
grep -q "crop-rect.png  1179x600" "$out/state/crop.log" && echo "ok    --crop by rectangle" || fail "--crop by rectangle: $(cat "$out/state/crop.log")"
"$bin" render Tests/Corpus/01_Settings.swift --open-fonts -o "$out/state/crop-label.png" --crop "Airplane Mode" --crop-padding 4 >"$out/state/crop2.log" 2>&1 && echo "ok    --crop by label" || fail "--crop by label: $(cat "$out/state/crop2.log")"

# AsyncImage of a file URL draws the image, at its scale (the network is not needed).
cat > "$out/state/async.swift" <<SWIFT
import SwiftUI
struct AsyncFile: View {
    var body: some View {
        AsyncImage(url: URL(fileURLWithPath: "$PWD/docs/images/screens-1.png"), scale: 2)
            .accessibilityIdentifier("photo")
    }
}
#Preview { AsyncFile() }
SWIFT
"$bin" render "$out/state/async.swift" --open-fonts --layout fit --scale 1 -o "$out/state/async.png" >"$out/state/async.log" 2>&1 || fail "AsyncImage render: $(cat "$out/state/async.log")"
half=$(python3 -c "import struct;d=open('docs/images/screens-1.png','rb').read(24);w,h=struct.unpack('>II',d[16:24]);print(f'{w//2}x')")
grep -q "async.png  $half" "$out/state/async.log" && echo "ok    AsyncImage draws a file URL at its scale" || fail "AsyncImage file URL: expected $half, got $(cat "$out/state/async.log")"

# Task.sleep on the virtual clock: delays within the settle time pass at once, no task is reported as
# unfinished, and a `wait` step wakes the 5 s slideshow timer (a different frame).
mkdir -p "$out/tasks"
"$bin" render Examples/TaskTiming.swift --open-fonts --scale 1 -o "$out/tasks/tasks.png" --accessibility-tree "$out/tasks/tasks.json" >"$out/tasks/tasks.log" 2>&1 || fail "task timing render"
"$bin" render Examples/TaskTiming.swift --open-fonts --scale 1 -o "$out/tasks/tasks-wait.png" --steps 'wait 5' >"$out/tasks/tasks-wait.log" 2>&1 || fail "task timing wait"
grep -q "did not finish" "$out/tasks/tasks.log" && fail "a .task was reported unfinished: $(cat "$out/tasks/tasks.log")" || echo "ok    sleeping tasks settle"
cmp -s "$out/tasks/tasks.png" "$out/tasks/tasks-wait.png" && fail "wait 5 did not wake the timer" || echo "ok    wait wakes sleeping tasks"
# A sleep called on a clock directly is virtual too, and a session with its own configuration is offline.
grep -q 'after 1 s, Done' "$out/tasks/tasks.json" && echo "ok    clock.sleep is virtual" || fail "clock.sleep(for:) did not finish: $(cat "$out/tasks/tasks.json" | head -c 400)"
[ "$(grep -o 'Offline' "$out/tasks/tasks.json" | wc -l | tr -d ' ')" -ge 2 ] && echo "ok    own sessions are offline" || fail "a session with its own configuration was not offline"

# Device frames: --frame wraps the screenshot, every frame and the filmstrip cells (iPhone 16 at 1x:
# 393x852 screen, 18pt of border and band per side, 3pt for the side buttons). --frame-dir takes the
# user's image and puts the screen in its transparent hole. --full-content stays unframed, with a warning.
mkdir -p "$out/frame/user"
"$bin" render Examples/Interactions.swift --preview Counter --open-fonts --scale 1 --frame -o "$out/frame/counter.png" --json \
  --frames "$out/frame/frames" --frames-every-step --steps 'tap "Increment"' >"$out/frame/counter.json" 2>&1 || fail "framed counter"
grep -q '"height":888' "$out/frame/counter.json" && grep -q '"width":435' "$out/frame/counter.json" \
  && echo "ok    framed size 435x888" || fail "framed size: $(cat "$out/frame/counter.json")"
for f in "$out"/frame/frames/*.png; do
  python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); sys.exit(struct.unpack(">II", d[16:24]) != (435, 888))' "$f" \
    || fail "$(basename "$f") is not framed"
done
# A 433x892 frame image: opaque grey with a 393x852 transparent hole at (20, 20).
python3 - "$out/frame/user/iphone-16.png" <<'PY'
import struct, sys, zlib
w, h = 433, 892
rows = b"".join(b"\0" + b"".join(b"\0\0\0\0" if 20 <= x < 413 and 20 <= y < 872 else b"\x40\x40\x44\xff" for x in range(w)) for y in range(h))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                              + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
PY
"$bin" render Examples/Interactions.swift --preview Counter --open-fonts --scale 1 --frame-dir "$out/frame/user" -o "$out/frame/user.png" --json \
  >"$out/frame/user.json" 2>&1 || fail "--frame-dir render"
grep -q '"width":433' "$out/frame/user.json" && echo "ok    --frame-dir uses the image" || fail "--frame-dir: $(cat "$out/frame/user.json")"
"$bin" render Examples/Interactions.swift --preview Counter --open-fonts --scale 1 --device iphone-17 --frame-dir "$out/frame/user" \
  -o "$out/frame/fallback.png" >"$out/frame/fallback.log" 2>&1 || fail "--frame-dir fallback render"
grep -q "no iphone-17.png" "$out/frame/fallback.log" && echo "ok    --frame-dir falls back with a warning" || fail "fallback: $(cat "$out/frame/fallback.log")"
"$bin" render Tests/Corpus/01_Settings.swift --open-fonts --scale 1 --frame --full-content "$out/frame/full.png" \
  -o "$out/frame/full-screen.png" >"$out/frame/full.log" 2>&1
grep -q "full-content images are not framed" "$out/frame/full.log" && echo "ok    --full-content warns" || fail "full-content: $(cat "$out/frame/full.log")"

# Shaking: an override of UIWindow.motionEnded in an extension (a dynamic replacement) posts a notification
# the view counts. Overrides in extensions of the app's own classes draw (Tests/Projects/run.sh checks the warnings).
mkdir -p "$out/shake"
"$bin" render Tests/Projects/Diagnostics/ExtensionOverrides.swift --no-project --open-fonts --scale 1 -o "$out/shake/shake.png" \
  --steps 'shake; shake' --accessibility-outline >"$out/shake/shake.log" 2>&1 || fail "shake render"
grep -q 'Shakes: 2' "$out/shake/shake.log" && echo "ok    shake reaches UIWindow.motionEnded" || fail "shake: $(cat "$out/shake/shake.log")"
grep -q 'staticText "Set up in viewDidLoad"' "$out/shake/shake.log" && echo "ok    viewDidLoad in an extension runs" \
  || fail "viewDidLoad in an extension did not run: $(cat "$out/shake/shake.log")"

# Determinism: same input, same bytes.
for f in $(cd "$out/a" && find . -type f ! -name '*.log' ! -name '*.json' | sort); do
  cmp -s "$out/a/$f" "$out/b/$f" || fail "$f differs between two runs"
done
[ "$failures" = 0 ] && echo "ok    outputs byte-identical across runs"
exit $((failures > 0))
