# Phase 7: Tonal Evidence Foundation

## Status

Active branch: `phase-7-tonal-evidence`.

Prerequisites merged on `main`:

- Phase 7 human-confirmed Song Memory foundation.
- Phase 7 Song Resolver Evidence Foundation.

## Goal

Make Song Resolver less dependent on exact recording / mix shape by adding deterministic tonal evidence that can survive moderate changes in instrumentation, level, and key.

This gate does **not** turn Resolver into an automatic identity authority. A candidate remains a proposal until the user explicitly confirms it.

## Evidence added in this gate

`AudioEvidenceVector` gains optional `TonalEvidenceVector` data so old local JSON remains decodable.

Tonal evidence contains:

- 12 pitch classes (C through B), octave-folded.
- 32 normalized timeline frames.
- a 12-bin global pitch-class distribution.
- an explicit analysis reference A frequency.

The current extractor samples fixed windows across the completed WAV, applies a Hann window, evaluates semitone-centered spectral energy across C2–B6 with small cent offsets, folds those energies into pitch classes, and normalizes the resulting Chroma-like vectors.

The cent offsets are intentionally present so ordinary tuning deviations such as approximately 432 Hz vs 440 Hz do not immediately destroy the tonal evidence.

## Matching behavior

For two fingerprints with Tonal Evidence, Resolver:

1. compares all 12 pitch-class rotations,
2. interprets the best rotation as an estimated semitone transposition from stored Arrangement to query,
3. compares both global pitch-class distribution and 32-frame tonal sequence,
4. tolerates a small normalized-time frame offset,
5. combines tonal similarity with duration, energy shape, and transient shape.

The current weighted confidence when tonal evidence exists is:

```text
duration       15%
energy shape   20%
transient      15%
tonal / chroma 50%
```

Legacy fingerprints without tonal evidence continue using the previous Resolver Evidence weights.

## Persistence compatibility

Tonal evidence is optional in `AudioEvidenceVector`.

An existing fingerprint with the same deterministic legacy signature can be upgraded in place when the same WAV is registered again after this gate. Its fingerprint ID remains stable and Tonal Evidence is attached to the existing record.

This avoids duplicating previously registered Arrangement evidence merely because a newer TakeLayer version knows how to derive more features.

## Human-confirmation rule

Even if:

- duration is perfect,
- energy / transient evidence is perfect,
- tonal similarity is perfect,
- estimated transposition is zero,
- total confidence is 100%,

Resolver still returns an unresolved candidate until the user explicitly chooses that candidate.

Tonal Evidence must never modify:

- `songStartRawSec`,
- `songStartAudioSec`,
- `offsetMs`,
- trim ranges,
- TimelineMapper behavior,
- user-confirmed Song Memory values.

## UI

Candidate details now expose:

- duration score,
- energy-shape score,
- transient-shape score,
- tonal / chroma score when available,
- estimated key shift in semitones when available.

This evidence is shown so a user can understand why a candidate ranked highly instead of receiving an unexplained AI decision.

## Tests required before merge

- existing TimelineMapper tests remain green,
- existing Short Foundation tests remain green,
- existing Song Memory / Resolver Evidence tests remain green,
- legacy `AudioEvidenceVector` JSON without Tonal Evidence still decodes,
- an old same-signature fingerprint upgrades without changing its ID,
- synthetic tonal patterns detect a known transposition,
- a different tonal progression scores below a transposed equivalent progression,
- a synthetic WAV produces deterministic Tonal Evidence and identifies its expected dominant pitch class,
- iOS Simulator build and XCTest pass.

## Explicitly not implemented yet

- Full FFT landmark fingerprinting.
- Dynamic time warping / elastic section alignment.
- Melody contour extraction.
- Vocal melody matching.
- Lyrics-based identity evidence.
- Known-lyrics forced alignment.
- External MusicBrainz / Apple Music metadata lookup.
- Confidence calibration on a real benchmark corpus.
- Automatic Song / Arrangement adoption.
- AI Short Director.
- Preference learning.

## Next gate

After this foundation is stable, the next useful Resolver gate should add **tempo / structure tolerance** rather than immediately adding generative AI.

A likely next step is section-aware or DTW-like tonal sequence comparison so the same work can still match when an acoustic or live arrangement contains a longer intro, shortened section, or materially different tempo.
