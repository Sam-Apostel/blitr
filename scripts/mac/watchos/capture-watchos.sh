#!/usr/bin/env bash
# Captures watchOS reference screenshots and element frames in the Apple Watch simulator.
#
#   scripts/mac/watchos/capture-watchos.sh [--devices "<name>|<name>"] [--schemes "light dark"]
#                                          [--only <regex>] [--out <dir>] [--settle <seconds>] [file.swift...]
#
# Default devices: Apple Watch Series 10 (46mm), Series 10 (42mm) and Ultra 2 (49mm), the renderer's
# apple-watch-series-10-46mm, apple-watch-series-10-42mm and apple-watch-ultra-2. Default files:
# Examples/Watch.swift and Examples/WatchList.swift. Writes <out>/<device-slug>/<scheme>/<screen>-<preview>.png
# and .json, plus <out>/manifest.json (default out: <references>/watchos-<runtime>). Uses an existing
# simulator of each device type on the newest watchOS runtime (it creates none) and shuts down the ones it
# booted. Uses XcodeGen for the UI test that drives the app and reads its accessibility hierarchy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICES="Apple Watch Series 10 (46mm)|Apple Watch Series 10 (42mm)|Apple Watch Ultra 2 (49mm)"
SCHEMES="light dark"
ONLY=""
OUT=""
SETTLE="1.0"
FILES=()
while (($#)); do
    case "$1" in
        --devices) DEVICES="$2"; shift 2 ;;
        --schemes) SCHEMES="$2"; shift 2 ;;
        --only) ONLY="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --settle) SETTLE="$2"; shift 2 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) FILES+=("$1"); shift ;;
    esac
done
((${#FILES[@]})) || FILES=("$ROOT/Examples/Watch.swift" "$ROOT/Examples/WatchList.swift")

read -r RUNTIME_ID RUNTIME_VERSION RUNTIME_BUILD < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "watchOS" and r["isAvailable"]]
if not rts: sys.exit("no watchOS simulator runtime installed")
r = sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]
print(r["identifier"], r["version"], r["buildversion"])')
OUT="${OUT:-${SWIFTUI_SCREENSHOT_REFERENCES:-$HOME/Library/Application Support/swiftui-screenshot/references}/watchos-$RUNTIME_VERSION}"
BUILD="${TMPDIR:-/tmp}/swiftui-screenshot-watchos-capture"
BUNDLE_ID="dev.swiftui-screenshot.reference-host"

# A simulator of that device type on the runtime: its name may differ (e.g. one created for this run).
udid_for() {
    python3 - "$RUNTIME_ID" "$1" <<'PY'
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
}
# "Apple Watch Series 10 (46mm)" -> apple-watch-series-10-46mm; "Apple Watch Ultra 2 (49mm)" -> apple-watch-ultra-2.
slug_for() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g; s/(ultra(-[0-9]+)?)-49mm$/\1/'
}

IFS='|' read -r -a DEVICE_LIST <<<"$DEVICES"
UDIDS=()
for device in "${DEVICE_LIST[@]}"; do
    udid="$(udid_for "$device")"
    if [[ -z "$udid" ]]; then
        echo "No \"$device\" simulator on watchOS $RUNTIME_VERSION. Create one (xcrun simctl create <name> \"$device\" $RUNTIME_ID) and run again." >&2
        exit 1
    fi
    UDIDS+=("$udid")
done

BOOTED_HERE=()
RESTORE_LOCALE=()   # "<udid>\t<AppleLocale>\t<AppleLanguages>" as found before the run
restore() {
    for entry in ${RESTORE_LOCALE[@]+"${RESTORE_LOCALE[@]}"}; do
        IFS=$'\t' read -r udid locale languages <<<"$entry"
        if [[ -n "$locale" ]]; then xcrun simctl spawn "$udid" defaults write -g AppleLocale "$locale" >/dev/null 2>&1 || true
        else xcrun simctl spawn "$udid" defaults delete -g AppleLocale >/dev/null 2>&1 || true; fi
        if [[ -n "$languages" ]]; then xcrun simctl spawn "$udid" defaults write -g AppleLanguages "$languages" >/dev/null 2>&1 || true
        else xcrun simctl spawn "$udid" defaults delete -g AppleLanguages >/dev/null 2>&1 || true; fi
    done
    for udid in ${BOOTED_HERE[@]+"${BOOTED_HERE[@]}"}; do
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    done
}
trap restore EXIT

