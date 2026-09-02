# Phase 7: Song Resolver Evidence Foundation

## Status

Active branch: `phase-7-song-resolver-evidence`.

This sub-phase begins deterministic same-song / same-arrangement candidate matching. It extends the merged human-confirmed Song Memory foundation without allowing automatic identity adoption.

## Goal

Given a completed WAV, TakeLayer should be able to:

1. derive deterministic local audio evidence,
2. register that evidence against a user-confirmed Arrangement,
3. compare a later WAV against known Arrangement evidence,
4. rank candidate Song / Arrangement pairs with inspectable component scores,
5. require explicit human confirmation before linking the Project.

## Evidence implemented in this gate

`AudioEvidenceVector` contains:

- duration,
- sample rate and channel count as descriptive metadata,
- a fixed 64-bucket normalized RMS / energy envelope,
- a fixed 64-bucket normalized transient envelope,
- a deterministic SHA-256 signature over quantized duration + envelopes.

The signature is used for exact evidence deduplication. Candidate similarity is not based on the signature alone.

## Candidate score

The first deterministic score is intentionally simple and inspectable:

```text
confidence
= duration similarity × 0.25
+ energy-shape similarity × 0.45
+ transient-shape similarity × 0.30
```

Envelope similarity uses centered correlation mapped to 0...1. Exact matching signatures return perfect evidence scores.

This is an evidence foundation, not the final Song Resolver. It is expected that later gates add chroma, melody, landmark fingerprinting, lyrics, and other evidence sources.

## Persistence

Registered `ArrangementAudioFingerprint` records are stored separately under the local Song Memory resolver-evidence store.

`ArrangementProfile.fingerprintIDs` stores references to registered evidence records. Song metadata remains in the existing Song Memory store.

## Human-confirmation rule

A resolver result may contain a 100% confidence candidate and still must not automatically attach it.

`SongMatchResult` therefore keeps:

```text
resolvedSongID = nil
resolvedArrangementID = nil
needsUserConfirmation = true
```

until the user explicitly chooses a candidate in the UI.

Only explicit confirmation may create or replace `ProjectSongMemoryLink` from a resolver candidate.

## Synchronization boundary

Song Resolver Evidence is not synchronization truth.

It must never modify:

- `songStartRawSec`,
- `songStartAudioSec`,
- `offsetMs`,
- trim ranges,
- TimelineMapper arithmetic,
- render-time audio placement.

The completed WAV remains the Reference Performance Anchor and `TimelineMapper` remains the authoritative synchronization boundary.

## Implemented UI

The MVP flow exposes a Song Resolver Evidence card that can:

- register the current completed WAV as evidence for the currently confirmed Arrangement,
- analyze the current WAV against all known Arrangement evidence,
- display total confidence plus duration / energy-shape / transient-shape subscores,
- explicitly connect a selected candidate to the Project.

Audio evidence extraction runs off the main actor so long WAVs do not intentionally block SwiftUI state updates.

## Tests required before merge

- Exact fingerprint produces confidence 1.0.
- Exact fingerprint still does not auto-resolve.
- Closer Arrangement ranks ahead of a distant one.
- Duplicate evidence registration is idempotent.
- Fingerprint-ID attachment to an Arrangement is idempotent.
- Empty evidence library returns no candidate and no automatic resolution.
- Existing TimelineMapper, Short Foundation, and Song Memory tests remain green.
- XcodeGen generation, iOS Simulator build, and XCTest all pass.

## Explicitly not implemented yet

- Robust landmark fingerprinting.
- Chroma similarity.
- Melody contour matching.
- Lyrics evidence.
- Automatic metadata lookup.
- Automatic identity adoption at any confidence threshold.
- Cross-arrangement time warping / DTW.
- Song section analysis.
- AI Short Director.
- Preference learning.
- Multi-part AI Director.

## Next gate

After this evidence foundation is stable, the next safe Phase 7 increment is to improve resolver evidence quality without changing the confirmation contract. Likely additions are chroma / tonal evidence and a stronger audio-landmark fingerprint, followed by confidence calibration against real recordings of the same song in different arrangements.
