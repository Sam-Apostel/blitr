#!/bin/bash
# Usage: fetch-corpus.sh <dest-dir>   (dest must be OUTSIDE the repo). Shallow-clones corpus.txt at pinned commits.
set -u
DEST=${1:?dest dir}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$DEST"; cd "$DEST"
grep -v '^#' "$HERE/corpus.txt" | while read -r name repo sha platforms; do
  [ -z "$name" ] && continue
  (
    [ -d "$name" ] && exit 0
    if [ "$sha" = "HEAD" ]; then
      git clone -q --depth 1 "https://github.com/$repo.git" "$name"
    else
      mkdir "$name" && cd "$name" && git init -q && git remote add origin "https://github.com/$repo.git" \
        && git fetch -q --depth 1 origin "$sha" && git checkout -q FETCH_HEAD
    fi
    echo "fetched $name"
  ) &
done
wait
for d in */; do echo "$d $(git -C "$d" rev-parse HEAD)"; done