# --- Host app (one module per file) and the UI test that drives it -------------------------------------
APP="$(PLATFORM=watchos DEPLOYMENT_TARGET="$RUNTIME_VERSION" "$ROOT/scripts/mac/build-host.sh" "$BUILD/host" "${FILES[@]}" | tail -1)"
mkdir -p "$BUILD/tests"
cp "$HERE/CaptureTests.swift" "$BUILD/tests/"
cat > "$BUILD/project.yml" <<YML
name: WatchCapture
options:
  bundleIdPrefix: dev.swiftui-screenshot
  deploymentTarget:
    watchOS: "$RUNTIME_VERSION"
settings:
  base:
    SWIFT_VERSION: "5.0"
    GENERATE_INFOPLIST_FILE: YES
    CODE_SIGNING_ALLOWED: NO
targets:
  WatchCapture:
    type: bundle.ui-testing
    platform: watchOS
    sources: [tests]
schemes:
  WatchCapture:
    build:
      targets:
        WatchCapture: [test]
    test:
      targets: [WatchCapture]
YML
(cd "$BUILD" && xcodegen generate --quiet)
xcodebuild -project "$BUILD/WatchCapture.xcodeproj" -scheme WatchCapture -destination "id=${UDIDS[0]}" \
    -derivedDataPath "$BUILD/derived" build-for-testing -quiet

JOBS="$(python3 - "$BUILD/host/gen/screens.json" "$ONLY" <<'PY'
import json, os, re, sys
path, only = sys.argv[1:]
failed_path = os.path.join(os.path.dirname(path), "failed.txt")
failed = set(open(failed_path).read().split()) if os.path.exists(failed_path) else set()
jobs = []
for s in json.load(open(path)):
    if s["module"] in failed or (only and not re.search(only, s["key"])): continue
    for p in s["previews"]:
        if p.get("layout") or p.get("orientation"): continue
        jobs.append(f"{s['key']}:{p['index']}")
print(" ".join(jobs))
PY
)"
[[ -n "$JOBS" ]] || { echo "nothing to capture" >&2; exit 1; }

