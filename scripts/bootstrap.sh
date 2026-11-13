#!/usr/bin/env bash
# Fetches the pinned native dependencies that are not committed to the repo:
#   - Skia (prebuilt libSkiaSharp.so, C API) -> Vendor/skia/lib
#   - Inter (open substitute for SF Pro)      -> Vendor/fonts
# Safe to re-run; skips anything already present.
set -euo pipefail
cd "$(dirname "$0")/.."

SKIA_VERSION=4.156.0
SKIA_SHA256=45780b4ae200797bba6ce479f10554711902eeab5676bd3854894df89d0edc10
INTER_VERSION=4.1
INTER_SHA256=9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e

case "$(uname -m)" in
  x86_64) RID=linux-x64 ;;
  aarch64|arm64) RID=linux-arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

fetch() { # url sha256 dest
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c - >/dev/null
}

if [ ! -f Vendor/skia/lib/libSkiaSharp.so ]; then
  echo "Fetching Skia $SKIA_VERSION ($RID)"
  fetch "https://api.nuget.org/v3-flatcontainer/skiasharp.nativeassets.linux.nodependencies/$SKIA_VERSION/skiasharp.nativeassets.linux.nodependencies.$SKIA_VERSION.nupkg" "$SKIA_SHA256" "$tmp/skia.zip"
  mkdir -p Vendor/skia/lib
  unzip -qo "$tmp/skia.zip" "runtimes/$RID/native/libSkiaSharp.so" LICENSE.txt THIRD-PARTY-NOTICES.txt -d "$tmp/skia"
  cp "$tmp/skia/runtimes/$RID/native/libSkiaSharp.so" Vendor/skia/lib/
  # The library's SONAME is versioned (libSkiaSharp.so.N.0.0); the loader looks for that name.
  soname=$(objdump -p Vendor/skia/lib/libSkiaSharp.so | awk '$1 == "SONAME" { print $2 }')
  if [ -n "$soname" ] && [ "$soname" != libSkiaSharp.so ]; then ln -sf libSkiaSharp.so "Vendor/skia/lib/$soname"; fi
  cp "$tmp/skia/LICENSE.txt" "$tmp/skia/THIRD-PARTY-NOTICES.txt" Vendor/skia/
fi

if [ ! -f Vendor/fonts/InterVariable.ttf ]; then
  echo "Fetching Inter $INTER_VERSION"
  fetch "https://github.com/rsms/inter/releases/download/v$INTER_VERSION/Inter-$INTER_VERSION.zip" "$INTER_SHA256" "$tmp/inter.zip"
  mkdir -p Vendor/fonts
  unzip -qo "$tmp/inter.zip" InterVariable.ttf InterVariable-Italic.ttf LICENSE.txt -d "$tmp/inter"
  cp "$tmp/inter/InterVariable.ttf" "$tmp/inter/InterVariable-Italic.ttf" Vendor/fonts/
  cp "$tmp/inter/LICENSE.txt" Vendor/fonts/Inter-LICENSE.txt
fi

echo "Vendor/ is ready."
