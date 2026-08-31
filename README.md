# TakeLayer

DAWで音を作る人のための、演奏動画アセンブラー。

**スマホで撮った演奏を、DAW完成音源つきの動画に整える。**

TakeLayerは、DAWで仕上げた完成WAVをReference Performance Anchorとして、撮りっぱなしの演奏動画を共通のProject Timelineへ並べ、同期・トリム・書き出しを安全に行うiOS-firstアプリです。

将来的には、この同期コアの上に、曲を覚え、歌詞や見せ場を理解し、複数のショート動画編集案を提案し、ユーザーの承認や修正から好みを学ぶ **AI Music Video Director** を構築します。

---

## Current status

As of 2026-08-31:

- Phase 0.5A Import-first Export PoC: merged
- Phase 0.5B Recording PoC: merged
- Phase 1 MVP-α: merged on `main`
- **Phase 1.1 Core Stabilization: current reliability gate**

Phase 1.1 exists before further feature expansion because the TakeLayer Core must be deterministic, buildable, testable, and persistent before AI or multi-part editing depends on it.

See:

- `docs/phases.md`
- `docs/phase-1.1-core-stabilization.md`
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
performance video
```

### TimelineMapper is authoritative

All raw-video ↔ Project Timeline ↔ completed-WAV mapping goes through:

```text
TakeLayer/Services/TimelineMapper.swift
```

Do not duplicate synchronization arithmetic inside rendering, UI, short-video logic, or future AI code.

Manual offset convention:

```text
offsetMs > 0  = completed WAV delayed relative to video
offsetMs < 0  = completed WAV advanced relative to video
```

### Non-destructive by default

Raw videos are preserved unless the user explicitly confirms deletion.

TakeLayer must not remove musical silence merely because a section is quiet.

---

## Phase 1.1

Phase 1.1 stabilizes the merged MVP-α.

Implemented direction:

- authoritative `TimelineMapper`
- real `offsetMs` application during export
- trim-aware completed-WAV mapping
- pre-roll handling without silent sync breakage
- shared mapping for validation and rendering
- XcodeGen project definition
- GitHub Actions iOS build + XCTest
- timeline regression tests
- local Project persistence
- serialized camera-session configuration/start/stop
- current async AVAssetExportSession export path

No AI features are introduced in this phase.

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

---

## Current Phase 1 workflow

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
```

The camera audio remains useful as future synchronization evidence, while the completed WAV is the primary program audio for the Phase 1 export.

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

### Phase 1.1 — Core Stabilization

Make the existing one-video core reliable.

### Phase 1.5 — Short Foundation

Before adding multi-part complexity, prove the primitives required for a high-quality one-video short:

- 9:16 canvas
- manual short extraction
- title layer
- user-supplied lyric layer
- subtitle renderer
- deterministic crop / zoom / pan plan
- preview → micro-adjustment → export

### Song Intelligence

Later:

- SongIdentity / SongProfile
- same-song recognition
- formal lyrics memory
- metadata candidates
- section / hook understanding

### AI Short Director

Later:

- 3–5 meaningful edit proposals
- performer-aware crop
- lyric alignment
- title / effect / zoom proposals
- Natural / Cinematic / Lyric Focus / Social Hook / Minimal variants
- deterministic EditingPlan renderer

### Preference Learning

Later:

- approval / rejection
- edit-delta learning
- song-specific preferences
- context-aware user-wide preferences
- explainable memory

### Multi-part AI Director

Later:

- multiple synchronized performance videos
- Part Salience
- musically sensible camera switching
- section-aware layouts

See `docs/phases.md` for the detailed roadmap.

---

## Documentation

Start here:

- `AGENTS.md` — rules for coding agents and phase discipline
- `docs/README.md` — documentation map
- `docs/architecture.md` — current core architecture
- `docs/phases.md` — implementation roadmap
- `docs/phase-1.1-core-stabilization.md` — current reliability phase
- `docs/data-model.md` — core conceptual data model
- `docs/testing-cases.md` — important musical edge cases
- `docs/ai-director-vision.md` — long-term AI Director product architecture
- `docs/song-memory-feedback.md` — approval/edit-delta learning design
- `docs/ai-director-data-model.md` — future AI data model

---

## Technology direction

Current core:

- Swift
- SwiftUI
- AVFoundation
- Accelerate / vDSP for later deterministic audio analysis
- local Project persistence
- XcodeGen
- XCTest / GitHub Actions

Future persistence may move toward SwiftData as Song Memory and richer project relationships are introduced.

FFmpegKit is not a core dependency.

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
