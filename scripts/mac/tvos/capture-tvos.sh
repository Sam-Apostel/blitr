#!/usr/bin/env bash
# Captures tvOS reference screenshots and element frames in the Apple TV simulator, including focused
# states reached with Siri Remote presses (the same presses the renderer takes with --press).
#
#   scripts/mac/tvos/capture-tvos.sh [--device "Apple TV 4K (3rd generation)"] [--schemes "light dark"]
#                                    [--only <regex>] [--out <dir>] [file.swift...]
#
# Default files: Examples/TVControls.swift, Tests/Corpus/13_TVHome.swift, Tests/Corpus/14_TVSettings.swift.
# Writes <out>/<scheme>/<screen>-<preview>.png and .json (default out:
# Tests/Reference/tvos-<runtime>/apple-tv-4k), plus <screen>-<preview>-<presses>.png/.json for the press
# variants below, and <out>/../manifest.json. Uses XcodeGen for the UI test that drives the remote.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="Apple TV 4K (3rd generation)"
SCHEMES="light dark"
ONLY=""
OUT=""
FILES=()
while (($#)); do
    case "$1" in
        --device) DEVICE="$2"; shift 2 ;;
        --schemes) SCHEMES="$2"; shift 2 ;;
        --only) ONLY="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) FILES+=("$1"); shift ;;
    esac
