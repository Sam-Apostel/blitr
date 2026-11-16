#!/usr/bin/env bash
# Measures the frame SwiftUI gives `Image(systemName:)` in the iOS Simulator for every symbol name the
# renderer's substitute artwork knows, and writes Sources/SwiftUI/Symbols/SymbolFrames.generated.swift.
#
#   scripts/mac/measure-symbol-frames.sh [--runtime 27.2] [--device "iPhone 16"] [--tsv <frames.tsv>]
#
# Names: every entry of Sources/SwiftUI/Symbols/SymbolData.generated.swift plus the hand-drawn ones in
# HandDrawnSymbols.swift. Configurations: 100pt at ultralight, regular, bold and black, each at image scale
# small, medium and large, plus checks: the other weights at 100pt, regular medium at 9-40pt and up to 80pt,
# and 17pt at every stored weight and scale.
# Uses an existing simulator of that device type and runtime (it creates none) and shuts it down afterwards
# if it was not booted. --tsv skips the simulator and regenerates the table from an earlier measurement.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME=""
DEVICE="iPhone 16"
TSV=""
while (($#)); do
    case "$1" in
        --runtime) RUNTIME="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --tsv) TSV="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
BUILD="${TMPDIR:-/tmp}/swiftui-screenshot-symbol-frames"
BUNDLE_ID="dev.swiftui-screenshot.symbol-frames"
mkdir -p "$BUILD"

if [[ -z "$TSV" ]]; then
    read -r RUNTIME_ID RUNTIME_VERSION RUNTIME_BUILD < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
if want: rts = [r for r in rts if r["version"] == want or r["version"].startswith(want + ".")]
if not rts: sys.exit("no matching iOS runtime installed")
r = sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
print(r["identifier"], r["version"], r["buildversion"])' "$RUNTIME")
    UDID="$(python3 - "$RUNTIME_ID" "$DEVICE" <<'PY'
import json, subprocess, sys
runtime, want = sys.argv[1:]
types = {t["identifier"]: t["name"] for t in json.loads(subprocess.run(
    ["xcrun", "simctl", "list", "devicetypes", "-j"], capture_output=True, text=True).stdout)["devicetypes"]}
devices = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "-j"],
                                    capture_output=True, text=True).stdout)["devices"].get(runtime, [])
match = [d for d in devices if d["isAvailable"] and (d["name"] == want or types.get(d.get("deviceTypeIdentifier")) == want)]
match.sort(key=lambda d: (d["state"] != "Booted", d["name"] != want))
print(match[0]["udid"] if match else "")
PY
)"
    [[ -n "$UDID" ]] || { echo "No \"$DEVICE\" simulator on iOS $RUNTIME_VERSION. Create one (xcrun simctl create <name> \"$DEVICE\" $RUNTIME_ID) and run again." >&2; exit 1; }
    echo "Simulator: $DEVICE, iOS $RUNTIME_VERSION ($RUNTIME_BUILD, $UDID)"
    WAS_BOOTED=0
    if xcrun simctl list devices | grep -q "$UDID) (Booted)"; then WAS_BOOTED=1; fi
    restore() { if ((WAS_BOOTED == 0)); then xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; fi; }
    trap restore EXIT
    if ((WAS_BOOTED == 0)); then xcrun simctl boot "$UDID"; fi
    xcrun simctl bootstatus "$UDID" -b >/dev/null

    # --- The app ---------------------------------------------------------------------------------
    APP="$BUILD/SymbolFrames.app"
    rm -rf "$APP"; mkdir -p "$APP"
    python3 - "$ROOT" > "$APP/names.txt" <<'PY'
import re, sys
root = sys.argv[1]
names = []
for line in open(f"{root}/Sources/SwiftUI/Symbols/SymbolData.generated.swift"):
    m = re.match(r"^([a-z0-9][A-Za-z0-9.]*)(@b)?\t\d", line)
    if m and m.group(1) not in names: names.append(m.group(1))
for m in re.finditer(r'case ((?:"[^"]+",?\s*)+):', open(f"{root}/Sources/SwiftUI/Symbols/HandDrawnSymbols.swift").read()):
    for n in re.findall(r'"([^"]+)"', m.group(1)):
        if n not in names: names.append(n)
print("\n".join(names))
PY
    {
        # The table: 100pt, the four weights, three scales.
        for w in ultralight regular bold black; do for s in small medium large; do echo "100 $w $s"; done; done
        # Checks: the other weights at 100pt (is interpolating between the four enough?), regular medium at
        # other point sizes (do frames scale linearly?), and 17pt at every weight and scale.
        for w in thin light medium semibold heavy; do for s in small medium large; do echo "100 $w $s"; done; done
        for p in $(seq 9 40) 44 48 56 64 80; do echo "$p regular medium"; done
        for w in ultralight bold black; do for s in small medium large; do echo "17 $w $s"; done; done
        echo "17 regular small"; echo "17 regular large"
    } > "$APP/configs.txt"
    SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    xcrun --sdk iphonesimulator swiftc -target "$(uname -m)-apple-ios$RUNTIME_VERSION-simulator" -sdk "$SDK" \
        -parse-as-library -swift-version 5 -O "$HERE/symbols/SymbolFramesApp.swift" -o "$APP/SymbolFrames"
    cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>SymbolFrames</string>
    <key>CFBundleName</key><string>SymbolFrames</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
    <key>MinimumOSVersion</key><string>$RUNTIME_VERSION</string>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
    <key>UILaunchScreen</key><dict/>
</dict>
</plist>
PLIST
    codesign --force --sign - "$APP" >/dev/null 2>&1
    xcrun simctl install "$UDID" "$APP"
    CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Documents"
    rm -f "$CONTAINER/done" "$CONTAINER/frames.tsv"
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" >/dev/null
    jobs=$(( $(wc -l < "$APP/names.txt") * $(wc -l < "$APP/configs.txt") ))
    echo "Measuring $jobs frames"
    for _ in $(seq 1 1800); do [[ -f "$CONTAINER/done" ]] && break; sleep 1; done
    [[ -f "$CONTAINER/done" ]] || { echo "the app did not finish (no $CONTAINER/done)" >&2; exit 1; }
    TSV="$BUILD/frames.tsv"
    cp "$CONTAINER/frames.tsv" "$TSV"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "$RUNTIME_VERSION $RUNTIME_BUILD $DEVICE" > "$BUILD/frames.meta"
    echo "Measurements: $TSV"
fi

python3 "$HERE/symbols/generate-symbol-frames.py" "$TSV" "$(cat "$(dirname "$TSV")/frames.meta")" \
    "$ROOT/Sources/SwiftUI/Symbols/SymbolFrames.generated.swift"
