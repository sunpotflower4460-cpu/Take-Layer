#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${TMPDIR:-/tmp}/TakeLayerResolverCalibration"
mkdir -p "$BUILD_ROOT"
BINARY="$BUILD_ROOT/resolver-calibration"

xcrun swiftc \
  "$REPO_ROOT/TakeLayer/Models/SongMemoryModels.swift" \
  "$REPO_ROOT/TakeLayer/Models/SongResolverEvidenceModels.swift" \
  "$REPO_ROOT/TakeLayer/Models/ResolverCalibrationModels.swift" \
  "$REPO_ROOT/TakeLayer/Models/ResolverPrivateCorpusModels.swift" \
  "$REPO_ROOT/TakeLayer/Services/TonalEvidenceExtractor.swift" \
  "$REPO_ROOT/TakeLayer/Services/AudioEvidenceExtractor.swift" \
  "$REPO_ROOT/TakeLayer/Services/SongResolver.swift" \
  "$REPO_ROOT/TakeLayer/Services/ResolverCalibrationHarness.swift" \
  "$REPO_ROOT/TakeLayer/Services/ResolverPrivateCorpusRunner.swift" \
  "$REPO_ROOT/tools/ResolverCalibrationCLI.swift" \
  -o "$BINARY"

"$BINARY" "$@"
