# AGENTS.md

## Project purpose

TakeLayer is an iOS-first app for turning smartphone performance footage into a finished performance video using a DAW-exported completed WAV as the reference audio.

Short definition: スマホで撮った演奏を、DAW完成音源つきの動画に整える。

Long-term direction: TakeLayer Core may support an AI Music Video Director that remembers songs and editing preferences, proposes multiple short-video edits, and learns from user approval and corrections. This direction must extend—not replace—the deterministic synchronization core.

## Repository implementation baseline

`main` contains the merged **Phase 1 (MVP-α)**, **Phase 1.1 Core Stabilization**, **Phase 1.5 Short Foundation**, **Phase 7 Song Intelligence Foundation**, **Phase 7 Song Resolver Evidence Foundation**, **Phase 7 Tonal Evidence Foundation**, **Phase 7 Elastic Tonal Alignment**, **Phase 7 Resolver Calibration Harness**, **Phase 7 Private Corpus Runner**, and **Phase 7 Consistency Stabilization**.

PR #15 (`phase-7-consistency-stabilization`) was squash-merged on 2026-09-04, and its merged `main` commit passed post-merge CI #93 including Resolver CLI compilation, iOS build, and the full XCTest suite.

**Phase 7 Real Corpus Measurement is the active operational gate.** Its scope is collecting and measuring a meaningful private real-audio corpus with the merged runner, reviewing false positives / false negatives, and choosing the next technical Resolver gate from observed failures rather than speculative complexity.

For every task, implement only the explicitly requested phase or scope and preserve already-merged behavior.

## Core principles

- Do not replace the DAW.
- Do not directly integrate with DAW APIs in the initial implementation.
- Treat the completed WAV as the Reference Performance Anchor.
- Keep `songStartRawSec` and `songStartAudioSec` as core concepts.
- Project timeline 0:00 means song start.
- Separate recording start, song start, first audible part entry, and selected trim range.
- Do not remove silence inside the song automatically.
- Prefer candidate suggestion + user confirmation over automatic adoption.
- Keep raw media edits non-destructive unless the user explicitly confirms deletion.
- Future AI suggestions must remain inspectable, reversible, and confidence-aware.
- Generative AI must never become the source of truth for synchronization.
- User-confirmed song metadata and lyrics must not be silently overwritten by external metadata or AI estimates.
- Resolver confidence alone must not create or replace a Project Song Memory link.
- Active production code must not depend on the historical `Features/ImportExportPoC/` folder.

## Timeline authority

`TakeLayer/Services/TimelineMapper.swift` is the authoritative mapping boundary for:

```text
raw video time
    ↓
Project Timeline
    ↓
completed-WAV time
```

Do not duplicate this arithmetic inside renderers, UI code, AI code, short extraction, Song Memory, Song Resolver, calibration code, corpus tooling, or future multi-part code.

Manual offset convention:

```text
offsetMs > 0  = completed WAV is delayed relative to video
offsetMs < 0  = completed WAV is advanced relative to video
```

AVFoundation `CMTime` conversion for user-visible synchronization/rendering should go through the shared microsecond-resolution `MediaTime` boundary so millisecond correction steps are not rounded differently between renderers.

Any sync defect must first be expressed as a TimelineMapper regression test before changing the mapping implementation when practical.

## Song-information authority

For song identity, arrangement metadata, and formal lyrics, use this precedence:

```text
1. User-confirmed value
2. Previously confirmed Song Memory
3. Trusted imported metadata candidate
4. Analysis estimate
5. Unknown
```

For formal lyrics specifically, the retained source order is:

```text
user-confirmed > licensed provider > transcription estimate
```

Song Memory is not a synchronization authority. It must not mutate `songStartRawSec`, `songStartAudioSec`, `offsetMs`, trim ranges, or renderer mapping.

Song Resolver may read completed-WAV evidence and Song Memory to produce candidates, but it must not silently promote analysis evidence into user-confirmed identity.

The legacy deterministic evidence `signature` is based on coarse duration / energy / transient evidence and must not be treated as proof of tonal identity. When Tonal Evidence exists, use the actual tonal comparison. Legacy evidence without Tonal Evidence must not be represented as certainty.

Tonal / Chroma, elastic alignment, calibration metrics, and private-corpus reports are analysis evidence. Even perfect benchmark separation is not equivalent to user confirmation or permission for automatic adoption.

## Tech direction

- iOS MVP first.
- Swift / SwiftUI.
- AVFoundation.
- Accelerate / vDSP when stronger signal processing is explicitly activated and materially useful.
- CryptoKit is acceptable for deterministic local evidence signatures and benchmark identifiers.
- SwiftData is a future persistence target; current persistence uses small JSON store boundaries.
- Xcode project generation is defined by `project.yml` using XcodeGen.
- Shared production workflow UI belongs outside historical PoC folders.
- Do not make FFmpegKit a core dependency.
- Android and Mac Companion are future phases.

## Phase discipline

