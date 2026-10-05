# Artist OS core boundary audit

Status: audit + guard rails. **No Swift source was changed and no file was moved.** The machine that produced this document has no Swift toolchain (download.swift.org blocked), so nothing below was compiled. Anything touching Swift semantics is listed in section 7 as UNVERIFIED. Scope follows `AGENTS.md`: no AI Director, Mac Companion, face tracking, auto-highlights, multi-camera, transitions or preference learning is added or enabled; `TimelineMapper` stays the single sync authority.

Intended dependency direction (arrows = "may depend on"):

```text
App/UI  ->  Rendering  ->  Analysis  ->  Core
```

Core = Foundation / CryptoKit only. Analysis = AVFoundation, no UI. Rendering = AVFoundation + CoreAnimation/CoreGraphics (and today UIKit). UI = SwiftUI/UIKit/AppKit.

## 1. Layer map (all 44 Swift files)

Method: imports by grep (`import` lines), then type-usage dependencies by scanning every capitalized identifier against all type declarations (struct/enum/class/protocol/typealias/actor) in the tree. Comments and string literals are ignored.

Counts: Core 14, Core-deferred 5, Core-by-import/Analysis-by-dependency 2, Analysis 4, Capture (iOS-only) 2, Rendering-geometry 1, Rendering 2, UI 13, Tool entry 1 (total 44).

