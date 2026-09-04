# Phase 7: Private Corpus Runner

## Status

**Merged on `main`.**

The runner is the measurement substrate used by the currently active **Phase 7 Real Corpus Measurement** gate.

Prerequisites merged on `main`:

- human-confirmed Song Memory,
- Resolver Evidence Foundation,
- Tonal Evidence Foundation,
- Elastic Tonal Alignment,
- Resolver Calibration Harness.

## Goal

Make empirical Resolver calibration repeatable with real local audio without committing or uploading raw WAV files.

This gate is developer tooling only. It does not change production Resolver thresholds, weights, identity adoption, synchronization, or editing behavior.

## Workflow

A local manifest describes labeled WAV pairs using paths relative to one private corpus root:

```json
{
  "schemaVersion": 1,
  "name": "local benchmark",
  "cases": [
    {
      "name": "studio vs acoustic",
      "relationship": "sameSongDifferentArrangement",
      "queryPath": "songs/song-a/acoustic.wav",
      "referencePath": "songs/song-a/studio.wav"
    }
  ]
}
```

The developer runs:

```bash
bash tools/run-resolver-calibration.sh \
  --manifest ResolverBenchmarks/Private/manifest.json
```

The runner:

1. validates the manifest and effective case IDs,
2. preflights every referenced WAV path inside the configured corpus root before evidence extraction begins,
3. extracts production `AudioEvidenceVector` values once per unique resolved WAV URL for that dataset build,
4. reuses cached evidence when one WAV appears in multiple labeled pairs,
5. creates stable labeled calibration cases,
6. evaluates them through the merged `ResolverCalibrationHarness`,
7. writes a derived dataset and calibration report.

Preflight is intentionally completed before signal analysis so a missing or invalid path in a later case does not waste earlier audio-analysis work.

## Privacy and path safety

- `ResolverBenchmarks/Private/` remains gitignored.
- Manifest audio paths must be relative.
- Absolute paths and `~` paths are rejected.
- Normalized or symlink-resolved paths may not escape the corpus root.
- Only WAV files are accepted in this gate.
- Raw WAV bytes are never serialized into the derived dataset or report.
- No network upload is performed.
- The evidence cache is in-memory and per dataset build; no new persistent audio cache is created.

## Stable case identity

A manifest case may provide an explicit UUID.

If omitted, the runner derives a deterministic UUID from:

- manifest name,
- case name,
- relationship label,
- query relative path,
- reference relative path.

This keeps repeated local runs comparable without storing raw media hashes as benchmark IDs. Duplicate effective case IDs fail explicitly before audio evidence extraction starts.

## Developer CLI

`tools/run-resolver-calibration.sh` compiles a small macOS Swift executable from the same source files used by TakeLayer's Resolver and Evidence pipeline.

Supported arguments:

- `--manifest <path>` required,
- `--root <directory>` optional,
- `--dataset <path>` optional,
- `--report <path>` optional,
- `--thresholds <csv>` optional diagnostic sweep,
- `--help`.

Default output filenames are `derived-dataset.json` and `report.json` under the corpus root.

CI calls the CLI with `--help` so source-level drift in the developer runner is caught even though private WAVs are unavailable in CI.

## Required tests

The merged/maintained runner must keep these behaviors covered:

- local synthetic WAVs can be loaded through a manifest and converted into a calibration dataset,
- repeated builds of the same manifest produce the same derived case ID,
- dataset/report files can be generated,
- absolute audio paths are rejected,
- parent-directory traversal outside the corpus root is rejected,
- duplicate explicit case IDs are rejected,
- all case paths are preflighted before evidence extraction starts,
- repeated references to the same resolved WAV are extracted only once per dataset build,
- CLI compilation succeeds on the macOS CI runner,
- all existing TimelineMapper / Short / Song Memory / Resolver / Tonal / Elastic / Calibration tests remain green,
- iOS Simulator build and XCTest pass.

## Explicitly not implemented

- Automatic production threshold selection.
- Automatic Resolver weight optimization.
- Automatic Song / Arrangement adoption.
- Uploading benchmark WAVs or private datasets.
- Cloud benchmark storage.
- Persistent cross-run evidence caching.
- Song-section labeling.
- Melody contour evidence.
- Lyrics identity evidence.
- External metadata lookup.
- AI Short Director.
- Preference learning.

## Current use

The active `phase-7-real-corpus-measurement.md` gate should use this runner to collect and inspect real labeled results.

If negatives overlap positives, classify why first: similar harmony, weak energy/transient discrimination, arrangement structure differences, melody ambiguity, or insufficient fingerprint uniqueness. Only then choose whether the next gate should be stronger landmark evidence, melody contour evidence, section understanding, or a reviewed scoring calibration.