- Implement only the requested phase.
- Do not implement multiple future phases in one pass.
- Phase 0.5A, Phase 0.5B, Phase 1, Phase 1.1, and Phase 1.5 are merged into `main`.
- Phase 7 Song Intelligence Foundation is merged into `main`.
- Phase 7 Song Resolver Evidence Foundation is merged into `main`.
- Phase 7 Tonal Evidence Foundation is merged into `main`.
- Phase 7 Elastic Tonal Alignment is merged into `main`.
- Phase 7 Resolver Calibration Harness is merged into `main`.
- Phase 7 Private Corpus Runner is merged into `main`.
- Phase 7 Consistency Stabilization is merged into `main` via PR #15 and passed post-merge CI #93.
- The active gate is documented in `docs/phase-7-real-corpus-measurement.md`.
- `docs/phase-7-consistency-stabilization.md` is a completed reliability record, not the current implementation scope.
- `docs/ai-director-vision.md`, `docs/song-memory-feedback.md`, and `docs/ai-director-data-model.md` are architecture references; they do not automatically activate all described capabilities.
- Do not infer that Phase 8, Phase 9, Phase 10, or unactivated Phase 7 sub-gates are active.

## Completed Phase 7 consistency-stabilization invariants

The following repairs are merged and must not regress:

- Keep `TimelineMapper` arithmetic authoritative unless a regression proves the formula itself is wrong.
- Preserve 1 ms manual offset precision through every active export path and Short preview seeking.
- Reject stale async export and Resolver results after relevant Project/WAV/link changes.
- Repair or reject dangling persisted Song Memory/media references instead of trusting them silently.
- Keep Resolver legacy signature semantics coarse; do not fabricate tonal certainty.
- Preserve lyrics source authority rather than letting a newer transcription estimate outrank licensed or user-confirmed lyrics.
- Keep human confirmation mandatory for Song/Arrangement adoption.
- Keep capture-session operations serialized through one service execution boundary.
- Keep production UI independent from `Features/ImportExportPoC/`.
- Reject invalid calibration configuration rather than silently changing requested values.
- Add regression tests for repaired invariants when practical.

See `docs/phase-7-consistency-stabilization.md`.

## Active Phase 7 real-corpus-measurement gates

- Collect real user-owned / permitted WAV relationships under the gitignored private corpus root.
- Include same Arrangement, same Song / different Arrangement, and difficult different-Song negatives.
- Include adversarial negatives such as same artist, similar instrumentation, similar key/BPM, and similar chord movement.
- Run the merged Private Corpus Runner and keep the resulting derived dataset/report inspectable.
- Review minimum positive confidence, maximum negative confidence, confidence gap, and threshold confusion metrics.
- Review per-case evidence rather than relying only on one aggregate score.
- Classify meaningful false positives / false negatives before adding another evidence source.
- Do not tune production weights or thresholds from synthetic fixtures or a tiny convenient corpus.
- Do not add Resolver complexity without an observed failure class that motivates it.
- No report may auto-link Song Memory or bypass human confirmation.
- Calibration activity must not modify TimelineMapper or synchronization fields.

See `docs/phase-7-real-corpus-measurement.md` and `ResolverBenchmarks/README.md`.

## Do not implement list

Do not add these unless the active phase explicitly requests them:

- Automatic sync beyond the requested phase.
- Automatic trim beyond the requested phase.
- Split-screen layout rendering beyond the requested phase.
- Waveform display beyond the requested phase.
- Full SwiftData implementation beyond the requested phase.
- Billing.
- Cloud sync.
- Android support.
- Mac Companion.
- DAW API integration.
- Automatic take adoption.
- Automatic deletion of raw videos.
- Automatic production confidence threshold selection.
- Automatic Resolver weight optimization.
- Uploading private benchmark WAVs or private benchmark datasets.
- High-resolution unconstrained DTW over raw audio features.
- Song-section labels unless chosen from measured failures / next product gate.
- Melody contour / vocal melody evidence unless justified by real failure cases.
- Lyrics identity evidence beyond an explicitly activated gate.
- Automatic Song / Arrangement adoption from resolver confidence.
- External music metadata lookup.
- Automatic lyric transcription or automatic lyric captions.
- Lyrics forced-alignment beyond an explicitly activated gate.
- AI performer crop / tracking.
- AI Music Video Director proposal generation.
- Preference learning / edit-delta learning.

Do not remove or regress already-merged functionality such as import/record flow, WAV import, manual song-start markers, trim, manual offset, validation, deterministic Short editing, Song Memory, Resolver Evidence, Tonal Evidence, Elastic Alignment, Calibration Harness, Private Corpus Runner, Consistency Stabilization repairs, or single-screen export unless explicitly requested.

## Future AI Director references

When an AI phase is explicitly activated, read these before implementation:

- `docs/ai-director-vision.md`
- `docs/song-memory-feedback.md`
- `docs/ai-director-data-model.md`
- `docs/phases.md`
- `docs/architecture.md`

## Required final report format

```text
## 実装内容
- ...

## 変更ファイル
- ...

## 未実装
- ...

## 注意点
- ...

## 次にやるべきこと
- ...
```
