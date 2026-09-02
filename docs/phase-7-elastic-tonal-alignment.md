# Phase 7: Elastic Tonal Alignment

## Status

Active branch: `phase-7-elastic-tonal-alignment`.

Prerequisites merged on `main`:

- human-confirmed Song Memory,
- deterministic Resolver Evidence,
- transposition-aware Tonal Evidence.

## Goal

Improve same-song candidate quality when a later performance keeps much of the same harmonic structure but changes timing or arrangement shape, for example:

- a live version with a longer intro,
- an acoustic version with sections stretched or compressed,
- a shortened section,
- different relative section lengths,
- a key-transposed performance combined with these timing differences.

This gate remains an evidence layer. It does not automatically identify, attach, trim, synchronize, or edit anything.

## Alignment model

The existing 32-frame `TonalEvidenceVector` remains unchanged.

For every one of the 12 pitch-class rotations, Resolver performs a small deterministic semi-global DTW-style alignment over the 32 × 32 tonal similarity matrix.

Allowed path moves are:

```text
1 frame query + 1 frame stored  = diagonal / normal progression
1 frame query + 0 frame stored  = stored structure stretched
0 frame query + 1 frame stored  = query structure stretched
```

Horizontal / vertical moves receive a small transition penalty.

The aligner may ignore at most four normalized frames at either endpoint. This is intended for modest intro / outro differences, not arbitrary subsequence matching.

## Explainable evidence

`SongMatchEvidence` gains optional backwards-compatible fields:

- `tonalAlignmentCoverage`
  - fraction of the shorter normalized tonal structure used by the selected alignment,
  - 1.0 means full 32-frame structural coverage.
- `tonalWarpFraction`
  - fraction of non-diagonal alignment moves,
  - higher values mean more stretching / compression was needed.

Candidate UI displays both values alongside:

- total confidence,
- duration,
- energy shape,
- transient shape,
- tonal / chroma score,
- estimated key shift.

This makes an apparently strong candidate inspectable. A candidate with good tonal similarity but low coverage or unusually high warp remains visibly suspicious.

## Score behavior

Tonal similarity combines:

```text
global pitch-class similarity   25%
elastic tonal sequence score    75%
```

The sequence score starts from average aligned frame similarity and applies modest penalties for:

- structural warp,
- unused endpoint coverage.

The resulting tonal score remains only one component of the existing Resolver confidence. Human confirmation remains mandatory regardless of score.

## Safety boundaries

Elastic tonal alignment must not modify or infer authoritative values for:

- `songStartRawSec`,
- `songStartAudioSec`,
- `offsetMs`,
- trim ranges,
- TimelineMapper,
- user-confirmed Song Memory,
- formal lyrics.

It is not synchronization logic and must never be reused as TimelineMapper truth.

## Required tests

Before merge:

- a same harmonic structure with stretched sections and key transposition remains high-scoring,
- the estimated transposition remains correct,
- `tonalAlignmentCoverage` is present and bounded 0...1,
- `tonalWarpFraction` is present and bounded 0...1,
- stretched structure requires observable non-zero warp in the regression fixture,
- a materially different tonal structure scores lower than the elastic same-song fixture,
- endpoint differences can be tolerated only with visible coverage reduction,
- exact registered evidence reports full coverage and zero warp,
- exact evidence still does not auto-resolve,
- old `SongMatchEvidence` JSON without new alignment fields still decodes,
- all previous TimelineMapper / Short / Song Memory / Resolver / Tonal Evidence tests remain green,
- iOS Simulator build and XCTest pass.

## Performance constraint

The alignment operates only on the fixed 32-frame evidence representation, not raw audio samples. Complexity stays intentionally bounded and no new media decoding pass is required after tonal evidence extraction.

## Explicitly not implemented yet

- Arbitrary full-song subsequence discovery.
- Beat-synchronous chroma.
- Full unconstrained DTW over high-resolution audio features.
- Song-section labels such as verse / chorus / bridge.
- Melody contour matching.
- Lyrics identity evidence.
- External metadata lookup.
- Automatic identity adoption.
- AI Short Director.
- Preference learning.

## Next gate

After elastic tonal alignment is stable, Phase 7 should prioritize **real-data confidence calibration and section / hook understanding** before automatic editing decisions.

A useful next step is a benchmark harness containing confirmed same-song / different-arrangement pairs and known-negative pairs. That gives TakeLayer empirical thresholds instead of inventing confidence cutoffs from synthetic fixtures.
