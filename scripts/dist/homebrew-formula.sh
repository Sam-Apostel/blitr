#!/usr/bin/env bash
# Prints the Homebrew formula for a release, from its macOS tarballs' checksum files.
#
#   scripts/dist/homebrew-formula.sh v0.1.0 assets/ > Formula/blitr.rb
#
# The formula installs the prebuilt macOS tarball. It is macOS only: on Linux a release needs the exact Swift
# toolchain it was built with, which install.sh and the npm package fetch.
set -euo pipefail
tag="${1:?usage: homebrew-formula.sh TAG ASSET_DIR}"
assets="${2:?usage: homebrew-formula.sh TAG ASSET_DIR}"
version="${tag#v}"
base="${BLITR_FORMULA_BASE_URL:-https://github.com/Sam-Apostel/blitr/releases/download/$tag}"

sha() { awk 'NR == 1 { print $1 }' "$assets/blitr-$tag-macos-$1.tar.gz.sha256"; }

cat <<EOF
class Blitr < Formula
  desc "Render SwiftUI previews to PNG without a simulator"
  homepage "https://github.com/Sam-Apostel/blitr"
  version "$version"
  license "MIT"

  depends_on :macos

  on_arm do
    url "$base/blitr-$tag-macos-arm64.tar.gz"
    sha256 "$(sha arm64)"
  end
EOF
if [ -f "$assets/blitr-$tag-macos-x86_64.tar.gz.sha256" ]; then
  cat <<EOF
  on_intel do
    url "$base/blitr-$tag-macos-x86_64.tar.gz"
    sha256 "$(sha x86_64)"
  end
EOF
fi
cat <<'EOF'

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/blitr"
  end

  def caveats
    <<~TEXT
      blitr compiles your SwiftUI code with Xcode's Swift compiler (or the Command Line Tools':
      xcode-select --install). For Apple's own fonts instead of the open substitutes, run:
        #{opt_libexec}/share/blitr/fetch-apple-fonts.sh --accept-apple-font-license
    TEXT
  end

  test do
    (testpath/"Hello.swift").write <<~SWIFT
      import SwiftUI
      #Preview { Text("Hello") }
    SWIFT
    ENV["BLITR_CACHE"] = testpath/"cache"
    system bin/"blitr", "render", testpath/"Hello.swift", "-o", testpath/"hello.png"
    assert_path_exists testpath/"hello.png"
  end
end
EOF
