# TakeLayer Phases

## Phase 0: 設計固定・リポジトリ土台

Current phase. Do not build real media processing yet. Fix the design, vocabulary, documentation, and repository structure so later phases do not reinterpret the core concepts.

## Phase 0.5A: Import-first Export PoC

- Video import.
- Completed WAV import.
- `songStartRawSec` selection.
- `songStartAudioSec` selection.
- Manual trim.
- Single-screen export.
- If possible, 2-split / 4-split verification.

This phase validates the core idea before adding recording.

## Phase 0.5B: Recording PoC

- In-app recording.
- Zen mode.
- Camera audio extraction.
- Sync assistance with completed WAV.
- Manual anchors.
- End-point drift check.

## Phase 1: MVP-α

- One video + completed WAV replacement.
- Video import / recording.
- Manual song-start marker.
- Manual trim.
- Manual offset.
- Single-screen export.
- Storage management.

## Phase 2: MVP-β

- Multiple parts.
- 2-split / 4-split.
- Place each Take onto the Project timeline.
- Timeline display.
- Per-part offset correction.

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
- Shorts extraction.
- Momentary camera-audio mix.

## Phase 6: Pro拡張

- Strict Sync / Natural Sync.
- Reference Map.
- MIDI tempo map import.
- Mac Companion.
- 4K.
- Advanced proxy editing.
