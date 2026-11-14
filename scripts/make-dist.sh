#!/usr/bin/env bash
# Builds a relocatable release tarball:
#
#   dist/swiftui-screenshot-<version>-linux-<arch>.tar.gz
#
#   swiftui-screenshot/
#     bin/swiftui-screenshot
#     lib/swiftui-screenshot/   SwiftUI, Combine, UIKit modules + shared libraries, libSkiaSharp, fonts/
#     share/swiftui-screenshot/ fetch-apple-fonts.sh, THIRD-PARTY-NOTICES, VERSION
#
# Usage: scripts/make-dist.sh [VERSION]     (default: git describe --tags --always)
# Needs Vendor/ (scripts/bootstrap.sh), the Swift toolchain on PATH, and patchelf
# (apt-get install -y patchelf). Apple's fonts (Vendor/apple-fonts) are never packaged.
# shellcheck disable=SC2015,SC2016  # `[ a ] && [ b ] || die` is intended; '$ORIGIN' must stay literal
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
root="$(pwd)"

for tool in swift patchelf readelf objdump tar; do
  command -v "$tool" >/dev/null || { echo "make-dist: '$tool' not found on PATH" >&2; exit 1; }
done
[ -f Vendor/skia/lib/libSkiaSharp.so ] && [ -d Vendor/fonts ] \
  || { echo "make-dist: Vendor/ is missing; run scripts/bootstrap.sh first" >&2; exit 1; }

version="${1:-${VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}}"
commit="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  aarch64|arm64) arch=aarch64 ;;
  *) echo "make-dist: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
swift_banner="$(swiftc --version 2>&1 | grep -m1 'Swift version')"
swift_version="$(sed -E 's/^.*Swift version ([^ ]+).*$/\1/' <<<"$swift_banner")"
name="swiftui-screenshot-$version-linux-$arch"

echo "Building $name ($swift_banner)"
swift build -c release >&2
bin="$(swift build -c release --show-bin-path)"

stage="$root/dist/stage/swiftui-screenshot"
rm -rf "$root/dist/stage"
lib="$stage/lib/swiftui-screenshot"
share="$stage/share/swiftui-screenshot"
mkdir -p "$stage/bin" "$lib/fonts" "$share"

# Tool.
cp "$bin/swiftui-screenshot" "$stage/bin/"

# Modules (the .swiftmodule directories carry the .swiftdoc next to the binary module) and libraries.
for m in SwiftUI Combine UIKit; do
  cp -r "$bin/$m.swiftmodule" "$lib/"
  cp "$bin/lib$m.so" "$lib/"
done

# Skia, plus the symlink named after its SONAME (the loader looks that name up).
cp -L Vendor/skia/lib/libSkiaSharp.so "$lib/"
soname="$(objdump -p "$lib/libSkiaSharp.so" | awk '$1 == "SONAME" { print $2 }')"
if [ -n "$soname" ] && [ "$soname" != libSkiaSharp.so ]; then ln -s libSkiaSharp.so "$lib/$soname"; fi

# Open fonts and their licences.
find Vendor/fonts -maxdepth 1 -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*LICENSE*' \) -exec cp {} "$lib/fonts/" \;

# Relocatability. The build links libSwiftUI.so with absolute rpaths (toolchain and Vendor/skia/lib)
# next to $ORIGIN; keep only $ORIGIN so libSkiaSharp is found beside it, wherever the tree lives.
for so in "$lib"/libSwiftUI.so "$lib"/libCombine.so "$lib"/libUIKit.so "$lib"/libSkiaSharp.so; do
  patchelf --set-rpath '$ORIGIN' "$so"
done
# The tool itself only needs the Swift runtime of the toolchain it is used with (it also needs one to
# compile anything). Look in the usual toolchain locations; LD_LIBRARY_PATH still overrides.
patchelf --set-rpath '/opt/swift/usr/lib/swift/linux:/usr/lib/swift/linux:/usr/local/swift/usr/lib/swift/linux' "$stage/bin/swiftui-screenshot"

# Check: no runpath may point into the build tree or Vendor/.
for f in "$stage/bin/swiftui-screenshot" "$lib"/*.so; do
  rp="$(readelf -d "$f" | sed -n 's/.*\(RUNPATH\|RPATH\).*\[\(.*\)\]/\2/p')"
  case "$rp" in
    *"$root"*|*Vendor*|*.build*) echo "make-dist: $f has a build-tree runpath: $rp" >&2; exit 1 ;;
  esac
  case "$f" in "$lib"/*) [ -z "$rp" ] || [ "$rp" = '$ORIGIN' ] || { echo "make-dist: $f runpath is '$rp'" >&2; exit 1; } ;; esac
done

# Notices.
{
  echo "swiftui-screenshot bundles or links the third-party components below."
  echo "SwiftUI, SF Pro and SF Symbols are trademarks of Apple Inc.; this project contains no Apple code, fonts or artwork."
  echo
  echo "================================================================================"
  echo "Skia and SkiaSharp (libSkiaSharp.so), and the components they incorporate, including HarfBuzz"
  echo "================================================================================"
  cat Vendor/skia/LICENSE.txt
  echo
  cat Vendor/skia/THIRD-PARTY-NOTICES.txt
  echo
  echo "================================================================================"
  echo "HarfBuzz (libharfbuzz0b, installed from the distribution package, not bundled)"
  echo "================================================================================"
  echo "Licensed under the 'Old MIT' licence; the full text is in the Skia/HarfBuzz section above."
  echo
  echo "================================================================================"
  echo "Open fonts"
  echo "================================================================================"
  cat scripts/dist/font-notices.txt
  tail -n +7 Vendor/fonts/Inter-LICENSE.txt
  echo
  echo "================================================================================"
  echo "Phosphor Icons (symbol artwork compiled into the SwiftUI module)"
  echo "================================================================================"
  cat Sources/SwiftUI/Symbols/LICENSE-phosphor-icons.txt
} > "$share/THIRD-PARTY-NOTICES"
cp "$share/THIRD-PARTY-NOTICES" "$lib/fonts/LICENSES.txt"

cp scripts/fetch-apple-fonts.sh "$share/"
chmod 755 "$share/fetch-apple-fonts.sh"

cat > "$share/VERSION" <<EOF
version: $version
commit: $commit
swift: $swift_banner
swift_version: $swift_version
arch: $arch
EOF

# Never ship Apple's fonts.
if find "$stage" \( -iname 'SF-*' -o -iname 'NewYork*' -o -iname 'apple-fonts' \) | grep -q .; then
  echo "make-dist: Apple font files found in the tree; refusing to package" >&2; exit 1
fi

mkdir -p "$root/dist"
tarball="$root/dist/$name.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner -C "$root/dist/stage" -cf - swiftui-screenshot | gzip -9n > "$tarball"
rm -rf "$root/dist/stage"
echo "$tarball ($(du -h "$tarball" | cut -f1))"
