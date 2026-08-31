# AGENTS.md

## Project purpose

TakeLayer is an iOS-first app for turning smartphone performance footage into a finished performance video using a DAW-exported completed WAV as the reference audio.

Short definition: スマホで撮った演奏を、DAW完成音源つきの動画に整える。

Long-term direction: TakeLayer Core may later support an AI Music Video Director that remembers songs and editing preferences, proposes multiple short-video edits, and learns from user approval and corrections. This future direction must extend—not replace—the deterministic synchronization core.

## Repository implementation baseline

`main` contains the merged **Phase 1 (MVP-α)** integrated flow from PR #5, building on Phase 0.5A and Phase 0.5B.

`phase-1.1-core-stabilization` is the stabilization branch. It exists to make the Phase 1 core buildable, persistent, testable, and synchronization-correct before feature expansion.

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

Do not duplicate this arithmetic inside renderers, UI code, AI code, short extraction, or future multi-part code.

Manual offset convention:

```text
offsetMs > 0  = completed WAV is delayed relative to video
offsetMs < 0  = completed WAV is advanced relative to video
```

Any sync defect must first be expressed as a TimelineMapper regression test before changing the mapping implementation when practical.

## Tech direction

- iOS MVP first.
- Swift / SwiftUI.
- AVFoundation.
- Accelerate / vDSP.
- SwiftData is a future persistence target; Phase 1.1 uses a small ProjectStore boundary first.
- Xcode project generation is defined by `project.yml` using XcodeGen.
- Do not make FFmpegKit a core dependency.
- Android and Mac Companion are future phases.

## Phase discipline

- Implement only the requested phase.
- Do not implement multiple phases in one pass.
- Historical Phase 0 was for design, documentation, and repository structure only.
- Phase 0.5A, Phase 0.5B, and Phase 1 have already been merged into `main`.
- Phase 1.1 is stabilization, not permission to add later creative automation.
- Do not infer that Phase 1.5, Phase 2, or any later phase is active unless explicitly requested.
- `docs/ai-director-vision.md`, `docs/song-memory-feedback.md`, and `docs/ai-director-data-model.md` are future architecture documents only.
- Do not implement Song Memory, lyric captions, AI crop, AI Director, preference learning, external metadata adapters, or automatic short-video generation until their future phase is explicitly activated.

## Phase 1.1 gates

Before calling Phase 1.1 complete:

- XcodeGen must generate the project.
- iOS Simulator build must pass.
- TimelineMapper tests must pass.
- `offsetMs` must affect real export mapping.
- trim start changes must preserve Project Timeline synchronization.
- Project state must survive restart.
- camera session startup/configuration must not block the main UI thread.

See `docs/phase-1.1-core-stabilization.md`.

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
- Song Memory / Song Resolver.
- External music metadata lookup.
- Automatic lyric captions.
- AI performer crop / tracking.
- AI Music Video Director.
- Preference learning / edit-delta learning.

Do not remove or regress already-merged Phase 1 functionality such as import/record flow, WAV import, manual song-start markers, trim, manual offset, validation, and single-screen export unless explicitly requested.

## Future AI Director references

When a future AI phase is explicitly activated, read these before implementation:

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