# --- Capture ------------------------------------------------------------------------------------
APPEARANCE="{}"
captured=0
for i in "${!DEVICE_LIST[@]}"; do
    device="${DEVICE_LIST[$i]}"; udid="${UDIDS[$i]}"; slug="$(slug_for "$device")"
    echo "Simulator: $device, watchOS $RUNTIME_VERSION ($udid)"
    if ! xcrun simctl list devices | grep -q "$udid) (Booted)"; then
        xcrun simctl boot "$udid"; BOOTED_HERE+=("$udid")
    fi
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl install "$udid" "$APP"
    # The same locale as the iOS sets. The watch's clock cannot be overridden (`simctl status_bar` is refused
    # on watchOS), so it shows the Mac's time; the manifest records when each device was captured.
    RESTORE_LOCALE+=("$udid"$'\t'"$(xcrun simctl spawn "$udid" defaults read -g AppleLocale 2>/dev/null || true)"$'\t'"$(xcrun simctl spawn "$udid" defaults read -g AppleLanguages 2>/dev/null | tr -d '\n ' || true)")
    xcrun simctl spawn "$udid" defaults write -g AppleLocale en_US
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages '("en-US")'
    DATES="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); d[sys.argv[2]]=sys.argv[3]; print(json.dumps(d))' "${DATES:-}" "$slug" "$(date '+%Y-%m-%dT%H:%M:%S%z')")"
    CONTAINER="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)/Documents"
    for scheme in $SCHEMES; do
        # How the scheme was applied: "system" when simctl set it, otherwise the system default stands.
        how="system"
        xcrun simctl ui "$udid" appearance "$scheme" >/dev/null 2>&1 || how="unsupported"
        APPEARANCE="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d[sys.argv[2]]=sys.argv[3]; print(json.dumps(d))' "$APPEARANCE" "$scheme" "$how")"
        dest="$OUT/$slug/$scheme"; mkdir -p "$dest"
        rm -f "$CONTAINER"/*.meta.json
        TEST_RUNNER_CAPTURE_BUNDLE="$BUNDLE_ID" TEST_RUNNER_CAPTURE_JOBS="$JOBS" TEST_RUNNER_CAPTURE_OUT="$dest" \
        TEST_RUNNER_CAPTURE_SETTLE="$SETTLE" \
            xcodebuild -project "$BUILD/WatchCapture.xcodeproj" -scheme WatchCapture -destination "id=$udid" \
            -derivedDataPath "$BUILD/derived" test-without-building -only-testing:WatchCapture/CaptureTests/testCapture \
            -quiet >"$BUILD/test.log" 2>&1 || echo "  $slug/$scheme: test failed (see $BUILD/test.log)" >&2
        for job in $JOBS; do
            name="${job/:/-}"
            [[ -f "$dest/$name.png" ]] || { echo "  $slug/$scheme/$name: not captured" >&2; continue; }
            python3 - "$dest/$name.tree.json" "$CONTAINER/$name.meta.json" "$dest/$name.json" "${job%%:*}" "${job##*:}" \
                "$BUILD/host/gen/screens.json" <<'PY'
import json, os, sys
tree_path, meta_path, dst, key, index, screens = sys.argv[1:]
tree = json.load(open(tree_path))
doc = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
# Element frames as XCUITest reports them (points, screen coordinates); roles are XCUIElementType names,
# which `swiftui-screenshot compare` matches against the renderer's roles. The application node is dropped.
doc.update({"version": 1, "source": "xcuitest", "elements": tree.get("children", []),
            "screen": key, "preview": int(index)})
for s in json.load(open(screens)):
    if s["key"] == key:
        name = next((p.get("name") for p in s["previews"] if p["index"] == int(index)), None)
        if name: doc["previewName"] = name
json.dump(doc, open(dst, "w"), indent=2, sort_keys=True)
os.remove(tree_path)
PY
            captured=$((captured + 1))
            echo "  $slug/$scheme/$name"
        done
    done
done

# --- Manifest -----------------------------------------------------------------------------------
python3 - "$OUT/manifest.json" "$RUNTIME_VERSION" "$RUNTIME_BUILD" "$BUILD/host/gen/screens.json" "$SCHEMES" \
    "$APPEARANCE" "$DEVICES" "$DATES" <<'PY'
import json, os, re, sys, subprocess, datetime
path, version, build, screens, schemes, appearance, devices, dates = sys.argv[1:]
dates = json.loads(dates)
manifest = json.load(open(path)) if os.path.exists(path) else {}
xcode = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True).stdout.split()
manifest.update({"watchosVersion": version, "runtimeBuild": build, "xcode": " ".join(xcode[:2]),
                 "xcodeBuild": xcode[-1] if xcode else ""})
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
for device in devices.split("|"):
    slug = re.sub(r"(ultra(-[0-9]+)?)-49mm$", r"\1", re.sub(r"[^a-z0-9]+", "-", device.lower()).strip("-"))
    manifest.setdefault("devices", {})[slug] = {
        "name": device, "schemes": schemes.split(), "captured": now, "colorSpace": "sRGB",
        # Per scheme: "system" when `simctl ui appearance` set it, "unsupported" when the runtime refused.
        "appearance": json.loads(appearance),
        "elementSource": "xcuitest",
        "locale": "en_US",
        # The clock in the corner shows the simulator's (the Mac's) time at capture.
        "simulatorDate": dates.get(slug, ""),
        "simulatorTimeZone": os.path.realpath("/etc/localtime").split("/zoneinfo/")[-1],
    }
manifest["screens"] = json.load(open(screens))
json.dump(manifest, open(path, "w"), indent=2, sort_keys=True)
PY
echo "Captured $captured images into $OUT"
