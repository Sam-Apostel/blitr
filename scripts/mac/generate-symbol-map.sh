#!/usr/bin/env bash
# Builds generate-symbol-map.swift with optimizations and runs it (interpreted, it takes over half an hour;
# compiled, under a minute). Arguments go to the generator: [--font Vendor/apple-fonts/SF-Pro.ttf] [--out <dir>]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$here/generate-symbol-map.swift" "$work/main.swift"
swiftc -O "$work/main.swift" -o "$work/generate-symbol-map"
cd "$here/../.."
"$work/generate-symbol-map" "$@"
