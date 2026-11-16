#!/bin/bash
# Offline map tiles (--map-tiles): generated tiles with dots at known coordinates, three maps drawn on them
# (Tests/Maps/MapTiles.swift), and the dots found where Web Mercator puts them (Tests/Maps/tiles.py).
# Run from the repository root after `swift build`:
#
#     Tests/Maps/tiles.sh [output-directory]
set -u
cd "$(dirname "$0")/../.."
bin="$(swift build --show-bin-path)/blitr"
out="${1:-out/MapTiles}"
rm -rf "$out"; mkdir -p "$out"
python3 Tests/Maps/tiles.py make "$out/tiles" || { echo "FAIL could not make the tiles"; exit 1; }
"$bin" render Tests/Maps/MapTiles.swift --all --map-tiles "$out/tiles" --layout fixed --width 300 --height 300 --scale 1 \
  --no-chrome --open-fonts --out-dir "$out/renders" >"$out/render.log" 2>&1 || { echo "FAIL render (see $out/render.log)"; exit 1; }
if grep -q "tiles are not drawn" "$out/render.log"; then echo "FAIL the placeholder warning shows with --map-tiles"; exit 1; fi
ls "$out/renders"
python3 Tests/Maps/tiles.py check "$out/renders"/*Rect*.png "$out/renders"/*Deep*.png "$out/renders"/*Heading*.png
