# TakeLayer Documentation Map

## Current core design

Read these first when working on the active TakeLayer implementation.

1. `../AGENTS.md`
2. `phases.md`
3. `phase-1.1-core-stabilization.md`
4. `phase-1.5-short-foundation.md`
5. `phase-7-song-intelligence-foundation.md`
6. `phase-7-song-resolver-evidence.md`
7. `phase-7-tonal-evidence.md`
8. `phase-7-elastic-tonal-alignment.md`
9. `phase-7-resolver-calibration-harness.md`
10. `architecture.md`
11. `mvp-scope.md`
12. `data-model.md`
13. `non-goals.md`
14. `testing-cases.md`
15. `codex-instructions.md`
16. `glossary.md`
17. `../README.md` — historical integrated v1.2 design; use `phases.md` for current implementation status.

## Reliability and deterministic editing foundations

### `phase-1.1-core-stabilization.md`

- authoritative TimelineMapper
- real `offsetMs` application
- trim-aware master-audio mapping
- pre-roll handling
- reproducible XcodeGen project
- macOS CI build and XCTest
- local Project persistence
- capture-session serialization
- modern async export path

### `phase-1.5-short-foundation.md`

- deterministic 9:16 Short editing
- Project Timeline range extraction
- crop / zoom / pan plan
- title and timed lyric layers
- preview → micro-adjustment → export

## Phase 7 Song Intelligence

### `phase-7-song-intelligence-foundation.md`

Human-confirmed musical-work memory:

- SongIdentity / SongProfile
- Song / Arrangement separation
- FormalLyrics
- Project ↔ Song Memory linkage
- user-confirmed information precedence

### `phase-7-song-resolver-evidence.md`

Merged deterministic candidate-evidence foundation:

- completed-WAV evidence extraction
- duration / energy / transient shape
- Arrangement fingerprint registration
- confidence-ranked candidates
- explicit human confirmation

### `phase-7-tonal-evidence.md`

Merged tonal matching foundation:

- 12 pitch classes
- 32 normalized-time Chroma-like frames
- global tonal distribution
- transposition-aware comparison
- tuning tolerance
- backwards-compatible fingerprint enrichment
- explainable tonal score and key-shift evidence

### `phase-7-elastic-tonal-alignment.md`

Merged structural-tolerance foundation:

- bounded semi-global DTW-style comparison over the fixed 32 tonal frames
- modest intro / outro endpoint tolerance
- section stretch / compression tolerance
- explainable tonal structure coverage
- explainable elastic warp fraction
- transposition-aware comparison retained
- human confirmation and TimelineMapper authority retained

### `phase-7-resolver-calibration-harness.md`

Active measurement gate:

- labeled same-Arrangement / same-song-different-Arrangement / different-song cases
- real completed-WAV URLs converted into deterministic benchmark evidence
- no raw WAV bytes stored in dataset JSON
- per-label confidence distributions
- observed positive / negative confidence gap
- threshold confusion matrix and precision / recall / specificity / F1 / balanced accuracy
- deterministic inspectable JSON datasets and reports
- no automatic threshold or Resolver weight changes

## Future AI Music Video Director

These documents define the long-term extension in which TakeLayer becomes a song-aware, preference-learning editing assistant.

### `ai-director-vision.md`

Product and architecture vision:

- upload-only short-video workflow
- same-song recognition
- existing-song metadata candidates
- high-accuracy lyric alignment
- automatic highlight selection
- crop / title / effects / editing proposals
- multiple proposal styles
- Editing Plan intermediate representation
- deterministic renderer
- Quality Gate
- multi-part extension

### `song-memory-feedback.md`

Memory and learning design:

- Song-specific memory
- Artist/project memory
- User-wide preference memory
- approval / rejection signals
- edit-delta learning
- context-aware preferences
- anti-overlearning safeguards
- explainable recommendations
- memory reset / forget controls

### `ai-director-data-model.md`

Future conceptual entities:

- SongIdentity
- SongProfile
- ArrangementProfile
- SongMatchResult
- FormalLyrics
- LyricsAlignment
- EditProposal
- EditingPlan
- EditDecision
- EditDelta
- PreferenceSignal
- LearnedEditingPreference
- MetadataCandidate
- QualityGateResult

## Architecture rule

Future AI features must extend the existing TakeLayer Core rather than replacing it.

```text
User / Review UI
      ↓
AI Director
      ↓
Song Memory + Preference Memory
      ↓
Editing Plan + Quality Gate
      ↓
TimelineMapper
      ↓
TakeLayer Core media processing
```

The current implementation phase remains authoritative. Future design documents are not permission to implement later-phase features early.
