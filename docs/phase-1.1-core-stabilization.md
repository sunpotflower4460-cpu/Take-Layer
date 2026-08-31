# Phase 1.1 — Core Stabilization

## Purpose

Phase 1.1 is the reliability bridge between the merged Phase 1 MVP-α and any later short-video or AI work.

The goal is not to add creative AI features. The goal is to make the TakeLayer Core deterministic, buildable, testable, persistent, and safe enough that later automation can depend on it.

## Why this phase exists

The Phase 1 review found two synchronization defects and several infrastructure gaps:

1. `offsetMs` was stored in the UI/project but not applied during export.
2. Moving `selectedRawStartSec` away from `songStartRawSec` did not move the completed-WAV source start by the same Project Timeline amount.
3. The repository had Swift source but no reproducible Xcode project definition or CI build.
4. Project state did not survive app restart.
5. Timeline behavior had documentation test cases but no executable unit tests.
6. Camera session configuration occurred outside the dedicated session queue.
7. The export path used deprecated AVAssetExportSession completion/status APIs.

## Core invariant

All synchronization must flow through one deterministic mapping:

```text
raw video time
    ↓
Project Timeline
    ↓
completed-WAV time
```

No renderer, AI Director, short extractor, or future multi-camera editor may independently reimplement this arithmetic.

## Timeline mapping

Project Timeline is still defined as:

```text
videoRawSec - songStartRawSec = projectTimelineSec
```

The corresponding completed-WAV location is:

```text
songStartAudioSec + projectTimelineSec - offsetSec
```

Manual offset convention:

```text
offsetMs > 0  => delay completed WAV relative to video
offsetMs < 0  => advance completed WAV relative to video
```

If the mathematically correct WAV source position would be before WAV time zero, TakeLayer inserts the WAV later in the output instead of clamping the source time and silently breaking sync.

## Implemented scope

### TimelineMapper

`TakeLayer/Services/TimelineMapper.swift`

Responsibilities:

- video raw time → Project Timeline
- Project Timeline → completed-WAV source time
- trim-aware audio mapping
- manual offset application
- pre-roll handling
- output/audio overlap calculation
- validation errors for impossible mappings

### Export integration

`VideoExportService` consumes `TimelineMapping` rather than calculating video/audio starts independently.

The service now:

- applies trim and offset consistently
- supports audio insertion time when pre-roll requires it
- derives output duration from the mapping
- uses the current async `AVAssetExportSession.export(to:as:)` API

### Validation

`ExportValidationService` runs the same TimelineMapper before enabling export.

A project that cannot be mapped safely must fail validation before rendering.

### Executable tests

`TakeLayerTests/TimelineMapperTests.swift` covers:

- exact song-start mapping
- trim beginning after song start
- positive manual offset
- negative manual offset
- pre-roll when the master WAV lacks enough lead-in

Future synchronization defects should be added here as regression tests before fixes are merged.

### Reproducible Xcode build

`project.yml` is the source-of-truth XcodeGen project definition.

Generate locally with:

```bash
brew install xcodegen
xcodegen generate
open TakeLayer.xcodeproj
```

The generated `.xcodeproj` is intentionally reproducible from `project.yml` rather than hand-maintained as opaque project metadata.

### CI

`.github/workflows/ios-build.yml` generates the Xcode project, builds the iOS Simulator target, chooses an available iPhone simulator, and runs XCTest.

A green CI run becomes the minimum build gate for later phases.

### Project persistence

`ProjectStore` persists `ProjectDraft` as JSON under the app Documents directory.

Phase 1.1 intentionally uses a small transparent persistence layer rather than prematurely coupling the project to the final Song Memory schema.

Persisted values include:

- project title and ID
- imported/recorded media references and metadata
- `songStartRawSec`
- `songStartAudioSec`
- selected trim range
- `offsetMs`
- export settings
- timestamps

This is a bridge. A later data migration may move project/song memory to SwiftData while preserving `ProjectStore` as the persistence boundary.

### Camera session serialization

Capture-session configuration and start/stop work use the dedicated serial session queue so blocking capture operations do not execute on the main UI thread.

## Explicit non-goals

Phase 1.1 does not add:

- automatic synchronization
- waveform matching
- AI crop
- lyric captions
- short-video generation
- Song Memory
- external metadata lookup
- preference learning
- multi-part layout
- automatic drift correction

## Exit criteria

Phase 1.1 is complete when:

1. XcodeGen generates the project successfully.
2. iOS Simulator build succeeds in CI.
3. TimelineMapper XCTest passes.
4. `offsetMs` measurably affects exported synchronization.
5. changing trim start preserves Project Timeline synchronization.
6. saved project state restores after app restart.
7. no future phase needs to duplicate raw-video ↔ master-audio mapping arithmetic.

Only after these gates are green should the project move to the short-video foundation or later AI Director work.
