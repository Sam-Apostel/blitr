#!/usr/bin/env bash
# Installs blitr (a Linux CLI that renders SwiftUI source to PNG) from a release tarball.
# Written for an unattended root setup script: idempotent, quiet on success, one-line error on failure.
#
#   install.sh [--prefix /opt/blitr] [--version vX.Y.Z] [--from <url-or-path-to-tarball>]
#              [--apple-fonts --accept-apple-font-license] [--claude-instructions]
#              [--bin-dir /usr/local/bin] [--swift-dir /opt/swift]
#
#   --prefix        Where the tree is unpacked (default /opt/blitr).
#   --version       Release tag to install (default: the latest release).
#   --from          A tarball path or URL instead of the GitHub release. For a URL, <url>.sha256 is verified;
#                   for a path, <path>.sha256 is verified if it exists.
#   --apple-fonts   Also download Apple's fonts from Apple (needs --accept-apple-font-license).
#   --claude-instructions
#                   Add (or refresh) a short block in ~/.claude/CLAUDE.md that tells a coding agent about the tool.
#   --bin-dir       Where the `blitr` symlink goes (default /usr/local/bin).
#   --swift-dir     Where a missing Swift toolchain is installed (default /opt/swift).
#
# Releases are fetched from https://github.com/Sam-Apostel/blitr.
# shellcheck disable=SC2015  # `[ a ] && [ b ] || die` is intended
set -Eeuo pipefail

REPO="Sam-Apostel/blitr"
prefix=/opt/blitr
bin_dir=/usr/local/bin
swift_dir=/opt/swift
version=""
from=""
apple_fonts=0
apple_accepted=0
claude_instructions=0

die() { echo "install.sh: error: $*" >&2; exit 1; }
trap 'die "unexpected failure at line $LINENO ($BASH_COMMAND)"' ERR

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix="$2"; shift ;;
    --version) [ $# -ge 2 ] || die "--version needs a value"; version="$2"; shift ;;
    --from) [ $# -ge 2 ] || die "--from needs a value"; from="$2"; shift ;;
    --bin-dir) [ $# -ge 2 ] || die "--bin-dir needs a value"; bin_dir="$2"; shift ;;
    --swift-dir) [ $# -ge 2 ] || die "--swift-dir needs a value"; swift_dir="$2"; shift ;;
    --apple-fonts) apple_fonts=1 ;;
    --accept-apple-font-license) apple_accepted=1 ;;
    --claude-instructions) claude_instructions=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
  shift
done
if [ "$apple_fonts" = 1 ] && [ "$apple_accepted" != 1 ]; then
  die "--apple-fonts also needs --accept-apple-font-license (terms: https://developer.apple.com/fonts/)"
fi
[ "$(uname -s)" = Linux ] || die "only Linux is supported"
case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  aarch64|arm64) arch=aarch64 ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; [ -z "${staging:-}" ] || rm -rf "$staging"; }
trap cleanup EXIT

# Runs a command with its output captured; shows the tail of the log only if it fails.
quiet() { # description command...
  local what="$1"; shift
  if ! "$@" >"$tmp/log" 2>&1; then
    tail -n 8 "$tmp/log" | sed 's/^/    /' >&2
    die "$what failed"
  fi
}

