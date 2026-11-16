#!/usr/bin/env bash
# Records Siri Remote press sequences in a tvOS app of your own (any built .app), for comparing the
# renderer's --press / --steps navigation with the real focus engine. After every press it saves the focused
# element, the buttons and cells on screen with their frames, the visible text, and a screenshot.
#
#   scripts/mac/tvos/record-app.sh --app <path/to/App.app> --out <dir>
#       [--env KEY=VALUE]... [--arg <value>]... [--settle <s>]
#       [--device "Apple TV 4K (3rd generation)"]
#       <name>=<presses> ...            e.g.  start=  tabs=right,right  push=down,select,menu
#
# Writes <out>/<name>.json ({name, presses, size, steps: [{press, focused, elements, texts, screenshot}]})
# and <out>/<name>-<step>.png (step 0 is the launch). The app is installed on the simulator first; the
# simulator is booted if needed and shut down again afterwards if it was not running. Uses XcodeGen for the
# UI test that drives the remote. Keep the output with the other references, outside the repository.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="Apple TV 4K (3rd generation)"
APP=""; OUT=""; SETTLE=3
ENVS=(); ARGS=(); PATHS=()
while (($#)); do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --env) ENVS+=("$2"); shift 2 ;;
        --arg) ARGS+=("$2"); shift 2 ;;
        --settle) SETTLE="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *=*) PATHS+=("$1"); shift ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
[[ -d "$APP" && -n "$OUT" && ${#PATHS[@]} -gt 0 ]] || { sed -n '2,13p' "$0"; exit 2; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"

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
echo "Simulator: $DEVICE, tvOS $RUNTIME_VERSION ($UDID); app $BUNDLE_ID"

WAS_BOOTED=0
if xcrun simctl list devices | grep -q "$UDID) (Booted)"; then WAS_BOOTED=1; fi
trap '((WAS_BOOTED == 0)) && xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true' EXIT
if ((WAS_BOOTED == 0)); then xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null; fi
xcrun simctl install "$UDID" "$APP"

BUILD="${TMPDIR:-/tmp}/blitr-tvos-app-paths"
mkdir -p "$BUILD/tests"
cp "$HERE/AppPathTests.swift" "$BUILD/tests/"
cat > "$BUILD/project.yml" <<YML
name: AppPaths
options:
  bundleIdPrefix: dev.blitr
  deploymentTarget:
    tvOS: "26.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    GENERATE_INFOPLIST_FILE: YES
    CODE_SIGNING_ALLOWED: NO
targets:
  AppPaths:
    type: bundle.ui-testing
    platform: tvOS
    sources: [tests]
schemes:
  AppPaths:
    build:
      targets:
        AppPaths: [test]
    test:
      targets: [AppPaths]
YML
(cd "$BUILD" && xcodegen generate --quiet)
xcodebuild -project "$BUILD/AppPaths.xcodeproj" -scheme AppPaths -destination "id=$UDID" \
    -derivedDataPath "$BUILD/derived" build-for-testing -quiet

to_json() { python3 -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "$@"; }
ENV_JSON="$(python3 -c 'import json, sys; print(json.dumps(dict(a.split("=", 1) for a in sys.argv[1:])))' ${ENVS[@]+"${ENVS[@]}"})"
ARGS_JSON="$(to_json ${ARGS[@]+"${ARGS[@]}"})"
PATHS_JSON="$(python3 -c 'import json, sys; print(json.dumps([dict(zip(["name", "presses"], p.split("=", 1))) for p in sys.argv[1:]]))' "${PATHS[@]}")"

TEST_RUNNER_APP_BUNDLE="$BUNDLE_ID" TEST_RUNNER_APP_ENV="$ENV_JSON" TEST_RUNNER_APP_ARGS="$ARGS_JSON" \
TEST_RUNNER_APP_PATHS="$PATHS_JSON" TEST_RUNNER_APP_OUT="$OUT" TEST_RUNNER_APP_SETTLE="$SETTLE" \
    xcodebuild -project "$BUILD/AppPaths.xcodeproj" -scheme AppPaths -destination "id=$UDID" \
    -derivedDataPath "$BUILD/derived" test-without-building -only-testing:AppPaths/AppPathTests/testPaths \
    -quiet >"$BUILD/test.log" 2>&1 || echo "test run failed (see $BUILD/test.log)" >&2

python3 - "$OUT" "$RUNTIME_VERSION" "$DEVICE" "${PATHS[@]}" <<'PY'
import json, os, sys
out, version, device, *paths = sys.argv[1:]
for p in paths:
    name = p.split("=", 1)[0]
    f = os.path.join(out, name + ".json")
    if not os.path.exists(f):
        print(f"  {name}: no result"); continue
    doc = json.load(open(f))
    doc.update({"tvosVersion": version, "device": device})
    json.dump(doc, open(f, "w"), indent=2, sort_keys=True)
    trail = " -> ".join(f"{s['press']}:{s['focused'].get('label') or '-'}" for s in doc["steps"])
    print(f"  {name}: {trail}")
PY
