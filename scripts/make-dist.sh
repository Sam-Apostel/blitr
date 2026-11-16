#!/usr/bin/env bash
# Builds a relocatable release tarball:
#
#   dist/swiftui-screenshot-<version>-linux-<arch>.tar.gz     (dist/...-macos-<arch>.tar.gz on a Mac)
#
#   swiftui-screenshot/
#     bin/swiftui-screenshot
#     lib/swiftui-screenshot/   SwiftUI and shim modules, the engine library, libSkiaSharp, fonts/
#     share/swiftui-screenshot/ fetch-apple-fonts.sh, THIRD-PARTY-NOTICES, VERSION
#
# Usage: scripts/make-dist.sh [VERSION]     (default: git describe --tags --always)
# Needs Vendor/ (scripts/bootstrap.sh), the Swift toolchain on PATH, and patchelf
# (apt-get install -y patchelf). Apple's fonts (Vendor/apple-fonts) are never packaged.
# On macOS it needs Xcode's install_name_tool, otool and codesign instead of patchelf, and the tarball
# expects Homebrew's harfbuzz at run time.
# shellcheck disable=SC2015,SC2016  # `[ a ] && [ b ] || die` is intended; '$ORIGIN' must stay literal
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
root="$(pwd)"

if [ "$(uname -s)" = Darwin ]; then
  os=macos; ext=dylib; tools="swift install_name_tool otool codesign tar"
else
  os=linux; ext=so; tools="swift patchelf readelf objdump tar"
fi
engine=libSwiftUIScreenshotEngine.$ext

for tool in $tools; do
  command -v "$tool" >/dev/null || { echo "make-dist: '$tool' not found on PATH" >&2; exit 1; }
done
[ -f "Vendor/skia/lib/libSkiaSharp.$ext" ] && [ -d Vendor/fonts ] \
  || { echo "make-dist: Vendor/ is missing; run scripts/bootstrap.sh first" >&2; exit 1; }

version="${1:-${VERSION:-$(git describe --tags --always 2>/dev/null || echo dev)}}"
commit="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
case "$os-$(uname -m)" in
  linux-x86_64) arch=x86_64 ;;
  linux-aarch64|linux-arm64) arch=aarch64 ;;
  macos-x86_64) arch=x86_64 ;;
  macos-arm64) arch=arm64 ;;
  *) echo "make-dist: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
swift_banner="$(swiftc --version 2>&1 | grep -m1 'Swift version')"
swift_version="$(sed -E 's/^.*Swift version ([^ ]+).*$/\1/' <<<"$swift_banner")"
name="swiftui-screenshot-$version-$os-$arch"

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
# The shim frameworks (UIKit, MapKit, WidgetKit, ...) and Combine are modules whose code is in the engine
# library; so is the Foundation shim (docs/ARCHITECTURE.md, "Shim modules"). The module list is
# Package.swift's `shimModules`, so a new shim is one entry there.
shims="$(sed -n 's/^let shimModules = \[\(.*\)\]/\1/p' Package.swift | tr -d '",')"
# On macOS, Combine, ObjectiveC, Security, os and OSLog are Apple's (Package.swift's `appleProvided`).
for m in SwiftUI SwiftUIScreenshotFoundation $shims; do
  if [ -d "$bin/$m.swiftmodule" ]; then cp -r "$bin/$m.swiftmodule" "$lib/"
  elif [ "$os" = linux ]; then echo "make-dist: $m.swiftmodule was not built" >&2; exit 1; fi
done
cp "$bin/$engine" "$lib/"

# Skia. On Linux, plus the symlink named after its SONAME (the loader looks that name up); on macOS its
# install name is @rpath/libSkiaSharp.dylib, found through the engine's @loader_path.
cp -L "Vendor/skia/lib/libSkiaSharp.$ext" "$lib/"
if [ "$os" = linux ]; then
  soname="$(objdump -p "$lib/libSkiaSharp.so" | awk '$1 == "SONAME" { print $2 }')"
  if [ -n "$soname" ] && [ "$soname" != libSkiaSharp.so ]; then ln -s libSkiaSharp.so "$lib/$soname"; fi
fi

# Open fonts and their licences.
find Vendor/fonts -maxdepth 1 -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*LICENSE*' \) -exec cp {} "$lib/fonts/" \;

if [ "$os" = linux ]; then
  # Relocatability. The build links libSwiftUIScreenshotEngine.so with absolute rpaths (toolchain and
  # Vendor/skia/lib) next to $ORIGIN; keep only $ORIGIN so libSkiaSharp is found beside it, wherever the
  # tree lives.
  for so in "$lib"/*.so; do
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
else
  # Relocatability on macOS: the engine names itself @rpath/libSwiftUIScreenshotEngine.dylib (dependents find
  # it through their rpaths) and keeps only @loader_path, so libSkiaSharp is found beside it. The Swift
  # runtime is the system's (/usr/lib/swift), so the tool keeps only rpaths there. Rewriting load commands
  # breaks the signature, so each file is signed again (ad hoc), as arm64 requires.
  rpaths() { otool -l "$1" | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }'; }
  install_name_tool -id "@rpath/$engine" "$lib/$engine"
  for f in "$lib/$engine" "$stage/bin/swiftui-screenshot"; do
    keep='@loader_path'; [ "$f" = "$stage/bin/swiftui-screenshot" ] && keep='/usr/lib/swift'
    while read -r rp; do
      if [ -n "$rp" ] && [ "$rp" != "$keep" ]; then install_name_tool -delete_rpath "$rp" "$f"; fi
    done <<<"$(rpaths "$f")"
    rpaths "$f" | grep -qxF "$keep" || install_name_tool -add_rpath "$keep" "$f"
    codesign --force --sign - "$f"
  done

  # Check: no rpath or load command may point into the build tree or Vendor/.
  for f in "$stage/bin/swiftui-screenshot" "$lib"/*.dylib; do
    if otool -l "$f" | grep -E '^ +(path|name) ' | grep -qE "$root|Vendor|\.build"; then
      echo "make-dist: $f refers to the build tree:" >&2; otool -l "$f" | grep -E '^ +(path|name) ' >&2; exit 1
    fi
  done
fi

# Notices.
{
  echo "swiftui-screenshot bundles or links the third-party components below."
  echo "SwiftUI, SF Pro and SF Symbols are trademarks of Apple Inc.; this project contains no Apple code, fonts or artwork."
  echo
  echo "================================================================================"
  echo "Skia and SkiaSharp (libSkiaSharp.$ext), and the components they incorporate, including HarfBuzz"
  echo "================================================================================"
  cat Vendor/skia/LICENSE.txt
  echo
  cat Vendor/skia/THIRD-PARTY-NOTICES.txt
  echo
  echo "================================================================================"
  if [ "$os" = linux ]; then
    echo "HarfBuzz (libharfbuzz0b, installed from the distribution package, not bundled)"
  else
    echo "HarfBuzz (Homebrew's harfbuzz, installed separately, not bundled)"
  fi
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
if [ "$os" = linux ]; then
  tar --sort=name --owner=0 --group=0 --numeric-owner -C "$root/dist/stage" -cf - swiftui-screenshot | gzip -9n > "$tarball"
else
  # bsdtar: no --sort; owner and group by number.
  tar --uid 0 --gid 0 --numeric-owner -C "$root/dist/stage" -cf - swiftui-screenshot | gzip -9n > "$tarball"
fi
rm -rf "$root/dist/stage"
echo "$tarball ($(du -h "$tarball" | cut -f1))"
