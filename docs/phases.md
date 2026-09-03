# TakeLayer Phases

## Repository status

As of 2026-09-03, `main` contains the merged **Phase 1 (MVP-α)**, **Phase 1.1 Core Stabilization**, **Phase 1.5 Short Foundation**, the first **Phase 7 Song Intelligence Foundation** with human-confirmed Song Memory, **Phase 7 Song Resolver Evidence Foundation**, **Phase 7 Tonal Evidence Foundation**, **Phase 7 Elastic Tonal Alignment**, and **Phase 7 Resolver Calibration Harness**. Phase 0.5A and Phase 0.5B are also merged.

**Phase 7 Private Corpus Runner** is now the active implementation gate. The current sub-scope makes real local-WAV calibration repeatable through a safe relative-path manifest, gitignored private corpus root, deterministic derived dataset/report generation, and a macOS developer CLI. It does not automatically change Resolver weights, production thresholds, identity adoption, synchronization, or editing behavior.

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

Status: merged on `main`.

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
- Modern async export path.

See `phase-1.1-core-stabilization.md`.

## Phase 1.5: Short Foundation

Status: merged on `main` via PR #7.

Goal: prove the one-video short-form editing substrate before multi-part complexity.

- One performance video.
- 9:16 output canvas at 1080 × 1920.
- Manual short-range extraction in Project Timeline coordinates.
- Deterministic title layer.
- User-supplied lyric text layer.
- Timed subtitle renderer.
- Deterministic crop / zoom / normalized pan plan.
- Preview → micro-adjustment → export.
- Persisted `ShortEditDraft` as an EditingPlan precursor.
- No generative decision-making required.

`TimelineMapper` remains the only synchronization authority. Future AI Short Director work may propose `ShortEditDraft` / EditingPlan values but must not bypass the deterministic renderer.

See `phase-1.5-short-foundation.md`.

## Phase 2: MVP-β / Multi-part Core

- Multiple parts.
- 2-split / 4-split.
- Place each Take onto the Project timeline.
- Timeline display.
- Per-part offset correction.

Multi-part work may proceed after the one-video renderer foundation is reliable, but product priority should remain high-quality one-video shorts first.

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

The phases below describe the long-term AI Music Video Director direction. They extend the TakeLayer Core delivery path rather than replacing it. Only the explicitly activated sub-scope may be implemented.

## Phase 7: Song Intelligence Foundation

Status: active private-corpus-runner gate. Human-confirmed Song Memory, deterministic Resolver Evidence, Tonal Evidence, Elastic Tonal Alignment, and Resolver Calibration Harness are merged on `main`.

Goal: TakeLayer begins to understand and remember the musical work itself.

### Merged Song Memory foundation

- `SongIdentity` and `SongProfile`.
- Song / Arrangement separation.
- Multiple Arrangements per Song.
- Local Song Memory persistence.
- User-confirmed metadata precedence.
- Formal lyrics storage for user-owned / permitted lyrics.
- Project ↔ Song / Arrangement linkage.
- Human confirmation UI.
- WAV replacement detaches stale identity linkage.

See `phase-7-song-intelligence-foundation.md`.

### Merged Song Resolver Evidence foundation

- Deterministic completed-WAV evidence extraction.
- Fixed-size energy and transient envelopes.
- Local evidence signatures for exact deduplication.
- Per-Arrangement evidence registration and persistence.
- `ArrangementProfile.fingerprintIDs` references.
- Deterministic candidate scores with component evidence.
- Explicit human confirmation before creating a resolver-derived Project link.
- No automatic adoption even for a perfect-confidence candidate.

See `phase-7-song-resolver-evidence.md`.

### Merged Tonal Evidence foundation

- Optional backwards-compatible `TonalEvidenceVector`.
- 12 octave-folded pitch classes.
- 32 normalized-time tonal frames.
- Global Chroma-like pitch-class distribution.
- Robust sampling around semitone centers to tolerate modest tuning differences.
- All-12 transposition search.
- Tonal / Chroma score and estimated semitone shift exposed in candidate evidence.
- Existing same-signature fingerprints upgraded in place instead of duplicated.
- Human confirmation remains mandatory.

