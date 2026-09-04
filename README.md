# TakeLayer

DAWで音を作る人のための、演奏動画アセンブラー。

**スマホで撮った演奏を、DAW完成音源つきの動画に整える。**

TakeLayerは、DAWで仕上げた完成WAVをReference Performance Anchorとして、撮りっぱなしの演奏動画を共通のProject Timelineへ並べ、同期・トリム・ショート編集・書き出しを安全に行うiOS-firstアプリです。

将来的には、この決定論的な同期・レンダリングコアの上に、曲を覚え、歌詞や見せ場を理解し、複数のショート動画編集案を提案し、ユーザーの承認や修正から好みを学ぶ **AI Music Video Director** を構築します。

---

## Current status

As of 2026-09-04, `main` contains:

- Phase 0.5A Import-first Export PoC
- Phase 0.5B Recording PoC
- Phase 1 MVP-α
- Phase 1.1 Core Stabilization
- Phase 1.5 Short Foundation
- Phase 7 Song Intelligence Foundation
- Phase 7 Song Resolver Evidence Foundation
- Phase 7 Tonal Evidence Foundation
- Phase 7 Elastic Tonal Alignment
- Phase 7 Resolver Calibration Harness
- Phase 7 Private Corpus Runner
- Phase 7 Consistency Stabilization

Phase 7 Consistency Stabilization was squash-merged via PR #15. Its merged `main` commit passed post-merge CI #93 including Resolver CLI compilation, iOS build, and the full XCTest suite.

The active operational gate is now **Phase 7 Real Corpus Measurement**. The goal is to measure the current Resolver on a meaningful private real-audio corpus, inspect failure classes, and let observed evidence—not speculative complexity—choose the next Resolver step.

See:

- `docs/phases.md`
- `docs/phase-7-real-corpus-measurement.md`
- `docs/README.md`

---

## Core invariants

### Project Timeline

```text
Project timeline 0:00 = 曲開始
```

Video:

```text
songStartRawSec → Project timeline 0:00
```

Completed WAV:

```text
songStartAudioSec → Project timeline 0:00
```

Recording start, song start, first audible part entry, and selected trim range are separate concepts.

### Completed WAV is the Reference Performance Anchor

TakeLayer does not replace or directly operate the DAW.

```text
DAW
 ↓
completed WAV
 ↓
TakeLayer
 ↓
performance video / short video
```

### TimelineMapper is authoritative

All raw-video ↔ Project Timeline ↔ completed-WAV mapping goes through:

```text
TakeLayer/Services/TimelineMapper.swift
```

Do not duplicate synchronization arithmetic inside rendering, UI, short-video logic, Resolver logic, or future AI code.

Manual offset convention:

```text
offsetMs > 0  = completed WAV delayed relative to video
offsetMs < 0  = completed WAV advanced relative to video
```

AVFoundation time conversion should use the shared microsecond-resolution `MediaTime` boundary so millisecond user corrections survive rendering.

### Human confirmation remains authoritative

Song Resolver produces candidates and evidence. It does **not** silently adopt a Song or Arrangement.

User-confirmed song metadata and formal lyrics outrank licensed-provider candidates, and licensed-provider lyrics outrank transcription estimates.

### Non-destructive by default

Raw videos are preserved unless the user explicitly confirms deletion.

TakeLayer must not remove musical silence merely because a section is quiet.

---

## Implemented workflow

```text
Create / restore Project
        ↓
Import or record performance video
        ↓
Import completed WAV
        ↓
Set songStartRawSec
        ↓
Set songStartAudioSec
        ↓
Choose non-destructive trim range
        ↓
Adjust manual offset
        ↓
TimelineMapper validation
        ↓
Single-screen MP4 export
        ↓
Optional deterministic 9:16 Short editing
        ↓
Song Memory / Resolver evidence reuse with human confirmation
```

The camera audio is retained as useful evidence, while the completed WAV is the program audio for the current deterministic export path.

---

## Completed consistency gate

Phase 7 Consistency Stabilization repaired cross-cutting defects without adding new AI behavior.

Completed scope includes:

- shared microsecond AVFoundation time conversion for normal and Short exports and Short preview seeking;
- stale async export / Resolver result rejection;
- legacy coarse Resolver signature correctness;
- tonal fingerprint collision handling;
- persisted Song Memory link repair;
- persisted media-file existence validation;
- lyrics authority and licensed-lyrics recovery after confirmed-lyrics removal;
- serialized camera recording operations and cancellable delayed tasks;
- strict calibration threshold validation;
- active UI extraction from the historical ImportExportPoC folder;
- regression tests and repository-status synchronization.

