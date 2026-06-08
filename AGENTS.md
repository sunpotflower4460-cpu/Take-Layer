# AGENTS.md

## Project purpose

TakeLayer is an iOS-first app for turning smartphone performance footage into a finished performance video using a DAW-exported completed WAV as the reference audio.

Short definition: スマホで撮った演奏を、DAW完成音源つきの動画に整える。

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