See `phase-7-tonal-evidence.md`.

### Merged Elastic Tonal Alignment

- Bounded semi-global DTW-style alignment over the existing 32 tonal frames.
- Limited endpoint trimming for modest intro / outro differences.
- Horizontal / vertical alignment moves for section stretch / compression.
- All-12 transposition search retained.
- `tonalAlignmentCoverage` exposes how much normalized structure was used.
- `tonalWarpFraction` exposes how much structural warping was required.
- Tonal score penalizes excessive endpoint exclusion and structural warp.
- Human confirmation remains mandatory regardless of confidence.
- No TimelineMapper or synchronization-field mutation.

See `phase-7-elastic-tonal-alignment.md`.

### Merged Resolver Calibration Harness

- Explicit labeled relationships: same Arrangement, same Song / different Arrangement, different Song.
- Build benchmark cases from real completed-WAV URLs using the existing `AudioEvidenceExtractor`.
- Store derived `AudioEvidenceVector` data instead of raw WAV bytes.
- Evaluate every case through existing `SongResolver.compare` and `combinedConfidence`.
- Per-label confidence distributions.
- Minimum positive confidence, maximum negative confidence, and observed confidence gap.
- Deterministic threshold sweep with confusion matrix, precision, recall, specificity, F1, and balanced accuracy.
- Inspectable Codable JSON datasets and reports.
- No automatic threshold selection or Resolver weight changes.

See `phase-7-resolver-calibration-harness.md`.

### Active Private Corpus Runner sub-scope

- Schema-versioned local manifest for labeled WAV pairs.
- Private audio paths are relative to one corpus root.
- Absolute paths, `~`, traversal, and symlink escapes outside that root are rejected.
- WAV-only input for this gate.
- Stable deterministic case IDs when no explicit UUID is supplied.
- Duplicate effective case IDs fail explicitly.
- `ResolverBenchmarks/Private/` remains gitignored.
- macOS developer CLI builds from the same Resolver / Evidence source files used by the app.
- One command generates a derived evidence dataset and calibration report.
- CI compiles the developer CLI even though private WAVs are unavailable in CI.
- No production threshold, weight, identity, synchronization, or editing changes.

See `phase-7-private-corpus-runner.md` and `../ResolverBenchmarks/README.md`.

### Later Phase 7 gates

- Real benchmark corpus collection large enough to support a reviewed calibration decision.
- Failure-case classification before adding another evidence source.
- Stronger audio landmark fingerprinting if empirical reports expose a need.
- Melody contour evidence if empirical reports expose a need.
- Lyrics evidence and known-text alignment.
- Metadata Provider Adapter layer.
- Song sections and highlight candidates.
- Reviewed Resolver weight / threshold calibration based on empirical reports.

Success criterion for full Phase 7:

A previously imported song can be recognized with calibrated confidence from multiple evidence sources, and TakeLayer can propose the existing profile without silently overwriting user-confirmed information.

## Phase 8: AI Short Director

Goal: one performance video can become multiple high-quality short-video proposals.

- 9:16 short-video workflow.
- Highlight / hook candidate generation.
- Performer-aware crop proposals.
- Title / artist text proposals.
- Lyric caption plans.
- Restrained zoom / pan / effect plans.
- Natural / Cinematic / Lyric Focus / Social Hook / Minimal variants.
- `EditingPlan` intermediate representation evolved from Phase 1.5 `ShortEditDraft`.
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
- User-confirmed Song Memory must not be silently overwritten by provider or AI estimates.
- Song Resolver confidence must not become an implicit synchronization or identity authority.
- Calibration reports must not silently become production thresholds or weights.
- Private benchmark media must not be uploaded or committed by calibration tooling.
- Generative AI must not become the source of truth for synchronization.
