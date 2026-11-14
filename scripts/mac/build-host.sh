#!/usr/bin/env bash
# Builds the reference-capture host app for the iOS Simulator from SwiftUI sources.
#
#   scripts/mac/build-host.sh <build-dir> <file.swift>...
#
# Produces <build-dir>/ReferenceHost.app and <build-dir>/gen/screens.json. Uses swiftc directly (no
# Xcode project): each source file is compiled as its own module, then linked into one app.
set -euo pipefail

BUILD="$1"; shift
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST="$ROOT/scripts/mac/host"
DEPLOYMENT="${DEPLOYMENT_TARGET:-18.0}"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-ios$DEPLOYMENT-simulator"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SWIFTC=(xcrun --sdk iphonesimulator swiftc -target "$TARGET" -sdk "$SDK" -swift-version 5 -Onone)
BUNDLE_ID="${BUNDLE_ID:-dev.swiftui-screenshot.reference-host}"

mkdir -p "$BUILD/bin" "$BUILD/gen" "$BUILD/mods" "$BUILD/obj"

# 1. The preprocessor driver runs on the Mac.
xcrun swiftc -O "$ROOT/Sources/swiftui-screenshot/Preprocessor.swift" "$HOST/Driver/main.swift" -o "$BUILD/bin/prepare-host"
"$BUILD/bin/prepare-host" "$ROOT" "$BUILD/gen" "$@"

# 2. PreviewSupport, then one module per screen.
rm -f "$BUILD"/obj/*.o
"${SWIFTC[@]}" -parse-as-library -module-name PreviewSupport -emit-module -emit-module-path "$BUILD/mods/PreviewSupport.swiftmodule" \
    -c "$HOST/PreviewSupport/PreviewEntry.swift" -o "$BUILD/obj/PreviewSupport.o"

failed=()
for source in "$BUILD"/gen/modules/*.swift; do
    module="$(basename "$source" .swift)"
    if ! "${SWIFTC[@]}" -parse-as-library -module-name "$module" -I "$BUILD/mods" \
        -emit-module -emit-module-path "$BUILD/mods/$module.swiftmodule" -c "$source" -o "$BUILD/obj/$module.o" 2>"$BUILD/obj/$module.log"; then
        failed+=("$module")
        echo "  could not compile $module (see $BUILD/obj/$module.log)" >&2
        sed -n '1,12p' "$BUILD/obj/$module.log" >&2
    fi
done
printf '%s\n' ${failed[@]+"${failed[@]}"} > "$BUILD/gen/failed.txt"
if ((${#failed[@]})); then
    # Leave the failures out of the registry so the rest still build.
    for module in "${failed[@]}"; do
        sed -i '' "/^import $module\$/d; /$module\.__previewEntries/d" "$BUILD/gen/Registry.swift"
        rm -f "$BUILD/obj/$module.o"
    done
fi

# 3. The app.
APP="$BUILD/ReferenceHost.app"
rm -rf "$APP"; mkdir -p "$APP"
"${SWIFTC[@]}" -parse-as-library -module-name ReferenceHost -I "$BUILD/mods" \
    "$HOST"/App/*.swift "$BUILD/gen/Registry.swift" "$BUILD"/obj/*.o -o "$APP/ReferenceHost"

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>ReferenceHost</string>
    <key>CFBundleName</key><string>ReferenceHost</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
    <key>MinimumOSVersion</key><string>$DEPLOYMENT</string>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
    <key>UILaunchScreen</key><dict/>
    <key>UIApplicationSupportsIndirectInputEvents</key><true/>
    <key>UISupportedInterfaceOrientations</key><array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIFileSharingEnabled</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "$APP"