PR #15 was merged only after clean XcodeGen generation, CLI compile, iOS simulator build, full XCTest, and review checks. The merge commit then passed post-merge `main` CI #93.

See `docs/phase-7-consistency-stabilization.md`.

---

## Generate the Xcode project

The repository uses `project.yml` as the reproducible project definition.

```bash
brew install xcodegen
xcodegen generate
open TakeLayer.xcodeproj
```

The generated `TakeLayer.xcodeproj` is intentionally not committed.

CI performs the same generation step before building and testing.

The historical `TakeLayer/Features/ImportExportPoC/` source remains in the repository for reference but is excluded from the active app target. Production workflow components live outside that legacy folder.

---

## Architecture direction

```text
Future User / Review UI
          ↓
Future AI Director
          ↓
Song Memory + Preference Memory
          ↓
Editing Plan + Quality Gate
          ↓
TimelineMapper
          ↓
TakeLayer Core
          ↓
AVFoundation deterministic render/export
```

Generative AI must never become the source of truth for synchronization.

---

## Near-term roadmap

### Now — Phase 7 Real Corpus Measurement

- collect meaningful private real-audio relationships;
- include same Arrangement, same Song / different Arrangement, and adversarial different-Song negatives;
- run the merged calibration tooling;
- inspect per-case false positives / false negatives;
- choose the next Resolver gate from observed failure classes rather than speculative complexity.

### Completed — Phase 7 Consistency Stabilization

The cross-cutting reliability gate is merged and post-merge CI is green.

### Later — AI Short Director

- 3–5 meaningful edit proposals;
- performer-aware crop;
- lyric alignment;
- title / effect / zoom proposals;
- Natural / Cinematic / Lyric Focus / Social Hook / Minimal variants;
- deterministic EditingPlan renderer.

### Later — Preference Learning

- approval / rejection;
- edit-delta learning;
- song-specific and context-aware user preferences;
- explainable memory and reset controls.

### Later — Multi-part AI Director

- multiple synchronized performance videos;
- Part Salience;
- musically sensible camera switching;
- section-aware layouts.

See `docs/phases.md` for the detailed roadmap.

---

## Documentation

Start here:

- `AGENTS.md` — coding-agent rules and active-gate discipline
- `docs/README.md` — documentation map
- `docs/phases.md` — implementation roadmap and current status
- `docs/phase-7-real-corpus-measurement.md` — active operational gate
- `docs/phase-7-consistency-stabilization.md` — completed cross-cutting reliability gate
- `docs/architecture.md` — current core architecture
- `docs/phase-1.1-core-stabilization.md` — deterministic core foundation
- `docs/phase-1.5-short-foundation.md` — one-video Short substrate
- `docs/phase-7-song-intelligence-foundation.md` — Song Memory foundation
- `docs/phase-7-song-resolver-evidence.md` — Resolver evidence foundation
- `docs/phase-7-tonal-evidence.md` — tonal evidence
- `docs/phase-7-elastic-tonal-alignment.md` — structural tonal alignment
- `docs/phase-7-resolver-calibration-harness.md` — calibration measurement
- `docs/phase-7-private-corpus-runner.md` — private real-audio runner
- `docs/ai-director-vision.md` — long-term AI Director architecture
- `docs/song-memory-feedback.md` — future approval/edit-delta learning design
- `docs/ai-director-data-model.md` — future AI data model

---

## Technology direction

Current core:

- Swift / SwiftUI
- AVFoundation
- local JSON persistence boundaries
- XcodeGen
- XCTest / GitHub Actions
- deterministic audio evidence extraction
- CryptoKit for local evidence signatures / benchmark identifiers

Accelerate / vDSP may be used when stronger signal processing is explicitly justified. SwiftData remains a future persistence target. FFmpegKit is not a core dependency.

---

## Product philosophy

音はDAWで磨く。  
映像はTakeLayerが整える。

同期は数値で確定する。  
AIは表現を提案する。

AIが勝手に正解を決めるのではなく、複数の候補を提示し、人間が選び、少し直し、その判断を次の提案へ活かす。

最終的な目標はシンプルです。

```text
動画を入れる
→ 曲を理解する
→ 高品質なショート案が複数出る
→ 少し直す
→ 承認する
→ 次回はもっと自分好みになる
```
