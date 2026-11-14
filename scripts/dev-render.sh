#!/usr/bin/env bash
# Development helper: render one SwiftUI file with the locally built module.
#   scripts/dev-render.sh Examples/Hello.swift out.png [runner options...]
# Rewrites `#Preview` the same way the CLI does, compiles against .build, runs.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/swift/usr/bin:$PATH"
src="$1"; out="$2"; shift 2
bin="$(cd "$root" && swift build --show-bin-path)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
python3 "$root/scripts/preprocess.py" "$src" "$work"
swiftc -swift-version 5 -Onone -I "$bin" -L "$bin" -lSwiftUIScreenshotEngine \
  -Xlinker -rpath -Xlinker "$bin" -Xlinker -rpath -Xlinker "$root/Vendor/skia/lib" \
  "$work"/*.swift -o "$work/runner" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error|warning: unre" -A3 || true
[ -x "$work/runner" ] || { echo "compile failed" >&2; exit 1; }
"$work/runner" --out "$out" --fonts "$root/Vendor/fonts" "$@"