| File | Imports | Class | Notes |
|---|---|---|---|
| `TakeLayer/ContentView.swift` | SwiftUI | UI | SwiftUI/UIKit/AVKit view or view model. |
| `TakeLayer/Features/ImportExportPoC/ImportExportPoCView.swift` | SwiftUI, UniformTypeIdentifiers | UI | Historical PoC; excluded from the app target by `project.yml`. |
| `TakeLayer/Features/ImportExportPoC/ImportExportPoCViewModel.swift` | AVFoundation, Combine, Foundation | UI | View model (ObservableObject/Combine); app layer. Uses AVFoundation directly. |
| `TakeLayer/Features/MVPAlpha/MVPAlphaFlowView.swift` | AVKit, SwiftUI, UniformTypeIdentifiers | UI | SwiftUI/UIKit/AVKit view or view model. |
| `TakeLayer/Features/MVPAlpha/MVPAlphaViewModel.swift` | AVFoundation, Combine, Foundation | UI | View model (ObservableObject/Combine); app layer. Uses AVFoundation directly. |
| `TakeLayer/Features/Recording/CameraPreviewView.swift` | AVFoundation, SwiftUI, UIKit | UI | SwiftUI/UIKit/AVKit view or view model. Imports UIKit. |
| `TakeLayer/Features/Recording/RecordingView.swift` | SwiftUI | UI | SwiftUI/UIKit/AVKit view or view model. |
| `TakeLayer/Features/Recording/RecordingViewModel.swift` | Combine, Foundation | UI | View model (ObservableObject/Combine); app layer. |
| `TakeLayer/Features/Shared/WorkflowComponents.swift` | AVKit, SwiftUI | UI | SwiftUI/UIKit/AVKit view or view model. |
| `TakeLayer/Features/ShortFoundation/ShortFoundationView.swift` | AVFoundation, SwiftUI, UIKit | UI | SwiftUI/UIKit/AVKit view or view model. Imports UIKit. |
| `TakeLayer/Features/SongIntelligence/SongMemoryEditorView.swift` | SwiftUI | UI | SwiftUI/UIKit/AVKit view or view model. |
| `TakeLayer/Features/SongIntelligence/SongResolverEvidenceView.swift` | SwiftUI | UI | SwiftUI/UIKit/AVKit view or view model. |
| `TakeLayer/Models/ExportSettings.swift` | Foundation | Core |  |
| `TakeLayer/Models/ImportedMasterAudio.swift` | Foundation | Core |  |
| `TakeLayer/Models/ImportedVideo.swift` | Foundation | Core |  |
| `TakeLayer/Models/ProjectDraft.swift` | Foundation | Core |  |
| `TakeLayer/Models/RecordedTake.swift` | Foundation | Core |  |
| `TakeLayer/Models/ResolverCalibrationModels.swift` | Foundation | Core |  |
| `TakeLayer/Models/ResolverPrivateCorpusModels.swift` | Foundation | Core |  |
| `TakeLayer/Models/ShortEditDraft.swift` | Foundation | Core |  |
| `TakeLayer/Models/SongMemoryModels.swift` | Foundation | Core |  |
| `TakeLayer/Models/SongResolverEvidenceModels.swift` | Foundation | Core |  |
| `TakeLayer/Services/AudioEvidenceExtractor.swift` | AVFoundation, CryptoKit, Foundation | Analysis | AVFoundation, headless-capable (already compiled by the macOS CLI). Mutually references `TonalEvidenceExtractor`. |
| `TakeLayer/Services/CameraRecordingService.swift` | AVFoundation, Foundation | Capture (iOS-only) | AVFoundation but AVCaptureSession/MovieFileOutput recording; not an Analysis concern, iOS-only. |
| `TakeLayer/Services/ExportValidationService.swift` | Foundation | Core |  |
| `TakeLayer/Services/MediaImportStore.swift` | Foundation | Core-deferred | Foundation only; copies picked files into app Documents (security-scoped URL API). |
| `TakeLayer/Services/MediaInfoReader.swift` | AVFoundation, Foundation, UniformTypeIdentifiers | Analysis | AVFoundation + UniformTypeIdentifiers; no UI. |
| `TakeLayer/Services/MediaTime.swift` | AVFoundation, Foundation | Analysis | CMTime helper (CoreMedia via AVFoundation); shared by both renderers. Could move to a tiny AV-only module. |
| `TakeLayer/Services/ProjectStore.swift` | Foundation | Core-deferred | Foundation only; persists to iOS `documentDirectory` (absolute-URL JSON, no schemaVersion). |
| `TakeLayer/Services/RecordingFileStore.swift` | Foundation | Core-deferred | Foundation only; iOS recording file paths. |
| `TakeLayer/Services/RecordingPermissionService.swift` | AVFoundation, Foundation | Capture (iOS-only) | AVFoundation permission APIs for recording. |
| `TakeLayer/Services/ResolverCalibrationHarness.swift` | Foundation | Core-by-import / Analysis-by-dependency | Imports Foundation only but calls `AudioEvidenceExtractor` (AVFoundation) directly: Core -> Analysis edge. Not in Core list. |
| `TakeLayer/Services/ResolverPrivateCorpusRunner.swift` | CryptoKit, Foundation | Core-by-import / Analysis-by-dependency | Foundation+CryptoKit but default argument is `AudioEvidenceExtractor.extract`, and it uses `ResolverCalibrationHarness`. Not in Core list. |
| `TakeLayer/Services/ShortRenderGeometry.swift` | CoreGraphics | Rendering-geometry | CoreGraphics only (no UIKit); pure math on `ShortCropPlan`; macOS-capable. Core-eligible if the Core rule were widened to CoreGraphics. |
| `TakeLayer/Services/ShortVideoExportService.swift` | AVFoundation, Foundation, QuartzCore, UIKit | Rendering | `import UIKit`; uses only `UIColor.white/.black` (2x each as `.cgColor`). |
| `TakeLayer/Services/SongMemoryStore.swift` | Foundation | Core-deferred | Foundation only; single-file store under `documentDirectory`, no locking. |
| `TakeLayer/Services/SongResolver.swift` | Foundation | Core |  |
| `TakeLayer/Services/SongResolverEvidenceStore.swift` | Foundation | Core-deferred | Foundation only; `documentDirectory` store. |
| `TakeLayer/Services/TimelineMapper.swift` | Foundation | Core |  |
| `TakeLayer/Services/TonalEvidenceExtractor.swift` | AVFoundation, Foundation | Analysis | AVFoundation, headless-capable. |
| `TakeLayer/Services/VideoExportService.swift` | AVFoundation, Foundation, UIKit | Rendering | `import UIKit` but NO UIKit symbol is used (see section 3). Defines shared `ExportResult`. |
| `TakeLayer/TakeLayerApp.swift` | SwiftUI | UI | SwiftUI/UIKit/AVKit view or view model. |
| `TakeLayer/Utilities/TimeFormatting.swift` | Foundation | Core |  |
| `tools/ResolverCalibrationCLI.swift` | Darwin, Foundation | Tool entry | Darwin+Foundation; macOS-only via `xcrun swiftc`. |

### Cross-direction findings (by type usage, not just imports)