done
((${#FILES[@]})) || FILES=("$ROOT/Examples/TVControls.swift" "$ROOT/Tests/Corpus/13_TVHome.swift" "$ROOT/Tests/Corpus/14_TVSettings.swift")

# Press variants, from the header comment of Examples/TVControls.swift: "<screen>|<preview name>|<presses>".
# The Buttons variant reaches "Prominent" (the renderer's --focus "Prominent") with two presses right.
VARIANTS=(
    "TVControls|Buttons|right,right"
    "TVControls|Tab Bar|down"
    "TVControls|Alert|down"
    "TVControls|Settings List|down,down"
)

read -r RUNTIME_ID RUNTIME_VERSION RUNTIME_BUILD < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "tvOS" and r["isAvailable"]]
if not rts: sys.exit("no tvOS simulator runtime installed")
r = sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
print(r["identifier"], r["version"], r["buildversion"])')
UDID="$(xcrun simctl list devices -j | python3 -c '
import json, sys
ds = [d for d in json.load(sys.stdin)["devices"].get(sys.argv[1], []) if d["name"] == sys.argv[2] and d["isAvailable"]]
print(ds[0]["udid"] if ds else "")' "$RUNTIME_ID" "$DEVICE")"
[[ -n "$UDID" ]] || { echo "No \"$DEVICE\" simulator on tvOS $RUNTIME_VERSION" >&2; exit 1; }
SLUG="$(echo "$DEVICE" | sed -E 's/ \(3rd generation\)//; s/ \(at 1080p\)/ hd/' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
OUT="${OUT:-$ROOT/Tests/Reference/tvos-$RUNTIME_VERSION/$SLUG}"
BUILD="${TMPDIR:-/tmp}/swiftui-screenshot-tvos-capture"
BUNDLE_ID="dev.swiftui-screenshot.reference-host"
echo "Simulator: $DEVICE, tvOS $RUNTIME_VERSION ($UDID)"

WAS_BOOTED=0
if xcrun simctl list devices | grep -q "$UDID) (Booted)"; then WAS_BOOTED=1; fi
# `simctl ui <udid> appearance` fails on tvOS 26.5 ("Runtime does not support userInterfaceStyle"), so when
# it is refused AppearanceTests sets it through the Settings app. Either way the result is checked against
# PineBoard's SystemAppearanceKey (0 Light, 1 Dark; absent behaves as Dark).
appearance_key() { xcrun simctl spawn "$UDID" defaults read com.apple.PineBoard SystemAppearanceKey 2>/dev/null || echo 1; }
set_appearance() { # Light | Dark
    local want=0; [[ "$1" == Dark ]] && want=1
    local lower; lower="$(tr '[:upper:]' '[:lower:]' <<<"$1")"
    if xcrun simctl ui "$UDID" appearance "$lower" >/dev/null 2>&1 && [[ "$(appearance_key)" == "$want" ]]; then return; fi
    for _ in 1 2 3; do
        TEST_RUNNER_APPEARANCE_STYLE="$1" xcodebuild -project "$BUILD/TVCapture.xcodeproj" -scheme TVCapture \
            -destination "id=$UDID" -derivedDataPath "$BUILD/derived" test-without-building \
            -only-testing:TVCapture/AppearanceTests/testSetAppearance -quiet >"$BUILD/appearance.log" 2>&1 || true
        sleep 1
        [[ "$(appearance_key)" == "$want" ]] && return
    done
    echo "could not set the $1 appearance (see $BUILD/appearance.log)" >&2; exit 1
}
OLD_APPEARANCE=""
restore() {
    # Back to how it was: no key behaves as Dark.
    if [[ -n "${APPEARANCE_CHANGED:-}" ]]; then
        if [[ "$OLD_APPEARANCE" == "0" ]]; then set_appearance Light || true; else set_appearance Dark || true; fi
        [[ -z "$OLD_APPEARANCE" ]] && xcrun simctl spawn "$UDID" defaults delete com.apple.PineBoard SystemAppearanceKey >/dev/null 2>&1
    fi
    if ((WAS_BOOTED == 0)); then xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; fi
}
trap restore EXIT
if ((WAS_BOOTED == 0)); then xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null; fi

# --- Host app (one module per file) and the UI test that drives it -------------------------------------
APP="$(PLATFORM=tvos DEPLOYMENT_TARGET="$RUNTIME_VERSION" "$ROOT/scripts/mac/build-host.sh" "$BUILD/host" "${FILES[@]}" | tail -1)"
xcrun simctl install "$UDID" "$APP"
mkdir -p "$BUILD/tests"
cp "$HERE/CaptureTests.swift" "$HERE/AppearanceTests.swift" "$BUILD/tests/"
cat > "$BUILD/project.yml" <<YML
name: TVCapture
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
  TVCapture:
    type: bundle.ui-testing
    platform: tvOS
    sources: [tests]
schemes:
  TVCapture:
    build:
      targets:
        TVCapture: [test]
    test:
      targets: [TVCapture]
YML
(cd "$BUILD" && xcodegen generate --quiet)
xcodebuild -project "$BUILD/TVCapture.xcodeproj" -scheme TVCapture -destination "id=$UDID" \
    -derivedDataPath "$BUILD/derived" build-for-testing -quiet
OLD_APPEARANCE="$(xcrun simctl spawn "$UDID" defaults read com.apple.PineBoard SystemAppearanceKey 2>/dev/null || true)"
CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Documents"

# --- Capture ------------------------------------------------------------------------------------
JOBS="$(python3 - "$BUILD/host/gen/screens.json" "${VARIANTS[@]}" <<'PY'
import json, sys
screens = json.load(open(sys.argv[1]))
variants = [v.split("|") for v in sys.argv[2:]]
for s in screens:
    for p in s["previews"]:
        if p.get("layout") or p.get("orientation"): continue
        print(f"{s['key']}\t{p['index']}\t")
        for key, name, presses in variants:
            if key == s["key"] and p.get("name") == name:
                print(f"{s['key']}\t{p['index']}\t{presses}")
PY
)"
captured=0
for scheme in $SCHEMES; do
    APPEARANCE_CHANGED=1
    if [[ "$scheme" == dark ]]; then set_appearance Dark; else set_appearance Light; fi
    mkdir -p "$OUT/$scheme"
    while IFS=$'\t' read -r key index presses; do
        [[ -z "$key" ]] && continue
        if [[ -n "$ONLY" ]] && ! grep -qE "$ONLY" <<<"$key"; then continue; fi
        name="$key-$index${presses:+-${presses//,/-}}"
        rm -f "$CONTAINER/$key-$index.json"
        TEST_RUNNER_CAPTURE_BUNDLE="$BUNDLE_ID" TEST_RUNNER_CAPTURE_SCREEN="$key" TEST_RUNNER_CAPTURE_PREVIEW="$index" \
        TEST_RUNNER_CAPTURE_PRESSES="$presses" TEST_RUNNER_CAPTURE_OUT="$OUT/$scheme/$name.png" \
            xcodebuild -project "$BUILD/TVCapture.xcodeproj" -scheme TVCapture -destination "id=$UDID" \
            -derivedDataPath "$BUILD/derived" test-without-building -only-testing:TVCapture/CaptureTests/testCapture \
            -quiet >"$BUILD/test.log" 2>&1 \
            || { echo "  $scheme/$name: test failed (see $BUILD/test.log)" >&2; continue; }
        if [[ -f "$CONTAINER/$key-$index.json" ]]; then
            python3 - "$CONTAINER/$key-$index.json" "$OUT/$scheme/$name.json" "$key" "$index" "$presses" <<'PY'
import json, sys
src, dst, key, index, presses = sys.argv[1:]
doc = json.load(open(src))
doc.update({"screen": key, "preview": int(index), "presses": presses.split(",") if presses else []})
json.dump(doc, open(dst, "w"), indent=2, sort_keys=True)
PY
        fi
        captured=$((captured + 1))
        echo "  $scheme/$name"
    done <<<"$JOBS"
done

# --- Manifest -----------------------------------------------------------------------------------
python3 - "$(dirname "$OUT")/manifest.json" "$DEVICE" "$SLUG" "$RUNTIME_VERSION" "$RUNTIME_BUILD" "$BUILD/host/gen/screens.json" "$SCHEMES" "${VARIANTS[@]}" <<'PY'
import json, os, sys, subprocess, datetime
path, device, slug, version, build, screens, schemes, *variants = sys.argv[1:]
manifest = json.load(open(path)) if os.path.exists(path) else {}
xcode = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True).stdout.split()
manifest.update({"tvosVersion": version, "runtimeBuild": build, "xcode": " ".join(xcode[:2]),
                 "xcodeBuild": xcode[-1] if xcode else ""})
manifest.setdefault("devices", {})[slug] = {
    "name": device, "schemes": schemes.split(),
    "captured": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "colorSpace": "sRGB",
    # Set as the system appearance (Settings > General > Appearance), driven by AppearanceTests.
    "appearance": "system",
    # The simulator runs in the Mac's time zone; calibrate.py renders with it (--time-zone).
    "simulatorTimeZone": os.path.realpath("/etc/localtime").split("/zoneinfo/")[-1],
    "pressVariants": [dict(zip(["screen", "preview", "presses"], v.split("|"))) for v in variants],
}
manifest["screens"] = json.load(open(screens))
json.dump(manifest, open(path, "w"), indent=2, sort_keys=True)
PY
echo "Captured $captured images into $OUT"
