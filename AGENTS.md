# AGENTS.md

## Project purpose

TakeLayer is an iOS-first app for turning smartphone performance footage into a finished performance video using a DAW-exported completed WAV as the reference audio.

Short definition: スマホで撮った演奏を、DAW完成音源つきの動画に整える。

Long-term direction: TakeLayer Core may later support an AI Music Video Director that remembers songs and editing preferences, proposes multiple short-video edits, and learns from user approval and corrections. This future direction must extend—not replace—the deterministic synchronization core.

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

## Tech direction

- iOS MVP first.
- Swift / SwiftUI.
- AVFoundation.
- Accelerate / vDSP.
- SwiftData.
- Do not make FFmpegKit a core dependency.
- Android and Mac Companion are future phases.

## Phase discipline

- Implement only the requested phase.
- Do not implement multiple phases in one pass.
- Phase 0 is for design, documentation, and repository structure only.
- Phase 0.5A starts with Import-first Export PoC.
- `docs/ai-director-vision.md`, `docs/song-memory-feedback.md`, and `docs/ai-director-data-model.md` are future architecture documents only.
- Do not implement Song Memory, lyric captions, AI crop, AI Director, preference learning, external metadata adapters, or automatic short-video generation until their future phase is explicitly activated.

## Do not implement list

Do not add these unless the active phase explicitly requests them:

- Video import implementation.
- WAV import implementation.
- AVFoundation export implementation.
- Recording feature.
- Automatic sync.
- Automatic trim.
- Split-screen layout rendering.
- Waveform display.
- Full SwiftData implementation.
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
