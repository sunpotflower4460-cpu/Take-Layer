# Phase 7: Resolver Calibration Harness

## Status

Active branch: `phase-7-resolver-calibration-harness`.

Prerequisites merged on `main`:

- human-confirmed Song Memory,
- deterministic Resolver Evidence,
- transposition-aware Tonal Evidence,
- bounded Elastic Tonal Alignment.

## Goal

Stop guessing what a "good" Song Resolver confidence means.

This gate adds a deterministic offline / developer-facing benchmark harness that can measure Resolver behavior against labeled evidence pairs before any confidence threshold or automatic decision policy is introduced.

The harness answers questions such as:

- How high do confirmed same-Arrangement pairs score?
- How high do confirmed same-song / different-Arrangement pairs score?
- How high do known different-song pairs score?
- Do the positive and negative confidence ranges overlap?
- At a candidate threshold, what are precision, recall, specificity, F1, and balanced accuracy?

It does **not** automatically change Resolver weights, thresholds, Song Memory links, synchronization, or editing decisions.

## Dataset relationships

Every `ResolverCalibrationCase` has one explicit human label:

```text
sameArrangement
sameSongDifferentArrangement
differentSong
```

For binary threshold metrics:

```text
sameArrangement                = positive / same song
sameSongDifferentArrangement   = positive / same song
differentSong                  = negative / different song
```

The original three-way relationship remains preserved in every observation and distribution.

## Real-WAV workflow

`ResolverCalibrationHarness.makeCase(...)` accepts two completed-WAV URLs plus the human-confirmed relationship.

It runs the same `AudioEvidenceExtractor` used by Song Resolver and stores only the resulting deterministic `AudioEvidenceVector` values inside the benchmark case.

Recommended workflow:

1. Choose two user-owned / permitted completed WAVs.
2. Label their relationship explicitly.
3. Call `makeCase(...)`.
4. Add the case to a `ResolverCalibrationDataset`.
5. Save the derived dataset JSON locally.
6. Evaluate it with `ResolverCalibrationHarness.evaluate(...)`.
7. Save / inspect the report JSON.
8. Add more positives and negatives before making product threshold decisions.

Raw audio is not embedded in the dataset JSON.

Private benchmark WAVs and private derived datasets should stay outside the repository or under an ignored private benchmark directory.

## Report

`ResolverCalibrationReport` contains:

- all per-case observations,
- Resolver confidence and component `SongMatchEvidence`,
- score distribution for same Arrangement,
- score distribution for same song / different Arrangement,
- score distribution for different songs,
- minimum confidence seen among positive same-song cases,
- maximum confidence seen among negative different-song cases,
- `confidenceGap = minimumPositive - maximumNegative`,
- threshold sweep metrics.

A positive confidence gap means the observed positive and negative confidence ranges are separated **for that dataset only**. It is not proof of a universal production threshold.

## Threshold sweep

The default sweep evaluates 0.00 through 1.00 in 0.05 increments.

For every threshold the harness reports:

- true positives,
- false positives,
- true negatives,
- false negatives,
- precision,
- recall,
- specificity,
- F1,
- balanced accuracy.

Custom threshold arrays are allowed. Values are clamped to 0...1, deduplicated, and sorted deterministically.

## Critical boundary

This gate is measurement only.

It must not:

- choose a production threshold automatically,
- mutate `SongResolver.combinedConfidence` weights from a report,
- auto-link a Project to Song Memory,
- auto-accept a candidate,
- modify TimelineMapper,
- modify `songStartRawSec`, `songStartAudioSec`, `offsetMs`, or trim ranges,
- use calibration labels as synchronization truth,
- upload private WAVs to a service.

Any later threshold or weighting change must be a separate reviewed gate backed by an explicit benchmark report.

## Persistence

Datasets and reports are plain Codable JSON.

Dataset schema begins at version 1. Unsupported future schema versions fail explicitly instead of being silently interpreted.

JSON output uses pretty printing and sorted keys so reports are inspectable and diff-friendly.

## Required tests

Before merge:

- labeled same-song synthetic fixtures score above a known negative fixture,
- a threshold with perfect fixture separation reports the expected confusion matrix,
- precision / recall / specificity / F1 / balanced accuracy are deterministic,
- dataset JSON round-trips,
- report JSON round-trips,
- unsupported dataset schema versions fail explicitly,
- empty datasets produce a safe inspectable empty report,
- custom thresholds clamp, deduplicate, and sort deterministically,
- all previous TimelineMapper / Short / Song Memory / Resolver / Tonal / Elastic tests remain green,
- XcodeGen, iOS Simulator build, and XCTest pass.

## Real-data acceptance before threshold tuning

Do not tune production confidence behavior from the synthetic regression fixtures alone.

Before a later calibration decision gate, collect a meaningful local corpus including:

- same master re-exported with level / mastering changes,
- same song in acoustic and full-band arrangements,
- same song in different keys,
- same song with longer / shorter intro or sections,
- live recordings with modest tempo drift,
- songs with similar common chord progressions,
- genuinely unrelated songs,
- difficult negatives by the same artist / similar instrumentation.

The benchmark should include both easy and adversarial negatives.

## Explicitly not implemented yet

- Automatic production threshold selection.
- Automatic Resolver weight optimization.
- Cloud benchmark upload.
- Bundled copyrighted audio corpus.
- Song-section labels.
- Melody contour evidence.
- Lyrics identity evidence.
- External metadata lookup.
- Automatic identity adoption.
- AI Short Director.
- Preference learning.

## Next gate

After enough real labeled pairs are collected, use the report to decide whether Resolver weights / thresholds need calibration.

Only after empirical calibration should Phase 7 move deeper into section / hook understanding or additional evidence sources.
