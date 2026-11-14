#!/bin/bash
# Reproduces the API coverage measurement end to end.
#
#   scripts/api-coverage/run-all.sh <work-dir> [--extra name=dir:plat1,plat2 ...] [--private name1,name2]
#
# <work-dir> must be outside the repository: it receives the downloaded corpus (never built or run),
# the symbol graphs, the parsed usage and the intermediate JSON.
# --extra adds a local corpus directory (e.g. a private checkout) next to the committed public list;
# --private marks extra corpora whose results the public document only aggregates.
# Requires: a Swift 6 toolchain on PATH, python3, network access to github.com (corpus download),
# and the repository's `swift build` prerequisites (Vendor/ symlink).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
WORK=${1:?work dir}; shift
EXTRA=(); PRIVATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --extra) EXTRA+=("$2"); shift 2 ;;
    --private) PRIVATE="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
case "$WORK" in "$REPO"*) echo "work dir must be outside the repository" >&2; exit 2 ;; esac
export SWIFTC=${SWIFTC:-$(command -v swiftc)}

echo "== 1. corpus"
"$HERE/fetch-corpus.sh" "$WORK/corpus"

echo "== 2. declaration index of our SwiftUI module (module interface + symbol graph)"
(cd "$REPO" && swift build --scratch-path "$WORK/ibuild" --product SwiftUI \
   -Xswiftc -emit-module-interface -Xswiftc -no-verify-emitted-module-interface)
BIN=$(cd "$REPO" && swift build --show-bin-path)
IFACE=$(find "$WORK/ibuild" -name SwiftUI.swiftinterface | head -1)
python3 -I "$HERE/parse_interface.py" "$IFACE" "$WORK/sigs.json"
SPEC=()
for m in SwiftUI Swift Foundation FoundationEssentials FoundationInternationalization FoundationNetworking Dispatch Observation Combine; do
  mkdir -p "$WORK/sg/$m"
  swift symbolgraph-extract -module-name "$m" -I "$BIN" -output-dir "$WORK/sg/$m" -minimum-access-level public -skip-synthesized-members >/dev/null 2>&1 || true
  SPEC+=("$m=$WORK/sg/$m")
done
python3 -I "$HERE/build_index.py" "$WORK/index.json" "${SPEC[@]}" 2>/dev/null

echo "== 3. extract usage (swiftc -dump-parse; nothing is built or run)"
ARGS=()
while read -r name repo sha plats; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue ;; esac
  ARGS+=("$name=$WORK/corpus/$name:$plats")
done < "$HERE/corpus.txt"
python3 -I "$HERE/extract.py" "$WORK/usage.json" --jobs "$(nproc)" "${ARGS[@]}" "${EXTRA[@]}"

echo "== 4. compare"
PRIV_ARGS=(); [ -n "$PRIVATE" ] && PRIV_ARGS=(--private "$PRIVATE")
python3 -I "$HERE/compare.py" "$WORK/index.json" "$WORK/compare.json" "${PRIV_ARGS[@]}" "$WORK/usage.json"

echo "== 5. confirm candidates by compiling (swiftui-screenshot)"
python3 -I "$HERE/confirm.py" "$WORK/compare.json" "$BIN/swiftui-screenshot" "$WORK/confirm.json" --workdir "$WORK"
python3 -I "$HERE/confirm.py" --manual "$HERE/manual_checks.json" "$BIN/swiftui-screenshot" "$WORK/manual.json" "$WORK" >/dev/null

echo "== 6. report"
python3 -I "$HERE/report.py" "$WORK/compare.json" "$WORK/confirm.json" "$WORK/manual.json" "$WORK/usage.json" \
  --out "$WORK/API-GAPS.md" --private-out "$WORK/private-report.txt"
echo "wrote $WORK/API-GAPS.md (copy to docs/API-GAPS.md); $WORK/private-report.txt is local only"
