#!/usr/bin/env bash
# Fetches the pinned native dependencies that are not committed to the repo:
#   - Skia (prebuilt libSkiaSharp.so, C API; libSkiaSharp.dylib on macOS) -> Vendor/skia/lib
#   - Open fonts standing in for Apple's system fonts -> Vendor/fonts
#       Inter (SF Pro), Nunito (SF Rounded), Source Serif 4 (New York),
#       JetBrains Mono (SF Mono), Noto Color Emoji (Apple Color Emoji)
# Safe to re-run; skips anything already present.
#   - HarfBuzz, self-contained (libHarfBuzzSharp, no glib or freetype) -> Vendor/harfbuzz/lib, for release
#     tarballs only (scripts/make-dist.sh)
# A build from source compiles and links against the system's HarfBuzz (libharfbuzz-dev on Linux; on macOS
# Homebrew's harfbuzz, found through pkg-config); a release carries its own, so it needs neither.
set -euo pipefail
cd "$(dirname "$0")/.."

SKIA_VERSION=4.156.0
SKIA_SHA256=45780b4ae200797bba6ce479f10554711902eeab5676bd3854894df89d0edc10
# The macOS package of the same release: one universal (arm64 + x86_64) libSkiaSharp.dylib.
SKIA_MACOS_SHA256=5014f2cb2560cdc99b2fd7d0b88497bc2742e766d21f2a79fc7dbcbb71137f9d
# HarfBuzzSharp, from the same project as SkiaSharp: HarfBuzz built with no dependencies beyond libc.
HARFBUZZ_VERSION=14.4.0.101
HARFBUZZ_SHA256=39ad37a2fcd1a8a1597315b636a7a711b7305c84296bf16b0119aa3eebbfb288
HARFBUZZ_MACOS_SHA256=db0e3be411603f30abdf5745b066a64ea1d7e983f6664d7501bc7e81fa691eea
INTER_VERSION=4.1
INTER_SHA256=9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e

OS="$(uname -s)"
if [ "$OS" = Darwin ]; then
  RID=osx
  if ! command -v pkg-config >/dev/null || ! pkg-config --exists harfbuzz; then
    echo "HarfBuzz was not found through pkg-config. Install both with: brew install harfbuzz pkg-config" >&2
    exit 1
  fi
else
  case "$(uname -m)" in
    x86_64) RID=linux-x64 ;;
    aarch64|arm64) RID=linux-arm64 ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

sha256_check() { # reads "<sha256>  <file>" on stdin; macOS has shasum where Linux has sha256sum
  if command -v sha256sum >/dev/null; then sha256sum -c - >/dev/null; else shasum -a 256 -c - >/dev/null; fi
}

fetch() { # url sha256 dest
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256_check
}

if [ "$OS" = Darwin ]; then
  if [ ! -f Vendor/skia/lib/libSkiaSharp.dylib ]; then
    echo "Fetching Skia $SKIA_VERSION (macOS, universal)"
    fetch "https://api.nuget.org/v3-flatcontainer/skiasharp.nativeassets.macos/$SKIA_VERSION/skiasharp.nativeassets.macos.$SKIA_VERSION.nupkg" "$SKIA_MACOS_SHA256" "$tmp/skia.zip"
    mkdir -p Vendor/skia/lib
    unzip -qo "$tmp/skia.zip" "runtimes/$RID/native/libSkiaSharp.dylib" LICENSE.txt THIRD-PARTY-NOTICES.txt -d "$tmp/skia"
    # Its install name is already @rpath/libSkiaSharp.dylib, so it loads from the engine's rpaths as it is
    # (and keeps its signature: nothing is rewritten).
    cp "$tmp/skia/runtimes/$RID/native/libSkiaSharp.dylib" Vendor/skia/lib/
    cp "$tmp/skia/LICENSE.txt" "$tmp/skia/THIRD-PARTY-NOTICES.txt" Vendor/skia/
  fi
elif [ ! -f Vendor/skia/lib/libSkiaSharp.so ]; then
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

