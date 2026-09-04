# Phase 7 Consistency Stabilization

## Status

Active reliability gate before Phase 7 Real Corpus Measurement resumes.

This gate does not add a new Resolver algorithm or AI feature. Its purpose is to make the already-merged TakeLayer Core, Short Foundation, Song Memory, Resolver, calibration tooling, persistence, recording, and CI agree on the same invariants.

## Why this gate exists

The repository had reached a point where individually correct features could still disagree at their boundaries. Examples found during the cross-cutting review included:

- millisecond offset precision preserved by `TimelineMapper` but rounded by one export path;
- a legacy coarse audio signature being treated as if it proved tonal identity;
- async Resolver/export work returning after the Project had already changed;
- persisted Song Memory links surviving after their referenced Song/Arrangement disappeared;
- persisted media metadata remaining present after the actual file was removed;
- production UI components being defined inside the historical ImportExportPoC folder;
- camera recording operations split across different execution contexts;
- diagnostic calibration thresholds being silently changed by clamping.

These are boundary-consistency defects, so they must be repaired before real-corpus measurements are trusted as evidence for the next Resolver gate.

## Active fixes

### Time and export consistency

- Use shared microsecond-resolution `MediaTime` conversion for AVFoundation `CMTime` creation.
- Preserve 1 ms manual offset steps in both normal and Short export paths.
- Keep `TimelineMapper` as the only synchronization arithmetic authority.
- Reject stale export completion when Project timing/media changed during rendering.

### Resolver and Song Memory consistency

- Do not interpret the legacy duration/energy/transient signature as tonal proof.
- When Tonal Evidence exists on both sides, compare it even if the legacy signature matches.
- Cap legacy no-tonal evidence below certainty.
- Keep separate tonal fingerprints when a coarse signature collides.
- Discard stale async Resolver evidence after WAV or Project linkage changes.
- Repair dangling Project Song Memory links when persisted data is restored.
- Restore a retained licensed-provider lyric pointer when user-confirmed lyrics are removed.
- Human confirmation remains mandatory for Resolver-derived identity links.

### Persistence and validation consistency

- Export validation verifies that persisted video and WAV URLs still exist on disk.
- Validation item identity is stable across recomputation.
- Decode compatibility may retain historical fields, but inactive settings must not be presented as configurable behavior.

### Recording consistency

- Serialize capture-session configuration, preview, record start, and record stop through the capture service queue boundary.
- Make countdown and Zen-mode delayed tasks cancellable.
- Guard duplicate stop transitions.

### Tooling and repository consistency

- Reject non-finite and out-of-range calibration thresholds instead of silently clamping them.
- Keep `ImportExportPoC` outside the active Xcode target.
- Move workflow UI used by production screens into `TakeLayer/Features/Shared/`.
- Keep the historical PoC source as reference only; active code must not depend on it.
- Remove obsolete CI branch-specific triggers.
- Add regression tests for repaired invariants.

## Guardrails

This gate must not:

- change the `TimelineMapper` formula without a demonstrated synchronization regression;
- auto-link a Song or Arrangement from Resolver confidence;
- tune production Resolver thresholds or weights from synthetic fixtures or an undersized corpus;
- introduce new AI Director proposal generation;
- upload private benchmark audio;
- destructively modify raw media by default.

## Completion criteria

The gate is complete only when the latest PR head satisfies all of the following:

1. Resolver calibration CLI compiles.
2. XcodeGen generates the project from a clean checkout.
3. iOS simulator build succeeds.
4. Full XCTest suite succeeds.
5. No unresolved review thread identifies a correctness defect.
6. Repository status documentation describes the actual active gate.
7. The merged `main` commit receives a green post-merge CI run.

After these criteria are met, Phase 7 Real Corpus Measurement becomes the next operational gate again.