- **No non-UI file references a UI type.** The only edge into the UI set is `TakeLayerApp -> ContentView` (the app entry, itself UI).
- **No Core-list file references a type outside the Core list.** This is now enforced by `tools/check-core-boundary.sh` (step 2).
- **Violating edge (pre-existing, documented, not fixed):** `ResolverCalibrationHarness` and `ResolverPrivateCorpusRunner` import only Foundation/CryptoKit, so an import-only audit calls them Core. They call `AudioEvidenceExtractor` (AVFoundation) directly, which is a Core -> Analysis edge. `docs/artist-os-integration-contract.md` section 3 previously listed the harness as Core; that was import-only reasoning and is corrected there. Fixing it means injecting the extractor (the runner already takes a closure parameter with `AudioEvidenceExtractor.extract` as the default argument; the harness hard-codes it at `ResolverCalibrationHarness.swift:33-34`). Not done (needs a compiler).
- `AudioEvidenceExtractor` and `TonalEvidenceExtractor` reference each other (same layer, fine).
- `ShortVideoExportService -> VideoExportService` is only for the shared `ExportResult` struct (Rendering -> Rendering). `ExportResult` is a plain value type and belongs in Core or a render-neutral file.
- `MediaTime` (CMTime) is used by both renderers and by `ShortFoundationView` (UI preview). It is Analysis-level (CoreMedia), fine for Rendering/UI to depend on.
- `ExportValidationService` is Foundation-only and depends only on `ProjectDraft`/`TimelineMapper`/`TimeFormatting`. It checks `FileManager.fileExists` on stored URLs, so it validates only same-machine paths.
- ShortEditDraft/ProjectDraft/ImportedVideo/ImportedMasterAudio are Core models but persist **absolute URLs** (Codable `URL`), which are not portable across machines.

## 2. TakeLayerCore closure (Package.swift)

`Package.swift` (repo root, swift-tools-version 5.9, macOS 13 / iOS 17) defines library `TakeLayerCore` with `path: "TakeLayer"` and an explicit `sources:` list of 14 files. The list is the same as `tools/core-files.txt` (single source of truth; the check script fails if they drift).

Files (all Foundation-only imports): `Models/{ExportSettings, ImportedMasterAudio, ImportedVideo, ProjectDraft, RecordedTake, ResolverCalibrationModels, ResolverPrivateCorpusModels, ShortEditDraft, SongMemoryModels, SongResolverEvidenceModels}.swift`, `Services/{ExportValidationService, SongResolver, TimelineMapper}.swift`, `Utilities/TimeFormatting.swift`.

How the closure was established: every capitalized identifier in each chosen file was matched against all declared types in the tree. Dependencies found: `TimelineMapper -> ProjectDraft`; `ProjectDraft -> ExportSettings, ImportedMasterAudio, ImportedVideo, ProjectSongMemoryLink (SongMemoryModels), RecordedTake, ShortEditDraft`; `RecordedTake -> ImportedVideo/MediaOrientation`; `ResolverCalibrationModels -> SongResolverEvidenceModels`; `ResolverPrivateCorpusModels -> ResolverCalibrationModels`; `SongResolver -> SongResolverEvidenceModels, SongMemoryModels`; `ExportValidationService -> ProjectDraft, TimelineMapper, TimeFormatting`. `SongResolver.swift` also holds `extension SongMemoryLibrary` (declared in `SongMemoryModels`, in the list). All of these are inside the list.

Supporting evidence (not a build of the package): five of the 14 files (`SongMemoryModels`, `SongResolverEvidenceModels`, `ResolverCalibrationModels`, `ResolverPrivateCorpusModels`, `SongResolver`) are already compiled together by `xcrun swiftc` in `tools/run-resolver-calibration.sh` in the existing iOS CI job, and all 14 compile inside the iOS app target. Compiling them as a standalone module has not been done.

Excluded, with reasons:

- `ResolverCalibrationHarness`, `ResolverPrivateCorpusRunner`: depend on `AudioEvidenceExtractor` (Analysis).
- `ProjectStore`, `SongMemoryStore`, `SongResolverEvidenceStore`, `MediaImportStore`, `RecordingFileStore`: Foundation-only but persist to iOS `documentDirectory`; including them would be a policy decision (portable store paths), not a closure fact. TODO.
- `ShortRenderGeometry`: CoreGraphics only; pure math; eligible only if the allowlist is widened to CoreGraphics. TODO.
- `MediaTime`, extractors, `MediaInfoReader`: AVFoundation (Analysis).

Caveats (manifest **unverified locally (no Swift toolchain)**):

