# AGENTS.md

## Project purpose

TakeLayer is an iOS-first app for turning smartphone performance footage into a finished performance video using a DAW-exported completed WAV as the reference audio.

Short definition: スマホで撮った演奏を、DAW完成音源つきの動画に整える。

Long-term direction: TakeLayer Core may support an AI Music Video Director that remembers songs and editing preferences, proposes multiple short-video edits, and learns from user approval and corrections. This direction must extend—not replace—the deterministic synchronization core.

## Repository implementation baseline

`main` contains the merged **Phase 1 (MVP-α)**, **Phase 1.1 Core Stabilization**, and **Phase 1.5 Short Foundation** foundations.

`phase-7-song-intelligence-foundation` is the active branch. Its current scope is human-confirmed Song Memory, Song / Arrangement separation, formal lyrics persistence, and Project linkage. Automatic resolver evidence, external metadata lookup, AI Director generation, and preference learning are not activated by this branch.

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

## Timeline authority

`TakeLayer/Services/TimelineMapper.swift` is the authoritative mapping boundary for:

```text
raw video time
    ↓
Project Timeline
    ↓
completed-WAV time
```

Do not duplicate this arithmetic inside renderers, UI code, AI code, short extraction, Song Memory, Song Resolver, or future multi-part code.

Manual offset convention:

```text
offsetMs > 0  = completed WAV is delayed relative to video
offsetMs < 0  = completed WAV is advanced relative to video
```

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

Song Memory is not a synchronization authority. It must not mutate `songStartRawSec`, `songStartAudioSec`, `offsetMs`, trim ranges, or renderer mapping.

## Tech direction

- iOS MVP first.
- Swift / SwiftUI.
- AVFoundation.
- Accelerate / vDSP.
- SwiftData is a future persistence target; current persistence uses small JSON store boundaries.
- Xcode project generation is defined by `project.yml` using XcodeGen.
- Do not make FFmpegKit a core dependency.
- Android and Mac Companion are future phases.

## Phase discipline

- Implement only the requested phase.
- Do not implement multiple phases in one pass.
- Phase 0.5A, Phase 0.5B, Phase 1, Phase 1.1, and Phase 1.5 have already been merged into `main`.
- Phase 7 Song Intelligence Foundation is explicitly activated only for the scope documented in `docs/phase-7-song-intelligence-foundation.md`.
- `docs/ai-director-vision.md`, `docs/song-memory-feedback.md`, and `docs/ai-director-data-model.md` are architecture references; they do not automatically activate all described capabilities.
- Do not infer that Phase 8, Phase 9, Phase 10, or unactivated Phase 7 sub-gates are active.

## Active Phase 7 gates

Before calling the current Song Intelligence foundation complete:

- `SongIdentity`, `SongProfile`, `ArrangementProfile`, and `FormalLyrics` must be Codable and persistent.
- A Project may link to a Song and Arrangement without changing synchronization.
- User-confirmed values must remain explicit and highest-precedence.
- Existing Song Memory entries must be selectable and editable.
- Formal lyrics must be versioned when changed.
- XcodeGen must generate the project.
- iOS Simulator build and XCTest must pass.
- Existing TimelineMapper and Short Foundation tests must continue to pass.

See `docs/phase-7-song-intelligence-foundation.md`.

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
- Audio fingerprint generation / same-song auto matching beyond the active Song Memory foundation.
- External music metadata lookup.
- Automatic lyric transcription or automatic lyric captions.
- Lyrics forced-alignment beyond an explicitly activated gate.
- AI performer crop / tracking.
- AI Music Video Director proposal generation.
- Preference learning / edit-delta learning.

Do not remove or regress already-merged functionality such as import/record flow, WAV import, manual song-start markers, trim, manual offset, validation, deterministic Short editing, or single-screen export unless explicitly requested.

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
