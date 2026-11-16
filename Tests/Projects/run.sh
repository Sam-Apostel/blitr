#!/bin/bash
# Project-mode tests: renders the Orchard fixture through every project reader and checks what the
# tool printed. Run from the repository root after `swift build`:
#
#     Tests/Projects/run.sh [output-directory]
#
# Exits non-zero at the first failed check.
set -u
cd "$(dirname "$0")/../.."
bin="$(swift build --show-bin-path)/swiftui-screenshot"
out="${1:-out/Projects}"
fixture=Tests/Projects/Orchard
mkdir -p "$out"
log="$out/log.txt"
failures=0

check() {  # check <description> <command...>: the command must succeed
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}
run() {  # run <expected exit status> <args...>: runs the tool, output to $log
  local expected="$1"; shift
  timeout 900 "$bin" "$@" >"$log" 2>&1
  local status=$?
  if [ "$status" != "$expected" ]; then
    echo "FAIL  exit $status (expected $expected): swiftui-screenshot $*"; sed 's/^/      /' "$log" | tail -25; failures=$((failures + 1)); return 1
  fi
}
has() { grep -q -- "$1" "$log"; }
lacks() { ! grep -q -- "$1" "$log"; }

echo "== discovery and render (XcodeGen spec found from the file)"
run 0 render $fixture/App/Sources/HarvestListView.swift --all --scheme both --open-fonts -v --out-dir "$out/list"
check "the spec and target are found from the file" has "project.yml (XcodeGen), target Orchard (application, iOS 17.0)"
check "modules are built in dependency order" has "modules: OrchardKit \[package OrchardKit\], OrchardUI \[package OrchardUI\], Orchard \[target Orchard\]"
check "only the entry's closure is compiled" has "compiling 4 of 9 files of Orchard"
check "the remote package is reported by name" has "warning: SunCalc (remote package"
check "the package's font is found" lacks "Font \"OrchardPixel\" not found"
check "no asset is missing" lacks "not found"
check "both previews, both schemes" test "$(ls "$out/list" | wc -l | tr -d " ")" = 4

echo "== caching"
run 0 render $fixture/App/Sources/TreeDetailView.swift --open-fonts -v -o "$out/detail.png"
check "package modules come from the cache" has "module OrchardKit: cached"
check "the UI package comes from the cache" has "module OrchardUI: cached"
check "generated asset symbols and the catalog image resolve" lacks "not found"

echo "== localization"
run 0 render $fixture/App/Sources/HarvestListView.swift --open-fonts --accessibility-outline -o "$out/list-en.png"
check "development language by default" has "Orchard"
check "a key-style string resolves in the development language" lacks "orchard.title"
check "plural: one" has "1 harvest\b"
run 0 render $fixture/App/Sources/HarvestListView.swift --open-fonts --locale nl --accessibility-outline -o "$out/list-nl.png"
check "Text keys resolve in Dutch" has "Boomgaard"
check "interpolated keys resolve" has "Dag 211 van het seizoen"
check "String(localized:) in the Foundation-only package resolves" has "Beste boom: Old Bramley"
check "plural: other" has "2 oogsten"
check "plural: one" has "1 oogst\b"
check "the Dutch render differs from the English one" bash -c "! cmp -s '$out/list-en.png' '$out/list-nl.png'"
run 0 render $fixture/App/Sources/HarvestListView.swift --open-fonts --locale fr -o "$out/list-fr.png"
check "an unknown locale is reported" has "warning: no strings for locale fr"

echo "== Xcode project (pbxproj) describes the same thing"
run 0 render $fixture/App/Sources/HarvestListView.swift --project $fixture/Orchard.xcodeproj --open-fonts -v -o "$out/list-xcodeproj.png"
check "the Xcode project is used" has "Orchard.xcodeproj (Xcode project), target Orchard (application, iOS 17.0)"
check "synchronized folder minus its exception, plus the Sources phase" has "compiling 4 of 9 files of Orchard"
check "same picture as through the XcodeGen spec" cmp "$out/list-en.png" "$out/list-xcodeproj.png"
"$bin" list $fixture/App/Sources/HarvestListView.swift >"$out/list-xcodegen.txt" 2>/dev/null
"$bin" list $fixture/App/Sources/HarvestListView.swift --project $fixture/Orchard.xcodeproj >"$out/list-pbxproj.txt" 2>/dev/null
check "both readers list the same previews" cmp "$out/list-xcodegen.txt" "$out/list-pbxproj.txt"
check "list covers the whole target" test "$(wc -l <"$out/list-xcodegen.txt" | tr -d " ")" = 4

