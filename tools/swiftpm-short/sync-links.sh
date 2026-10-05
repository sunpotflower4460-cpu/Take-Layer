#!/usr/bin/env bash
# Recreates the symlinks of the macOS test package from tools/core-files.txt + tools/rendering-files.txt.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$HERE/Sources/TakeLayerShortKit"; TST="$HERE/Tests/TakeLayerShortKitTests"
find "$SRC" "$TST" -type l -delete
while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"; [ -z "$line" ] && continue
  ln -s "../../../../$line" "$SRC/$(basename "$line")"
done < <(cat "$ROOT/tools/core-files.txt" "$ROOT/tools/rendering-files.txt")
for t in TimelineMapperTests ShortFoundationTests; do ln -s "../../../../TakeLayerTests/$t.swift" "$TST/$t.swift"; done
