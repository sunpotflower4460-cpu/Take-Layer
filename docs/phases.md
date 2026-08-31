# TakeLayer Phases

## Repository status

As of 2026-08-31, `main` contains the merged **Phase 1 (MVP-α)** integrated flow from PR #5. Phase 0.5A and Phase 0.5B are also merged.

**Phase 1.1 Core Stabilization** is the next gate before feature expansion. It fixes timeline/export correctness and adds reproducible build, tests, and project persistence.

This file is a roadmap. A later phase is not active merely because it appears here. Implement only the phase or scope explicitly requested.

## Phase 0: 設計固定・リポジトリ土台

Historical foundation phase. Design, vocabulary, documentation, and repository structure were fixed so later phases would not reinterpret the core concepts.

## Phase 0.5A: Import-first Export PoC

Status: merged.

- Video import.
- Completed WAV import.
- `songStartRawSec` selection.
- `songStartAudioSec` selection.
- Manual trim.
- Single-screen export.
- If possible, 2-split / 4-split verification.

This phase validated the core idea before adding recording.

## Phase 0.5B: Recording PoC

Status: merged.

- In-app recording.
- Zen mode.
- Camera audio extraction.
- Sync assistance with completed WAV.
- Manual anchors.
- End-point drift check.

## Phase 1: MVP-α

Status: merged baseline on `main`.

- One video + completed WAV replacement.
- Video import / recording.
- Manual song-start marker.
- Manual trim.
- Manual offset.
- Single-screen export.
- Storage management.

## Phase 1.1: Core Stabilization

Status: implementation branch / merge gate.

Primary purpose: make Phase 1 deterministic and testable before later features depend on it.

- Authoritative `TimelineMapper`.
- Apply `offsetMs` during real export.
- Preserve synchronization when trim start differs from song start.
- Handle pre-roll without silently clamping audio time.
- Use the same timeline mapping for validation and rendering.
- Reproducible Xcode project generation.
- macOS CI build and XCTest.
- Timeline regression tests.
- Local Project persistence.
- Serialized AVCaptureSession configuration/start/stop.
- Modern async AVAssetExportSession export path.

See `phase-1.1-core-stabilization.md`.

Phase 1.1 must be green before Phase 1.5 / Phase 2 / AI work proceeds.

## Phase 1.5: Short Foundation

Goal: prove the one-video short-form editing substrate before multi-part complexity.

- One performance video.
- 9:16 output canvas.
- Manual short-range extraction.
- Deterministic title layer.
- User-supplied lyric text layer.
- Subtitle renderer.
- Deterministic crop / zoom / pan plan.
- Preview → micro-adjustment → export.
- No generative decision-making required yet.

This phase creates the renderer primitives that the later AI Short Director will control through an EditingPlan.

## Phase 2: MVP-β / Multi-part Core

- Multiple parts.
- 2-split / 4-split.
- Place each Take onto the Project timeline.
- Timeline display.
- Per-part offset correction.

Multi-part work may proceed after Phase 1.1, but product priority should be evaluated against Phase 1.5 because the primary near-term value is high-quality one-video shorts.

## Phase 3: 自動候補化

- Song-length window search.
- Candidate suggestion.
- Reason display.
- User evaluation.
- Undo.

## Phase 4: 同期補助強化

- Camera audio × completed WAV matching.
- Sync click.
- Sync Guide WAV.
- End-point drift detection.
- Drift warning.

## Phase 5: 演出

- Production-process style.
- Parts appear in `recordedAt` order.
- Section-specific layouts.
- Shorts extraction for legacy roadmap compatibility; new one-video short primitives should originate in Phase 1.5.
- Momentary camera-audio mix.

## Phase 6: Pro拡張

- Strict Sync / Natural Sync.
- Reference Map.
- MIDI tempo map import.
- Mac Companion.
- 4K.
- Advanced proxy editing.

---

# Future AI Director Track

The phases below describe the long-term AI Music Video Director direction. They are **not active implementation phases** until explicitly promoted. They extend the TakeLayer Core delivery path rather than replacing it.

## Phase 7: Song Intelligence Foundation

Goal: TakeLayer begins to understand and remember the musical work itself.

- `SongIdentity` and `SongProfile`.
- Song / Arrangement separation.
- Same-song recognition using multiple evidence sources.
- Song Memory.
- User-confirmed metadata precedence.
- Metadata Provider Adapter layer.
- Formal lyrics storage for user-owned / permitted lyrics.
- Lyrics alignment to known text.
- Song sections and highlight candidates.
- Confidence-based confirmation UI.

Success criterion:

A previously imported song can be recognized with confidence, and TakeLayer can propose the existing profile without silently overwriting user-confirmed information.

## Phase 8: AI Short Director

Goal: one performance video can become multiple high-quality short-video proposals.

- 9:16 short-video workflow.
- Highlight / hook candidate generation.
- Performer-aware crop proposals.
- Title / artist text proposals.
- Lyric caption plans.
- Restrained zoom / pan / effect plans.
- Natural / Cinematic / Lyric Focus / Social Hook / Minimal variants.
- `EditingPlan` intermediate representation.
- Deterministic rendering from EditingPlan.
- Quality Gate before proposals are shown.
- Proposal comparison UI.
- Human micro-adjustment before approval.

Success criterion:

The user can drop in a performance video, review 3–5 meaningfully different proposals, make small final adjustments, and approve/export one without reconstructing the edit manually.

## Phase 9: Feedback & Preference Learning

Goal: TakeLayer learns what the user considers good editing.

- Approved / rejected proposal history.
- Explicit ratings / notes.
- Edit-delta capture between AI proposal and approved final plan.
- Song-specific preferences.
- Arrangement / artist / user-wide preference scopes.
- Context-aware preference application.
- Evidence count and confidence.
- Do-not-overlearn safeguards.
- Explainable preference application.
- Memory inspection / reset / forget controls.
- Ranking approved-style proposals higher over time.

Initial implementation should prefer structured rules and weighted history before attempting model fine-tuning.

Success criterion:

Repeated user corrections measurably reduce the amount of manual adjustment needed on later proposals.

## Phase 10: Multi-part AI Director

Goal: extend the same Director logic to multiple synchronized performance videos.

- Part activity analysis.
- Part Salience estimation.
- Section-aware camera / layout selection.
- Vocal entry detection.
- Solo / fill / phrase-event emphasis.
- Automatic front-layer / split-layout proposals.
- Multi-part lyric / title composition.
- EditingPlan support for camera switching and layout events.
- Preference learning for multi-camera choices.

Part Salience must not be based on frequency alone. It should combine musical activity, novelty, section context, role, and visual information.

Success criterion:

Multiple synchronized performance videos can be turned into musically sensible edit proposals while preserving TakeLayer Core synchronization accuracy.

## Roadmap invariant

No future phase may weaken these core guarantees:

- Completed WAV remains a valid Reference Performance Anchor.
- `songStartRawSec` and `songStartAudioSec` remain explicit concepts.
- Project timeline 0:00 remains song start.
- `TimelineMapper` remains the authoritative raw-video ↔ Project Timeline ↔ master-audio mapping boundary.
- Raw media editing remains non-destructive by default.
- AI proposals remain inspectable and reversible.
- Low-confidence identity, lyrics, sync, or metadata decisions return to user confirmation.
- Generative AI must not become the source of truth for synchronization.
