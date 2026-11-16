#!/usr/bin/env bash
# Records where the real tvOS focus engine moves focus, for every preview of a SwiftUI file, by driving
# the Siri Remote in the Apple TV simulator from a UI test (see FocusWalkTests.swift).
#
#   scripts/mac/tvos/record-focus.sh [--source Examples/TVFocus.swift] [--previews "0 1 2"]
#                                    [--device "Apple TV 4K (3rd generation) (at 1080p)"] [--out <dir>]
#                                    [--probe <presses>]
#
# Writes <out>/<screen>-<preview>.json (default out: <references>/tvos-<runtime>/focus) with, per
# focusable element, its label and frame in points, the press path that reaches it from launch, and the
# element each of up/down/left/right moves to (null: focus stays). Uses XcodeGen for the project.
#
# With --probe "right,down,select,menu" (and one preview), it instead replays those presses from launch
# and writes <screen>-<preview>-probe-<presses>.json with the focused element and visible text after
# each press, for questions that depend on history.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$ROOT/scripts/mac/tvos-focus"
HOST="$ROOT/scripts/mac/host"
SOURCE="$ROOT/Examples/TVFocus.swift"
PREVIEWS=""
PROBE=""
DEVICE="Apple TV 4K (3rd generation) (at 1080p)"
OUT=""
while (($#)); do
    case "$1" in
        --source) SOURCE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
        --previews) PREVIEWS="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --probe) PROBE="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done

read -r RUNTIME_ID RUNTIME_VERSION < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "tvOS" and r["isAvailable"]]
if not rts: sys.exit("no tvOS simulator runtime installed")
r = sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
print(r["identifier"], r["version"])')
UDID="$(xcrun simctl list devices -j | python3 -c '
import json, sys
ds = [d for d in json.load(sys.stdin)["devices"].get(sys.argv[1], []) if d["name"] == sys.argv[2] and d["isAvailable"]]
print(ds[0]["udid"] if ds else "")' "$RUNTIME_ID" "$DEVICE")"
[[ -n "$UDID" ]] || { echo "No \"$DEVICE\" simulator on tvOS $RUNTIME_VERSION" >&2; exit 1; }
OUT="${OUT:-${SWIFTUI_SCREENSHOT_REFERENCES:-$HOME/Library/Application Support/swiftui-screenshot/references}/tvos-$RUNTIME_VERSION/focus}"
BUILD="${TMPDIR:-/tmp}/swiftui-screenshot-focus-host"
mkdir -p "$BUILD/src" "$BUILD/tests" "$OUT"
echo "Simulator: $DEVICE, tvOS $RUNTIME_VERSION ($UDID)"

# --- Sources: the preview file rewritten as for the iOS host, in one module ----------------------------
xcrun swiftc -O "$ROOT/Sources/swiftui-screenshot/Preprocessor.swift" "$HOST/Driver/main.swift" -o "$BUILD/prepare-host"
"$BUILD/prepare-host" "$ROOT" "$BUILD/gen" "$SOURCE"
KEY="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["key"])' "$BUILD/gen/screens.json")"
rm -f "$BUILD"/src/*.swift
for f in "$HOST"/App/*.swift "$HOST/PreviewSupport/PreviewEntry.swift"; do sed "/^import PreviewSupport$/d" "$f" > "$BUILD/src/$(basename "$f")"; done
sed '/^import PreviewSupport$/d' "$BUILD"/gen/modules/*.swift > "$BUILD/src/Screen.swift"
printf 'import SwiftUI\n\n@MainActor let previewRegistry: [String: [_PreviewEntry]] = ["%s": __previewEntries]\n' "$KEY" > "$BUILD/src/Registry.swift"
cp "$HERE/FocusWalkTests.swift" "$BUILD/tests/"

cat > "$BUILD/project.yml" <<YML
name: FocusHost
options:
  bundleIdPrefix: dev.swiftui-screenshot
  deploymentTarget:
    tvOS: "26.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    GENERATE_INFOPLIST_FILE: YES
    CODE_SIGNING_ALLOWED: NO
targets:
  FocusHost:
    type: application
    platform: tvOS
    sources: [src]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.swiftui-screenshot.focus-host
  FocusWalk:
    type: bundle.ui-testing
    platform: tvOS
    sources: [tests]
    dependencies:
      - target: FocusHost
    settings:
      base:
        TEST_TARGET_NAME: FocusHost
schemes:
  FocusHost:
    build:
      targets:
        FocusHost: all
        FocusWalk: [test]
    test:
      targets: [FocusWalk]
YML
(cd "$BUILD" && xcodegen generate --quiet)
xcodebuild -project "$BUILD/FocusHost.xcodeproj" -scheme FocusHost -destination "id=$UDID" \
    -derivedDataPath "$BUILD/derived" build-for-testing -quiet

# --- Walk each preview ---------------------------------------------------------------------------
if [[ -z "$PREVIEWS" ]]; then
    PREVIEWS="$(python3 -c 'import json,sys; print(" ".join(str(p["index"]) for p in json.load(open(sys.argv[1]))[0]["previews"]))' "$BUILD/gen/screens.json")"
fi
WAS_BOOTED=0
if xcrun simctl list devices | grep -q "$UDID) (Booted)"; then WAS_BOOTED=1; fi
trap '((WAS_BOOTED == 0)) && xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true' EXIT
for index in $PREVIEWS; do
    file="$OUT/$KEY-$index.json"
    only="FocusWalk/FocusWalkTests/testWalk"
    if [[ -n "$PROBE" ]]; then
        mkdir -p "$OUT/probes"; file="$OUT/probes/$KEY-$index-probe-${PROBE//,/-}.json"; only="FocusWalk/FocusWalkTests/testProbe"
    fi
    rm -f "$file"
    echo "  $KEY-$index"
    TEST_RUNNER_FOCUS_LIMIT="${FOCUS_LIMIT:-80}" TEST_RUNNER_FOCUS_SCREEN="$KEY" TEST_RUNNER_FOCUS_PREVIEW="$index" TEST_RUNNER_FOCUS_OUT="$file" TEST_RUNNER_FOCUS_PROBE="$PROBE" \
        xcodebuild -project "$BUILD/FocusHost.xcodeproj" -scheme FocusHost -destination "id=$UDID" \
        -derivedDataPath "$BUILD/derived" test-without-building -only-testing:"$only" -quiet >"$BUILD/test-$index.log" 2>&1 \
        || echo "    test run failed (see $BUILD/test-$index.log)" >&2
    if [[ -f "$file" ]]; then
        python3 - "$file" "$RUNTIME_VERSION" "$DEVICE" "$BUILD/gen/screens.json" "$index" <<'PY'
import json, sys
path, runtime, device, screens, index = sys.argv[1:]
doc = json.load(open(path))
names = {str(p["index"]): p.get("name") for p in json.load(open(screens))[0]["previews"]}
doc.update({"tvosVersion": runtime, "device": device, "previewName": names.get(index)})
json.dump(doc, open(path, "w"), indent=2, sort_keys=True)
PY
    else
        echo "    no result written" >&2
    fi
done
echo "Focus walks in $OUT"
