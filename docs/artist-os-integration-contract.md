# Artist OS integration contract (boundary only)

Status: **documentation of a boundary. No Swift code, no Mac Companion, no AI Director, no cloud sync is added or activated by this document.** Phase 7 Real Corpus Measurement remains the active gate (see `AGENTS.md`). Everything marked *planned* below is not implemented and must never be emitted as if it were.

Artist OS is a separate repository that *coordinates* TakeLayer with the other artist systems. TakeLayer remains the source of truth for songs, arrangements, Song Memory, synchronization and editing preferences.

## 1. Ownership

| Concept | Owner | Artist OS may |
|---|---|---|
| `SongIdentity.id` (songId), `ArrangementProfile.id` (arrangementId) | TakeLayer | hold them as opaque references via its Identity Graph |
| `ProjectDraft.id` (projectId) | TakeLayer | hold as opaque reference |
| Song Memory (`SongMemory/library.json`) | TakeLayer | **never read the file directly**; only an export TakeLayer produces |
| Timeline synchronization (`TimelineMapper`) | TakeLayer | never recompute it; never duplicate its arithmetic |
| User-confirmed song metadata / lyrics | TakeLayer | never overwrite |
| Edit proposals, preferences, quality gate | TakeLayer (*planned*) | consume as typed Artifacts only once emitted |

Artist OS links a TakeLayer song to a release through **explicit, human-confirmed** identity links. A title match is never sufficient.

## 2. What exists today vs planned

| Capability | State | Source |
|---|---|---|
| Timeline sync (raw video ↔ project ↔ WAV) | **exists**, iOS app only | `TakeLayer/Services/TimelineMapper.swift` |
| `ShortEditDraft` | **exists** (Codable struct; "EditingPlan precursor") | `docs/phases.md` |
| Song Resolver + calibration CLI | **exists**; the only headless entry point | `tools/run-resolver-calibration.sh` |
| `EditingPlan`, `EditProposal`, `EditDecision`, `EditDelta` | **planned** (design only) | `docs/ai-director-data-model.md` |
| Quality Gate | **planned** | docs only |
| AI Director | **planned**, not active | `AGENTS.md` |
| Headless render / sync / export | **not available**: rendering imports UIKit (iOS-only) | `VideoExportService`, `ShortVideoExportService` |

## 3. Layer map (for a future Mac worker)

Derived from Swift `import`s and type usage at audit time (2026-10-05). Full per-file audit, the `TakeLayerCore` SwiftPM closure (`Package.swift`, unverified locally) and the UIKit analysis of the export services: `docs/artist-os-core-boundary.md`. The boundary and the TimelineMapper-authority tripwire are enforced by `tools/check-core-boundary.sh` (CI: `.github/workflows/core-boundary.yml`):

- **Core (Foundation-only, portable):** the 14 files in `tools/core-files.txt` (`Models/*`, `TimelineMapper`, `SongResolver`, `ExportValidationService`, `TimeFormatting`). Foundation-only but deferred (persist to iOS Documents): `ProjectStore`, `SongMemoryStore`, `SongResolverEvidenceStore`, `MediaImportStore`, `RecordingFileStore`. `ResolverCalibrationHarness` and `ResolverPrivateCorpusRunner` import only Foundation/CryptoKit but call `AudioEvidenceExtractor` (Analysis), so they are not Core by dependency.
- **Analysis (AVFoundation, no UI):** `AudioEvidenceExtractor`, `TonalEvidenceExtractor`, `MediaInfoReader`.
- **Rendering:** `VideoExportService`, `ShortVideoExportService` — import UIKit; **iOS-only**, cannot run headless today. (Actual UIKit use is only `UIColor.white/.black` in the Short service; none in `VideoExportService`. Not yet changed: no compiler.)
- **UI:** SwiftUI (with AVKit/UIKit in a few views). No AppKit.

A Mac worker becomes feasible only after rendering is separated from UIKit. That is a TakeLayer-side decision and is out of scope here.

## 4. Mac Runner compatibility

Artist OS Mac jobs are **typed** (no free-form commands). The table states which job types TakeLayer can serve:

| Artist OS job type | TakeLayer status |
|---|---|
| `SONG_RESOLUTION` | partial: resolver exists, but only as the calibration CLI (corpus manifest in, report out); no per-song job entry |
| `AUDIO_ANALYSIS`, `MEDIA_ANALYSIS` | not exposed headlessly (extractors exist as library code) |
| `VIDEO_ANALYSIS`, `LYRICS_ALIGNMENT` | not in TakeLayer |
| `GENERATE_EDIT_PROPOSALS`, `MEDIA_QUALITY_GATE`, `GENERATE_SHORT_VARIANTS` | planned (AI Director / Quality Gate) |
| `RENDER_EDIT_PLAN`, `EXTRACT_THUMBNAIL_CANDIDATES` | blocked: UIKit-bound rendering |

`docs/artist-os/mac-runner-capabilities.json` is the static manifest: only `resolver_calibration` is listed as runnable, with Artist OS job type `RESOLVER_CALIBRATION` (a separate name; per-song `SONG_RESOLUTION` and `RENDER_EXISTING_EDIT_PLAN` are unsupported). A Runner must report a job type as supported only if it has a real handler; Artist OS never queues work to a Runner that does not list it, and a stub must fail with `unsupported`, never a fake success.

## 5. Data and portability rules

- **No raw paths in contracts.** Persisted media references in project JSON are absolute iOS-container URLs; they are not portable and must not be serialized into any Artist OS-visible document. Use a runner-local asset id plus a `sha256:<hex>` content hash.
- **Do not serialize `ProjectDraft` directly.** A future export is a separate DTO layer with an explicit `schemaVersion` (project/Song Memory/evidence JSON currently carry none; only the resolver corpus manifest/dataset/report are versioned, `schemaVersion` 1 with reject-on-unknown).
- **Song Memory is a single file with no locking.** External access must be export-based and read-only.
- **Private corpus audio must never be uploaded or committed.**
- Planned artifacts must carry `schemaVersion`, and unknown versions must be rejected rather than guessed.

## 6. Artifact contract (planned shape, not emitted)

When EditProposals exist they should arrive at Artist OS as an `EditProposalArtifact` envelope:

```json
{
  "schemaVersion": 1,
  "artifactId": "…",
  "kind": "EditProposalArtifact",
  "producer": "take-layer",
  "subjectRefs": [{ "system": "take-layer", "entityType": "song", "entityId": "<SongIdentity.id>" }],
  "payloadVersion": 1,
  "payload": { "…": "versioned EditingPlan + confidence + rationale summary" }
}
```

Rules: inspectable, reversible, confidence-aware; the renderer executes a validated plan deterministically; a generative model never mutates raw media state directly; human selection and corrections are returned to TakeLayer for preference learning. Approval stays in TakeLayer; Artist OS only projects "needs your selection" and links in.

## 7. Safety

- Artist OS never connects to TakeLayer storage; the only exchange is explicit exports/job envelopes.
- Nothing here weakens `TimelineMapper` authority or the song-information precedence in `AGENTS.md`.
- Resolver confidence alone must not create or replace a Song Memory link, and Artist OS must not either.