1. All types are `internal`. Even if the package compiles, another module (app, CLI, Mac worker) cannot call `TimelineMapper` until the needed API is made `public` (or `@testable import` is used in tests). That is a source change across many types and was not done. Also the iOS app still compiles these files directly; the package is additive and nothing consumes it yet.
2. The package targets Swift 5 language mode (tools 5.9). `project.yml` uses `SWIFT_VERSION 5.10`; no mismatch expected.
3. With `path: "TakeLayer"` and an explicit `sources:` list, SwiftPM should ignore the other files in that directory; whether it prints "unhandled file" warnings for e.g. `Resources/` was not observed.
4. `project.yml`, the iOS CI job (`.github/workflows/ios-build.yml`) and `tools/run-resolver-calibration.sh` are untouched. Its 10 source paths were all confirmed to exist.

## 3. VideoExportService and ShortVideoExportService

### Exact UIKit usage

Both files contain `import UIKit`. Symbol search (`UI[A-Z]\w+`, `UIScreen`, `UIImage`, `UIFont`, `UIGraphicsImageRenderer`) gives:

| File | UIKit symbols actually used |
|---|---|
| `VideoExportService.swift` | **None.** Only the `import UIKit` line (line 3). Everything else is AVFoundation plus CoreGraphics value types (`CGSize`, `CGRect`, `CGAffineTransform`) and `CMTime`. |
| `ShortVideoExportService.swift` | `UIColor.white.cgColor` (line 250, text foreground) and `UIColor.black.cgColor` (line 251, text shadow), both in `textLayer(...)`. No `UIImage`, `UIFont`, `UIGraphicsImageRenderer`, `UIScreen`. The font is not set (CATextLayer default). `contentsScale` is hard-coded to 2, not read from `UIScreen`. |

Elsewhere in the app UIKit appears only in `Features/Recording/CameraPreviewView.swift` and `Features/ShortFoundation/ShortFoundationView.swift` (UI layer).

### What is headless-capable on macOS

- Capable by API family (all exist on macOS): `AVURLAsset`, `AVMutableComposition`, `AVMutableVideoComposition`, `AVMutableVideoCompositionLayerInstruction`, `AVAssetExportSession`, `CMTime`/`MediaTime`, `CGAffineTransform`, `CALayer`/`CATextLayer`/`CAKeyframeAnimation` (QuartzCore), `AVVideoCompositionCoreAnimationTool`, `AVCoreAnimationBeginTimeAtZero`.
- Needs checking on a Mac (not assumed): whether the overlay path (`AVVideoCompositionCoreAnimationTool` + `CATextLayer`) renders correctly in a window-less CLI process; the async `AVAssetExportSession.export(to:as:)` used at `VideoExportService.swift:128` and `ShortVideoExportService.swift:131` (I believe this is a recent-SDK API; its macOS availability and the deployment target needed for it were not verified); `FileManager ... .documentDirectory` resolves to `~/Documents` on macOS.
- Pure math already portable: `TimelineMapper` and `ShortRenderGeometryBuilder`.

### Minimal separation (ordered, with risk)

1. **Drop `import UIKit` from `VideoExportService.swift`.** No UIKit symbol is used. Risk: low, but CoreGraphics types might have been reaching the file through UIKit; if AVFoundation does not re-export them the build breaks. Safe form: replace with `import CoreGraphics` (or `QuartzCore`). Needs a compile. NOT DONE.
2. **Replace `UIColor.white.cgColor` / `UIColor.black.cgColor` in `ShortVideoExportService.swift` with `CGColor(gray: 1, alpha: 1)` / `CGColor(gray: 0, alpha: 1)`** and drop `import UIKit` (keep `import QuartzCore`, add `import CoreGraphics`). `CGColor(gray:alpha:)` exists on both platforms. The two edits are mechanical but they alter pixels only if the color space differs (UIColor white is a gray/sRGB-extended color, `CGColor(gray:)` is device/generic gray; visually identical, not pixel-verified). No protocol is needed for two constants; a protocol (for fonts/images) would only be justified if a later feature needs UIImage/UIFont, which is not in scope. NOT DONE. Risk: low-medium (text overlay look on iOS must not change; the iOS UI must keep working, so it needs the existing iOS CI plus a visual check).
3. **Separate preview from rendering core.** `ShortFoundationView` (UI) only imports `MediaTime` and `TimelineMapper` for seeking; it does not share code with the export services except via `ShortVideoExportService.export`. So the export services are already callable without UI. The separation that matters is a module boundary (Rendering target), plus making the output location injectable (both hard-code `documentDirectory` in `makeOutputURL`). Risk: medium (API shape change of `export`); NOT DONE.
4. **Move `ExportResult` out of `VideoExportService.swift`** so `ShortVideoExportService` does not depend on the other renderer. Risk: low. NOT DONE.
5. **Create `TakeLayerRendering` SwiftPM target** (AVFoundation + QuartzCore + CoreGraphics; requires Core and `MediaTime` public) and a macOS CI job that runs `swift build`. Risk: medium; requires step 1-2 plus public API surface. NOT DONE.