echo "== tvOS target"
run 0 render $fixture/TV/Sources/TVBoardView.swift --open-fonts -v -o "$out/tv.png"
check "the target's platform is the default --platform" has "target OrchardTV (application, tvOS 17.0)"
check "rendered on the Apple TV profile" has "3840x2160"

echo "== entry points"
run 0 render $fixture/App/Sources/TreeDetailView.swift --open-fonts --view "TreeRow(tree: SampleOrchard.state.trees[1]).padding()" --layout fit -v -o "$out/view.png"
check "--view pulls in what the expression names" has "HarvestListView.swift: declares TreeRow"
run 0 render --project $fixture --target Orchard --open-fonts -o "$out/app.png"
check "@main App renders its first window" test -s "$out/app.png"

echo "== a Swift package on its own"
run 0 render $fixture/OrchardUI/Sources/OrchardUI/WeightBadge.swift --open-fonts -v -o "$out/badge.png"
check "Package.swift is the project" has "Package.swift (Swift package), target OrchardUI"
check "Bundle.module resources (font, colors) resolve" lacks "not found"

echo "== unsupported code is reported, not rendered"
run 1 render $fixture/App/Sources/ToolsView.swift --open-fonts -o "$out/tools.png"
check "nothing is rendered" test ! -e "$out/tools.png"
check "the summary names the framework" has "ARKit: 1 file imports it"
run 1 render $fixture/App/Sources/HarvestListView.swift --whole-target --open-fonts -o "$out/whole.png"
check "--whole-target compiles the unsupported files too" has "Frameworks this renderer does not provide"
run 1 check $fixture/App/Sources/ToolsView.swift
check "check lists the framework and what is used from it" has "ARKit: 1 file imports it; uses ARWorldTrackingConfiguration ×2, ARSession ×1"
check "check lists the remote package's module" has "SunCalc: 1 file imports it"
"$bin" check --project $fixture --target Orchard --json >"$log" 2>/dev/null   # JSON on stdout, notes on stderr
check "check --json is JSON with the same content" python3 -c "
import json, sys
report = json.load(open('$log'))
assert report['ok'] is False and report['target'] == 'Orchard'
module = report['modules'][-1]
assert module['files'] == 9, module['files']
names = {f['name']: f for f in module['report']['frameworks']}
assert set(names) == {'ARKit', 'SunCalc'}, names
assert names['ARKit']['symbols'] == {'ARWorldTrackingConfiguration': 2, 'ARSession': 1}, names
assert not any('Scratchpad' in d['file'] for d in module['report']['diagnostics'])
"
run 0 check $fixture/App/Sources/HarvestListView.swift
check "check passes for a screen that compiles" has "ok     target Orchard (4 files)"

echo "== diagnostics"
run 1 render Tests/Projects/Diagnostics/LineNumbers.swift --no-project -o "$out/lines.png"
check "errors keep their line numbers after rewriting" has "LineNumbers.swift:27:30: error"
run 0 render Tests/Projects/Diagnostics/ExtensionOverrides.swift --no-project --open-fonts -o "$out/overrides.png"
check "an override in an extension is left out, named, with its line" has "ExtensionOverrides.swift:10: left out \`override open func viewDidLoad()\` in \`extension UINavigationController\`"
check "each override gets its own warning" has "ExtensionOverrides.swift:17: left out \`override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?)\` in \`extension UIWindow\`"
check "an override in a class body is kept" lacks "left out \`override var name"
# More than a pipe buffer (64 KB) of diagnostics used to deadlock the tool.
many="$out/ManyErrors.swift"
{ echo "import SwiftUI"; for i in $(seq 1 1500); do echo "let wrong$i: Int = \"a string, not an integer, to make the compiler print a long diagnostic number $i\""; done; echo '#Preview { Text("x") }'; } >"$many"
run 1 render "$many" --no-project -o "$out/many.png"
check "a compile with thousands of errors finishes and is summarized" has "Unsupported, from 1500 errors in 1 file"

echo
if [ "$failures" = 0 ]; then echo "all project-mode checks passed"; else echo "$failures check(s) failed"; exit 1; fi
