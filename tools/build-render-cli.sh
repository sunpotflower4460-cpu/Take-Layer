#!/usr/bin/env bash
# Builds take-layer-render from the SAME source files the iOS app uses (Core + Short renderer),
# plus tools/render/*. macOS only. Output: $BUILD_ROOT/take-layer-render
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${TMPDIR:-/tmp}/TakeLayerRender"
mkdir -p "$BUILD_ROOT"
files=()
while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"
  [ -n "$line" ] && files+=("$REPO_ROOT/$line")
done < <(cat "$REPO_ROOT/tools/core-files.txt" "$REPO_ROOT/tools/rendering-files.txt")
xcrun swiftc "${files[@]}" "$REPO_ROOT"/tools/render/*.swift -o "$BUILD_ROOT/take-layer-render"
echo "$BUILD_ROOT/take-layer-render"