SUDO=""
if [ "$(id -u)" -ne 0 ]; then command -v sudo >/dev/null 2>&1 && SUDO="sudo"; fi
APT_UPDATED=0
apt_install() { # packages...
  command -v apt-get >/dev/null 2>&1 || die "missing packages ($*) and apt-get is not available"
  [ "$(id -u)" -eq 0 ] || [ -n "$SUDO" ] || die "missing packages ($*); re-run as root to install them"
  export DEBIAN_FRONTEND=noninteractive
  if [ "$APT_UPDATED" = 0 ]; then quiet "apt-get update" $SUDO apt-get -qq update; APT_UPDATED=1; fi
  quiet "apt-get install $*" $SUDO apt-get -qq install -y --no-install-recommends "$@"
}
need_packages() { # packages...: installs the ones dpkg does not know
  command -v dpkg >/dev/null 2>&1 || return 0
  local missing=() p
  for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  [ ${#missing[@]} -eq 0 ] || apt_install "${missing[@]}"
}

need_packages curl ca-certificates libharfbuzz0b
[ "$apple_fonts" = 0 ] || need_packages 7zip

download() { # url dest
  local code
  code="$(curl -sSL --retry 3 --retry-delay 2 -w '%{http_code}' -o "$2" "$1" 2>"$tmp/curl.err")" || code=000
  if [ "$code" != 200 ]; then
    local hint=""
    case "$code" in 404|401|403) hint=" (the release assets may be private: download them and use --from)" ;; esac
    die "download of $1 failed (HTTP $code)$hint"
  fi
}

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

verify_sha() { # file sha-file
  local want have
  want="$(awk 'NR == 1 { print $1 }' "$2")"
  have="$(sha_of "$1")"
  [ -n "$want" ] && [ "$want" = "$have" ] || die "checksum mismatch for $(basename "$1") (expected ${want:-nothing}, got $have)"
}

# 1. The tarball.
tarball=""
case "$from" in
  "")
    if [ -z "$version" ]; then
      # Resolve "latest" through the redirect so no API token is needed.
      latest="$(curl -sSL --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null || true)"
      version="${latest##*/}"
      case "$version" in v*) ;; *) die "could not find the latest release of $REPO (is it published, and public? otherwise use --from)" ;; esac
    fi
    asset="blitr-$version-linux-$arch.tar.gz"
    url="https://github.com/$REPO/releases/download/$version/$asset"
    download "$url" "$tmp/$asset"
    download "$url.sha256" "$tmp/$asset.sha256"
    verify_sha "$tmp/$asset" "$tmp/$asset.sha256"
    tarball="$tmp/$asset"
    ;;
  http://*|https://*)
    asset="$(basename "${from%%\?*}")"
    download "$from" "$tmp/$asset"
    download "$from.sha256" "$tmp/$asset.sha256"
    verify_sha "$tmp/$asset" "$tmp/$asset.sha256"
    tarball="$tmp/$asset"
    ;;
  *)
    [ -f "$from" ] || die "--from: no such file $from"
    tarball="$from"
    [ ! -f "$from.sha256" ] || verify_sha "$from" "$from.sha256"
    ;;
esac

# 2. Unpack next to the prefix, then swap it in.
mkdir -p "$(dirname "$prefix")"
staging="$(mktemp -d "$(dirname "$prefix")/.blitr.XXXXXX")"
quiet "unpacking $(basename "$tarball")" tar -xzf "$tarball" -C "$staging" --strip-components=1 --no-same-owner
[ -x "$staging/bin/blitr" ] && [ -f "$staging/share/blitr/VERSION" ] \
  || die "$(basename "$tarball") does not look like a blitr release"
info() { sed -n "s/^$1: *//p" "$staging/share/blitr/VERSION" | head -n 1; }
[ "$(info arch)" = "$arch" ] || die "this tarball is for $(info arch), this machine is $arch"
tool_version="$(info version)"
swift_version="$(info swift_version)"
[ -n "$swift_version" ] || die "the tarball's VERSION file does not say which Swift version it needs"

if [ -f "$prefix/share/blitr/VERSION" ] && cmp -s "$prefix/share/blitr/VERSION" "$staging/share/blitr/VERSION"; then
  rm -rf "$staging"; staging=""   # already installed
else
  # Keep Apple's fonts across an upgrade.
  if [ -d "$prefix/lib/blitr/apple-fonts" ]; then
    cp -a "$prefix/lib/blitr/apple-fonts" "$staging/lib/blitr/apple-fonts"
  fi
  rm -rf "$prefix.old"
  [ ! -e "$prefix" ] || mv "$prefix" "$prefix.old"
  mv "$staging" "$prefix"; staging=""
  rm -rf "$prefix.old"
  chmod 755 "$prefix"
fi

# 3. The Swift toolchain, pinned to the version the modules were built with.
swift_matches() { # path to swiftc
  [ -x "$1" ] && "$1" --version 2>/dev/null | grep -q "Swift version $swift_version "
}
swiftc_path=""
for candidate in "$(command -v swiftc 2>/dev/null || true)" "$swift_dir/usr/bin/swiftc" /opt/swift/usr/bin/swiftc; do
  if [ -n "$candidate" ] && swift_matches "$candidate"; then swiftc_path="$candidate"; break; fi
