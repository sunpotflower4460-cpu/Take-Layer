# TakeLayer Documentation Map

## Current core design

Read these first when working on the active TakeLayer implementation.

1. `../AGENTS.md`
2. `phases.md`
3. `phase-1.1-core-stabilization.md`
4. `architecture.md`
5. `mvp-scope.md`
6. `data-model.md`
7. `non-goals.md`
8. `testing-cases.md`
9. `codex-instructions.md`
10. `glossary.md`
11. `../README.md` — historical integrated v1.2 design; use `phases.md` for current implementation status.

## Phase 1.1 Core Stabilization

### `phase-1.1-core-stabilization.md`

Current reliability gate between merged Phase 1 and later feature expansion:

- authoritative TimelineMapper
- real `offsetMs` application
- trim-aware master-audio mapping
- pre-roll handling
- reproducible XcodeGen project
- macOS CI build and XCTest
- local Project persistence
- capture-session serialization
- modern async export path

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