if [ "$OS" = Darwin ]; then hb_package=harfbuzzsharp.nativeassets.macos; hb_sha=$HARFBUZZ_MACOS_SHA256; hb_file=libHarfBuzzSharp.dylib
else hb_package=harfbuzzsharp.nativeassets.linux; hb_sha=$HARFBUZZ_SHA256; hb_file=libHarfBuzzSharp.so; fi
if [ ! -f "Vendor/harfbuzz/lib/$hb_file" ]; then
  echo "Fetching HarfBuzz $HARFBUZZ_VERSION ($RID)"
  fetch "https://api.nuget.org/v3-flatcontainer/$hb_package/$HARFBUZZ_VERSION/$hb_package.$HARFBUZZ_VERSION.nupkg" "$hb_sha" "$tmp/harfbuzz.zip"
  mkdir -p Vendor/harfbuzz/lib
  unzip -qo "$tmp/harfbuzz.zip" "runtimes/$RID/native/$hb_file" -d "$tmp/harfbuzz"
  cp "$tmp/harfbuzz/runtimes/$RID/native/$hb_file" Vendor/harfbuzz/lib/
fi

if [ ! -f Vendor/fonts/InterVariable.ttf ]; then
  echo "Fetching Inter $INTER_VERSION"
  fetch "https://github.com/rsms/inter/releases/download/v$INTER_VERSION/Inter-$INTER_VERSION.zip" "$INTER_SHA256" "$tmp/inter.zip"
  mkdir -p Vendor/fonts
  unzip -qo "$tmp/inter.zip" InterVariable.ttf InterVariable-Italic.ttf LICENSE.txt -d "$tmp/inter"
  cp "$tmp/inter/InterVariable.ttf" "$tmp/inter/InterVariable-Italic.ttf" Vendor/fonts/
  cp "$tmp/inter/LICENSE.txt" Vendor/fonts/Inter-LICENSE.txt
fi

# Remaining system-font designs, pinned to exact upstream commits.
GOOGLE_FONTS=https://raw.githubusercontent.com/google/fonts/29b4ec6df2522a8aee279414b78a07910b065874/ofl
NOTO_EMOJI=https://raw.githubusercontent.com/googlefonts/noto-emoji/22e564626297b4df0a40570ad81d6c05cc7c38bd/fonts
font() { # url sha256 filename
  if [ ! -f "Vendor/fonts/$3" ]; then
    echo "Fetching $3"
    fetch "$1" "$2" "$tmp/font"
    mv "$tmp/font" "Vendor/fonts/$3"
  fi
}
font "$GOOGLE_FONTS/nunito/Nunito%5Bwght%5D.ttf" bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207 "Nunito[wght].ttf"
font "$GOOGLE_FONTS/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf" 48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda "JetBrainsMono[wght].ttf"
font "$GOOGLE_FONTS/jetbrainsmono/JetBrainsMono-Italic%5Bwght%5D.ttf" 85ae2a5cd3f56baf1ce1c21a851322c58e3d8fbe8e8ad4a4d090a820dd7fe558 "JetBrainsMono-Italic[wght].ttf"
font "$GOOGLE_FONTS/sourceserif4/SourceSerif4%5Bopsz%2Cwght%5D.ttf" 97b2d4da6e3cb494b5a1e66ae176914d852ccabef49e0c02c0df25f3e39aca0b "SourceSerif4[opsz,wght].ttf"
font "$GOOGLE_FONTS/sourceserif4/SourceSerif4-Italic%5Bopsz%2Cwght%5D.ttf" 15fbc7e4679489a501998c3669272637a6646388ef7e4bd77eebb5bf967a1f42 "SourceSerif4-Italic[opsz,wght].ttf"
font "$NOTO_EMOJI/NotoColorEmoji.ttf" 39ee3c587e10e89669b9ff32703261d10d5f9c4dd5ad147b6b5a1c5200591817 "NotoColorEmoji.ttf"
# Each font's own licence file, from the same pinned commits.
font "$GOOGLE_FONTS/nunito/OFL.txt" 580df76c95a1ec5ab878ceb25bb3d85c6a076804e9c970c8c6972aea775fdf65 "Nunito-LICENSE.txt"
font "$GOOGLE_FONTS/jetbrainsmono/OFL.txt" b2fe5e8987594e9ffd1d2ca52a2f5d73eb8335243893c5d6254b5ad69269591d "JetBrainsMono-LICENSE.txt"
font "$GOOGLE_FONTS/sourceserif4/OFL.txt" 5f94c3fd3a23131a417ab5a0c8452de57e70c3cfb9f604d88241f7065ebf9fd9 "SourceSerif4-LICENSE.txt"
font "$NOTO_EMOJI/LICENSE" 6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2 "NotoColorEmoji-LICENSE.txt"

echo "Vendor/ is ready."
