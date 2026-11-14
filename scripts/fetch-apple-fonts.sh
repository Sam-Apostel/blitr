#!/usr/bin/env bash
# Optional: fetch Apple's system fonts (SF Pro, SF Pro Rounded, SF Mono, New York) from
# Apple's own download servers so renders use the real fonts instead of the open substitutes.
#
#   scripts/fetch-apple-fonts.sh --accept-apple-font-license [--dest DIR]
#
# Nothing here is redistributed: the files are downloaded from Apple to this machine and
# unpacked locally. Apple licenses these fonts solely for creating mock-ups of user
# interfaces for software running on Apple platforms; read the terms at
# https://developer.apple.com/fonts/ (the licence is also shown by each installer package).
# Passing --accept-apple-font-license (or ACCEPT_APPLE_FONT_LICENSE=1) states that you accept them.
#
# Requires: curl, 7z (apt-get install 7zip).
set -euo pipefail
cd "$(dirname "$0")/.."

dest="Vendor/apple-fonts"
accepted="${ACCEPT_APPLE_FONT_LICENSE:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --accept-apple-font-license) accepted=1 ;;
    --dest) dest="$2"; shift ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$accepted" != 1 ]; then
  cat >&2 <<'MSG'
Apple's fonts are licensed by Apple, for creating mock-ups of user interfaces for software
running on Apple platforms. Read the terms at https://developer.apple.com/fonts/ and re-run with
  --accept-apple-font-license
to download them from Apple to this machine.
MSG
  exit 1
fi

sevenzip="$(command -v 7z || command -v 7zz || true)"
[ -n "$sevenzip" ] || { echo "7z not found. Install it with: apt-get install -y 7zip" >&2; exit 1; }

base="https://devimages-cdn.apple.com/design/resources/download"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$dest"

# A font disk image is: .dmg -> installer .pkg -> cpio payload -> Library/Fonts/*.
unpack() { # name
  local name="$1" work="$tmp/$1"
  mkdir -p "$work/dmg" "$work/pkg" "$work/payload"
  echo "Fetching $name.dmg from Apple"
  curl -fsSL --retry 3 -o "$work/$name.dmg" "$base/$name.dmg"
  "$sevenzip" x -y -o"$work/dmg" "$work/$name.dmg" >/dev/null
  local pkg; pkg="$(find "$work/dmg" -name '*.pkg' | head -n 1)"
  [ -n "$pkg" ] || { echo "no installer package found in $name.dmg" >&2; exit 1; }
  "$sevenzip" x -y -o"$work/pkg" "$pkg" >/dev/null
  local payload; payload="$(find "$work/pkg" -type f -name 'Payload*' | head -n 1)"
  [ -n "$payload" ] || { echo "no payload found in $name.dmg" >&2; exit 1; }
  "$sevenzip" x -y -o"$work/payload" "$payload" >/dev/null
  sha256sum "$work/$name.dmg" | sed "s|$work/||" >> "$dest/SOURCES.txt"
}

keep() { # name, then file patterns
  local name="$1"; shift
  for pattern in "$@"; do
    find "$tmp/$name/payload" -type f -name "$pattern" -exec cp {} "$dest/" \;
  done
}

: > "$dest/SOURCES.txt"
unpack SF-Pro
keep SF-Pro 'SF-Pro.ttf' 'SF-Pro-Italic.ttf' 'SF-Pro-Rounded-*.otf'
unpack SF-Mono
keep SF-Mono 'SF-Mono-*.otf'
unpack NY
keep NY 'NewYork*.ttf'

count="$(find "$dest" -type f \( -name '*.ttf' -o -name '*.otf' \) | wc -l)"
echo "Installed $count Apple font files into $dest (source checksums in $dest/SOURCES.txt)."
echo "swiftui-screenshot picks this directory up automatically; check with: swiftui-screenshot doctor"
