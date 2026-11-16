#!/bin/bash
# Framework shim checks: known-answer tests (hashes, UTType, keychain, colors) and decoding the generated
# barcodes with zxing-cpp when it is installed (pip install zxing-cpp pillow), and offline map tiles
# (Tests/Maps/tiles.sh). Run from the repository
# root after `swift build`.
set -u
cd "$(dirname "$0")/../.."
bin="$(swift build --show-bin-path)/swiftui-screenshot"
out="${1:-out/Frameworks}"
mkdir -p "$out"
results="$(cd "$out" && pwd)/checks.txt"
rm -f "$results"
FRAMEWORK_CHECKS_OUT="$results" "$bin" render Tests/Frameworks/UnitChecks.swift -o "$out/checks.png" --layout fit --open-fonts >"$out/checks.log" 2>&1
[ -f "$results" ] || { echo "FAIL checks did not run (see $out/checks.log)"; exit 1; }
cat "$results"
failures=$(grep -c "^FAIL" "$results")
if python3 -c "import zxingcpp" 2>/dev/null; then
  "$bin" render Examples/Frameworks/Barcodes.swift -o "$out/barcodes.png" --layout fit --width 393 --open-fonts >/dev/null 2>&1
  decoded=$(python3 -c "
import zxingcpp
from PIL import Image
print(len(zxingcpp.read_barcodes(Image.open('$out/barcodes.png').convert('RGB'))))")
  if [ "$decoded" -ge 4 ]; then echo "PASS barcodes decode ($decoded)"; else echo "FAIL barcodes decode ($decoded)"; failures=$((failures + 1)); fi
fi
# Offline map tiles: markers' coordinates and the tiles' pixels agree.
if Tests/Maps/tiles.sh "$out/MapTiles"; then echo "PASS map tiles"; else echo "FAIL map tiles"; failures=$((failures + 1)); fi
[ "$failures" -eq 0 ] || { echo "$failures failed"; exit 1; }