### Not done because it cannot be verified without a compiler

Steps 1-5 above, any `public` annotation, the harness extractor injection, a `swift build` of `Package.swift`, and any move of `ExportResult`/`MediaTime`.

## 4. What is now enforced by script (`tools/check-core-boundary.sh`, runs on Linux and macOS; no Swift)

Run in CI by the new workflow `.github/workflows/core-boundary.yml` (ubuntu-latest). It reads `tools/core-files.txt` and fails on:

1. a listed file that is missing;
2. an `import` of any module outside `Foundation`, `CryptoKit` (comments stripped; handles `@preconcurrency import` and `import struct X.Y`);
3. any of the tokens `UIKit SwiftUI AVFoundation AVKit AppKit UIImage UIColor UIFont UIScreen QuartzCore CoreAnimation CALayer CATextLayer` in a Core file (comments stripped);
4. a Core file that references a type declared in any non-Core Swift file under `TakeLayer/` or `tools/` (the direction check; found by reading identifiers, not imports);
5. `Package.swift` sources drifting from `tools/core-files.txt`;
6. **TimelineMapper authority** (scans `TakeLayer/` and `tools/`, excluding `Services/TimelineMapper.swift`; `TakeLayerTests` is not scanned because tests compute expectations):
   - G1: a line that mentions `offsetMs` together with a `/ 1000` / `/ 1_000` / `0.001` conversion (the ms-to-s step in `masterAudioSec`);
   - G2: a line with a spaced binary `+`/`-` that contains two or more distinct sync identifiers from `songStartRawSec, songStartAudioSec, offsetMs, projectTimelineSec, videoRawSec, masterAudioSec, audioSourceStartSec, audioInsertionTimeSec` (this is the shape of `projectTimelineSec`, `videoRawSec`, `masterAudioSec`);
   - G3: re-declaration of `func projectTimelineSec|videoRawSec|masterAudioSec|remapProjectTimelineSec|makeMapping`.

Verified here: it **passes on the current tree** (14 core files, exit 0). It **fails** on a deliberately violating copy (outside the repo): `import UIKit` in a Core file, a Core file referencing `ShortRenderGeometry`, an `offsetMs / 1_000.0` expression and a re-declared `videoRawSec` in a Features file, and a drifted `Package.swift`.

Limits (be honest about them): it is line-based and lexical. It will not catch arithmetic split across lines, a sync value copied into a differently named local (`let s = project.songStartRawSec ?? 0; t - s`), arithmetic with a single family identifier (`raw - songStartRawSec` on its own line is not flagged by G2), or a numeric literal in place of the `1_000.0`. Existing legitimate uses that it deliberately tolerates: default selection range (`songStartRawSec + effectiveDuration`, `MVPAlphaViewModel` ~line 463) and effective audio duration (`audio.durationSec - songStartAudioSec`), which are duration bookkeeping with one sync identifier. It is a tripwire for the obvious copy of the mapper, not a proof. The existing `TimelineMapperTests` remain the regression authority.

## 5. Mac capability analysis

Today, the only headless entry point is `tools/run-resolver-calibration.sh` (-> `tools/ResolverCalibrationCLI.swift`).

### (a) Resolver calibration CLI (runnable today)

- Input: private-corpus manifest JSON, `schemaVersion` 1 (rejects unknown versions), with `--root` for audio base directory; optional `--dataset`, `--report`, `--thresholds`.
- Output: `derived-dataset.json` and `report.json`.
- Platform: macOS only (`xcrun swiftc`; the script is compiled in the existing iOS CI job with `--help`).
- Constraint: private corpus audio must never be uploaded or committed (`ResolverBenchmarks/Private/` is git-ignored).
- It is a measurement tool for the active gate (Real Corpus Measurement), not a product job. Artist OS job type name: **`RESOLVER_CALIBRATION`** (the Artist OS side adds this exact name; it is not overloaded onto `SONG_RESOLUTION`). `docs/artist-os/mac-runner-capabilities.json` now carries `artistOsJobType: "RESOLVER_CALIBRATION"` on `resolver_calibration` and lists `SONG_RESOLUTION` and `RENDER_EXISTING_EDIT_PLAN` as unsupported.

