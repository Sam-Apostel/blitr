#!/usr/bin/env bash
# Captures reference screenshots and element frames from the iOS Simulator for every preview in
# Tests/Corpus (and Examples), for comparison with the renderer (`swiftui-screenshot compare`).
#
#   scripts/mac/capture-references.sh [options]
#
#   --runtime <version>   iOS runtime to use, e.g. 26.5 (default: newest installed)
#   --device <name>       Simulator device type (default: "iPhone 16", the renderer's default)
#   --schemes "<list>"    Color schemes (default: "light dark")
#   --only <key>          Only screens whose key matches this grep pattern (e.g. 01_Settings)
#   --corpus-only         Skip Examples
#   --out <dir>           Output root (default: Tests/Reference)
#   --settle <seconds>    Wait after the view appears before capturing (default: 1.0)
#
# Writes <out>/ios-<runtime>/<device-slug>/<scheme>/<screen>-<preview>.png and .json, plus
# <out>/ios-<runtime>/manifest.json. Uses an existing simulator of that device type and runtime
# (it creates none), and shuts it down afterwards if it was not already booted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME=""
DEVICE="iPhone 16"
SCHEMES="light dark"
ONLY=""
CORPUS_ONLY=0
OUT="$ROOT/Tests/Reference"
SETTLE="1.0"
BUNDLE_ID="dev.swiftui-screenshot.reference-host"

while (($#)); do
    case "$1" in
        --runtime) RUNTIME="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --schemes) SCHEMES="$2"; shift 2 ;;
        --only) ONLY="$2"; shift 2 ;;
        --corpus-only) CORPUS_ONLY=1; shift ;;
        --out) OUT="$2"; shift 2 ;;
        --settle) SETTLE="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done

# --- Pick the simulator ------------------------------------------------------------------------
read -r RUNTIME_ID RUNTIME_VERSION RUNTIME_BUILD < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
if want: rts = [r for r in rts if r["version"] == want or r["version"].startswith(want + ".")]
if not rts: sys.exit("no matching iOS runtime installed")
r = sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
print(r["identifier"], r["version"], r["buildversion"])' "$RUNTIME")

# A simulator of that device type: its name may differ (e.g. one created for this run).
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
if [[ -z "$UDID" ]]; then
    echo "No \"$DEVICE\" simulator on iOS $RUNTIME_VERSION. Create one (xcrun simctl create <name> \"$DEVICE\" $RUNTIME_ID) and run again." >&2
    exit 1
fi

SLUG="$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
DEST="$OUT/ios-$RUNTIME_VERSION/$SLUG"
BUILD="${TMPDIR:-/tmp}/swiftui-screenshot-reference-host"
echo "Simulator: $DEVICE, iOS $RUNTIME_VERSION ($UDID)"

WAS_BOOTED=0
if xcrun simctl list devices | grep -q "$UDID) (Booted)"; then WAS_BOOTED=1; fi
OLD_LOCALE=""; OLD_LANGUAGES=""; OLD_REDUCE_MOTION=""
restore() {
    xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
    if [[ -n "$OLD_LOCALE" ]]; then xcrun simctl spawn "$UDID" defaults write -g AppleLocale "$OLD_LOCALE" >/dev/null 2>&1 || true; fi
    if [[ -n "$OLD_LANGUAGES" ]]; then xcrun simctl spawn "$UDID" defaults write -g AppleLanguages "$OLD_LANGUAGES" >/dev/null 2>&1 || true; fi
    if [[ -z "$OLD_REDUCE_MOTION" ]]; then
        xcrun simctl spawn "$UDID" defaults delete com.apple.Accessibility ReduceMotionEnabled >/dev/null 2>&1 || true
    fi
    if ((WAS_BOOTED == 0)); then xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; fi
}
trap restore EXIT

if ((WAS_BOOTED == 0)); then
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b >/dev/null
fi

# --- Build and install the host app ------------------------------------------------------------
SOURCES=("$ROOT"/Tests/Corpus/*.swift)
if ((CORPUS_ONLY == 0)); then SOURCES+=("$ROOT"/Examples/*.swift "$ROOT"/Examples/*/*.swift); fi
# Build for the runtime being captured, so sources using its newest APIs compile.
APP="$(DEPLOYMENT_TARGET="$RUNTIME_VERSION" "$ROOT/scripts/mac/build-host.sh" "$BUILD" "${SOURCES[@]}" | tail -1)"
xcrun simctl install "$UDID" "$APP"

# --- Make the simulator deterministic -----------------------------------------------------------
OLD_LOCALE="$(xcrun simctl spawn "$UDID" defaults read -g AppleLocale 2>/dev/null || true)"
OLD_LANGUAGES="$(xcrun simctl spawn "$UDID" defaults read -g AppleLanguages 2>/dev/null | tr -d '\n ' || true)"
OLD_REDUCE_MOTION="$(xcrun simctl spawn "$UDID" defaults read com.apple.Accessibility ReduceMotionEnabled 2>/dev/null || true)"
xcrun simctl spawn "$UDID" defaults write -g AppleLocale en_US
xcrun simctl spawn "$UDID" defaults write -g AppleLanguages '("en-US")'
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true
xcrun simctl ui "$UDID" content_size large
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100

CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/Documents"
SRGB="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

# --- Capture -----------------------------------------------------------------------------------
captured=0; skipped=()
while IFS=$'\t' read -r key index name; do
    if [[ -n "$ONLY" ]] && ! grep -qE "$ONLY" <<<"$key"; then continue; fi
    for scheme in $SCHEMES; do
        xcrun simctl ui "$UDID" appearance "$scheme"
        mkdir -p "$DEST/$scheme"
        rm -f "$CONTAINER/ready"
        xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
            -screen "$key" -preview "$index" -settle "$SETTLE" -AppleLocale en_US -AppleLanguages '(en)' >/dev/null
        ready=0
        for _ in $(seq 1 100); do
            if [[ -f "$CONTAINER/ready" ]]; then ready=1; break; fi
            sleep 0.1
        done
        if ((ready == 0)); then
            echo "  $key-$index ($scheme): no ready signal, captured after timeout" >&2
        fi
        png="$DEST/$scheme/$key-$index.png"
        xcrun simctl io "$UDID" screenshot --type=png "$png" >/dev/null 2>&1
        # Simulator screenshots are normally tagged sRGB already; convert anything else.
        profile="$(sips -g profile "$png" | awk -F': ' '/profile/ {print $2}')"
        if [[ "$profile" != sRGB* ]]; then sips --matchTo "$SRGB" "$png" >/dev/null; fi
        if [[ -f "$CONTAINER/$key-$index.json" ]]; then
            python3 - "$CONTAINER/$key-$index.json" "$DEST/$scheme/$key-$index.json" "$key" "$index" "$name" <<'PY'
import json, sys
src, dst, key, index, name = sys.argv[1:]
doc = json.load(open(src))
doc["screen"] = key; doc["preview"] = int(index)
if name: doc["previewName"] = name
json.dump(doc, open(dst, "w"), indent=2, sort_keys=True)
PY
            rm -f "$CONTAINER/$key-$index.json"
        fi
        captured=$((captured + 1))
        printf '  %s-%s %s\n' "$key" "$index" "$scheme"
    done
done < <(python3 - "$BUILD/gen/screens.json" <<'PY'
import json, sys
for screen in json.load(open(sys.argv[1])):
    for p in screen["previews"]:
        # Only full-device previews are comparable to a simulator screen.
        if p.get("layout") or p.get("orientation"):
            print(f"skip\t{screen['key']}-{p['index']}\t", file=sys.stderr); continue
        print(f"{screen['key']}\t{p['index']}\t{p.get('name', '')}")
PY
)

# The simulator runs on the Mac's clock and time zone.
SIM_DATE="$(date '+%Y-%m-%dT%H:%M:%S%z')"
SIM_TZ="$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"

# --- Manifest -----------------------------------------------------------------------------------
python3 - "$OUT/ios-$RUNTIME_VERSION/manifest.json" "$DEVICE" "$SLUG" "$RUNTIME_VERSION" "$RUNTIME_BUILD" "$BUILD/gen/screens.json" <<PY
import json, os, sys, subprocess, datetime
path, device, slug, version, build, screens = sys.argv[1:]
manifest = json.load(open(path)) if os.path.exists(path) else {}
xcode = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True).stdout.split()
manifest.update({
    "iosVersion": version,
    "runtimeBuild": build,
    "xcode": " ".join(xcode[:2]),
    "xcodeBuild": xcode[-1] if xcode else "",
})
devices = manifest.setdefault("devices", {})
devices[slug] = {
    "name": device,
    "schemes": "$SCHEMES".split(),
    "captured": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "statusBar": {"time": "9:41", "battery": "charged 100%", "cellularBars": 4, "wifiBars": 3},
    "locale": "en_US", "dynamicType": "large", "reduceMotion": True, "colorSpace": "sRGB",
    # Screens that show dates or times render the simulator's clock; this is when they were taken.
    "simulatorDate": "$SIM_DATE", "simulatorTimeZone": "$SIM_TZ",
}
failed = set(open(os.path.join(os.path.dirname(screens), "failed.txt")).read().split()) if os.path.exists(os.path.join(os.path.dirname(screens), "failed.txt")) else set()
listed = json.load(open(screens))
for s in listed:
    if s["module"] in failed:
        s["skipped"] = "does not compile for iOS with real SwiftUI"
    elif not s["previews"]:
        s["skipped"] = "no previews (an App's WindowGroup cannot be shown on its own)"
manifest["screens"] = listed
json.dump(manifest, open(path, "w"), indent=2, sort_keys=True)
PY
echo "Captured $captured images into $DEST"
