#!/usr/bin/env bash
# Checks the Linux Markdown parser (MarkdownInline in Sources/SwiftUIScreenshotFoundation/FoundationGaps.swift,
# compiled only on Linux) against Apple's AttributedString(markdown:) on this Mac: characters, inline intents
# and block intents of every run must be the same for each input in scripts/mac/markdown/main.swift.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
python3 - "$root/Sources/SwiftUIScreenshotFoundation/FoundationGaps.swift" "$work/ours.swift" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = s.index('enum MarkdownInline {'); b = s.index('// MARK: - URLSession byte streams')
open(sys.argv[2], 'w').write('import Foundation\n' + s[a:b])
PY
cp "$root/scripts/mac/markdown/main.swift" "$work/main.swift"
swiftc "$work/ours.swift" "$work/main.swift" -o "$work/check"
"$work/check"