done
if [ -z "$swiftc_path" ]; then
  case "$swift_version" in
    [0-9]*.[0-9]*|[0-9]*.[0-9]*.[0-9]*) ;;
    *) die "the tarball needs Swift $swift_version, which is not a release toolchain that can be downloaded" ;;
  esac
  [ -r /etc/os-release ] || die "cannot tell which Linux this is (no /etc/os-release)"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:24.04) platform=ubuntu24.04 ;;
    ubuntu:22.04) platform=ubuntu22.04 ;;
    *) die "no Swift $swift_version toolchain is downloaded for ${PRETTY_NAME:-this system}; install it yourself and put swiftc on PATH" ;;
  esac
  suffix=""; [ "$arch" = aarch64 ] && suffix="-aarch64"
  # Runtime and build dependencies of the toolchain, as listed on swift.org for Ubuntu 24.04.
  need_packages binutils git unzip gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libpython3-dev \
    libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata zlib1g-dev
  branch="swift-$swift_version-release"
  name="swift-$swift_version-RELEASE"
  url="https://download.swift.org/$branch/${platform//./}$suffix/$name/$name-$platform$suffix.tar.gz"
  mkdir -p "$tmp/swift"
  # Streamed straight into tar: the archive is about 1 GB and need not touch the disk.
  if ! curl -fsSL --retry 3 --retry-delay 2 "$url" 2>"$tmp/curl.err" | tar -xz -C "$tmp/swift" --strip-components=1 2>"$tmp/tar.err"; then
    die "downloading the Swift $swift_version toolchain from $url failed: $(tail -n 1 "$tmp/curl.err" "$tmp/tar.err" | tr '\n' ' ')"
  fi
  [ -x "$tmp/swift/usr/bin/swiftc" ] || die "the Swift toolchain archive from $url has no swiftc"
  mkdir -p "$(dirname "$swift_dir")"
  rm -rf "$swift_dir.old"
  [ ! -e "$swift_dir" ] || mv "$swift_dir" "$swift_dir.old"
  mv "$tmp/swift" "$swift_dir"
  rm -rf "$swift_dir.old"
  swiftc_path="$swift_dir/usr/bin/swiftc"
fi

# 4. The command.
mkdir -p "$bin_dir"
ln -sfn "$prefix/bin/blitr" "$bin_dir/blitr"

# 5. Apple's fonts, only on request.
if [ "$apple_fonts" = 1 ] && [ ! -f "$prefix/lib/blitr/apple-fonts/SF-Pro.ttf" ]; then
  quiet "fetching Apple fonts" "$prefix/share/blitr/fetch-apple-fonts.sh" --accept-apple-font-license
fi

# 6. A note for coding agents.
if [ "$claude_instructions" = 1 ]; then
  claude_md="${HOME:?HOME is not set}/.claude/CLAUDE.md"
  begin='<!-- BEGIN blitr (written by install.sh; re-running it replaces this block) -->'
  end='<!-- END blitr -->'
  cat > "$tmp/block" <<EOF
$begin
## blitr
\`blitr\` is installed. It renders SwiftUI source to PNG without Xcode or a simulator, by compiling
your sources against its own SwiftUI implementation. Use it after changing SwiftUI code to see the result.
- \`blitr render File.swift --all --out-dir out/\` writes one PNG per #Preview / PreviewProvider
  (\`--preview <n|name>\` for one, \`--view "MyView()"\` for an expression).
- \`--scheme both\` renders light and dark, \`--device iphone-16|ipad|...\` picks a device (\`blitr devices\`),
  \`--layout fit\` renders just the view, \`--crop <identifier>\` one part of the screen.
- \`--locale\`, \`--time-zone\`, \`--date\` and \`--location\` set the device's state; renders are offline unless
  \`--allow-network\`.
- \`blitr list File.swift\` shows the previews; \`--json\` prints one JSON object per image.
- Anything not rendered faithfully (unmapped SF Symbol, missing asset, UIKit view) is reported as a
  \`warning:\` line on stderr, or in the \`warnings\` field with \`--json\`. Read them.
- Read the PNG files to check layout and appearance of UI work.
- A compile error naming a SwiftUI API that does not exist means the renderer lacks it. That is a limit of
  the tool, not a bug in the user's code: do not rewrite working code to avoid it; render a smaller view and say so.
- \`blitr doctor\` checks the installation; \`blitr version\` prints versions.
$end
EOF
  mkdir -p "$(dirname "$claude_md")"
  if [ -f "$claude_md" ] && grep -qF 'BEGIN blitr' "$claude_md"; then
    grep -qF "$end" "$claude_md" || die "$claude_md has a blitr block without its END marker; fix it by hand"
    # Replace everything between the markers (inclusive) with the new block.
    awk -v blockfile="$tmp/block" '
      /BEGIN blitr/ && !done { while ((getline line < blockfile) > 0) print line; skipping = 1; next }
      skipping && /END blitr/ { skipping = 0; done = 1; next }
      !skipping { print }
    ' "$claude_md" > "$tmp/CLAUDE.md"
    cat "$tmp/CLAUDE.md" > "$claude_md"
  else
    if [ -s "$claude_md" ]; then
      [ -z "$(tail -c 1 "$claude_md")" ] || echo >> "$claude_md"
      echo >> "$claude_md"
    fi
    cat "$tmp/block" >> "$claude_md"
  fi
fi

# 7. Check it works.
swift_bin="$(dirname "$swiftc_path")"
if ! PATH="$swift_bin:$PATH" "$bin_dir/blitr" doctor >"$tmp/doctor" 2>&1; then
  sed 's/^/    /' "$tmp/doctor" >&2
  die "blitr doctor reported a problem (output above)"
fi
echo "blitr $tool_version installed in $prefix (Swift $swift_version at $swift_bin)"