### (b) `SONG_RESOLUTION` per song: blocked

- The resolver (`SongResolver`) and extractors exist as library code, but no entry takes "one query audio + a Song Memory / evidence library" and returns candidates. The CLI consumes a corpus manifest of labelled cases, not a library.
- The evidence library and Song Memory live in the iOS app's Documents (`SongMemoryStore`, `SongResolverEvidenceStore`), are unversioned JSON, single-file, no locking, and `AGENTS.md` forbids resolver confidence from creating or replacing a Song Memory link; so a job could only return candidates with evidence, never a link.
- No schema or export format exists for sending a library to a Mac.

### (c) `RENDER_EXISTING_EDIT_PLAN` from a valid `ShortEditDraft`: blocked

1. Rendering files import UIKit (section 3; trivial usage, but the module cannot be built into a macOS CLI until it is removed and compiled).
2. `ShortVideoExportService.export(project:draft:)` needs the whole `ProjectDraft` (song starts, offset, active video, WAV), not just the draft. `ShortEditDraft` alone is not a renderable plan.
3. `ProjectDraft` persists `ImportedVideo.url` and `ImportedMasterAudio.url` as absolute iOS-container URLs; they do not exist on a Mac. A runner needs an asset-id plus `sha256` mapping to local files (contract section 5).
4. No `schemaVersion` on `ShortEditDraft`, `ProjectDraft` or any persisted project JSON.
5. No headless entry point, and the output location is hard-coded to `documentDirectory` with a random file name.
6. Unverified on macOS: CoreAnimation text overlay in a headless process; the export-session API availability (section 3).
7. A `ShortEditDraft` JSON schema and fixture are provided (`docs/artist-os/schemas/short-edit-draft.schema.json`, `docs/artist-os/fixtures/short-edit-draft.example.json`) derived from the synthesized Codable of `ShortEditDraft.swift`; the fixture validates against the schema with Python `jsonschema`. It documents today's unversioned shape and is explicitly **not** a stable contract and was not round-tripped through Swift. A `ProjectDraft` schema was **not** written: it needs the `SongMemoryModels` link type and decisions about URL handling, so that is a TODO rather than a guess.

### Recommendation: first honest Mac capability and next step

- **First Mac capability = `RESOLVER_CALIBRATION` (already real).** It is the only job with a real handler, needs no refactor, and directly serves the active gate. Claim nothing else.
- **ONE next step: prove the Core package builds on a Mac, in a separate CI job.** Ordered, verifiable plan:
  1. Add a new workflow (not the existing iOS one) on `macos-latest` that runs `swift build --target TakeLayerCore` (verifies section 2's closure and `Package.swift` for real).
  2. Only then, one PR: drop `import UIKit` in `VideoExportService`, `UIColor` -> `CGColor(gray:)` in `ShortVideoExportService`, and move `ExportResult`, verified by the existing iOS build + XCTest and the macOS job compiling a `TakeLayerRendering` target.
  3. Then a schema-versioned render-request DTO (draft + sync parameters + asset-id/sha256 map + output path) and a headless `render-short` CLI, with a golden-duration test through `TimelineMapper`.
  4. Only after 3, advertise `RENDER_EXISTING_EDIT_PLAN` in `mac-runner-capabilities.json`.
  Why this one: it is the cheapest step that converts the largest unverified item (the manifest) into a fact, and every later capability (render, per-song resolution) depends on it.

## 6. Artist OS contract pointer

`docs/artist-os-integration-contract.md` now references this document and `tools/check-core-boundary.sh`.

## 7. UNVERIFIED (no compiler) and not done

- `Package.swift` was never run through SwiftPM (manifest unverified locally (no Swift toolchain)); the 14-file closure is by textual type analysis only.
- No `public` API exists on Core types; no consumer of the package exists.
- Steps 1-5 of section 3, the harness extractor injection, and relocating `ExportResult` were not performed.
- The claims about macOS availability of `AVAssetExportSession.export(to:as:)` and headless CoreAnimation text rendering are open questions.
- The ShortEditDraft schema/fixture were validated against each other, not against a Swift encoder/decoder.
- The authority guard is a heuristic with the limits stated in section 4.
