# TakeLayer Architecture

## Overview

TakeLayer aligns raw performance videos and a DAW-exported completed WAV onto one shared project timeline. It does not operate a DAW directly. The user exports a completed WAV from the DAW, then TakeLayer uses that WAV as the reference audio for video assembly.

## Project timeline

Project timeline 0:00 equals the song start.

All media is placed on this timeline:

```text
Video take:  songStartRawSec   → Project timeline 0:00
Master WAV:  songStartAudioSec → Project timeline 0:00
```

The project timeline is not the recording timeline and not necessarily the WAV file's byte-zero or sample-zero position. It is the musical timeline used by TakeLayer.

## songStartRawSec

`songStartRawSec` is the second value inside a raw video that corresponds to Project timeline 0:00.

Example:

```text
raw video 48.32 seconds = Project timeline 0:00
```

This separates the recording start from the song start. A performer may start recording, wait, count in, fail once, speak, then begin the real take. `songStartRawSec` points to the actual song start inside that raw video.

## songStartAudioSec

`songStartAudioSec` is the second value inside the completed WAV that corresponds to Project timeline 0:00.

Example:

```text
WAV 2.00 seconds = Project timeline 0:00
```

The completed WAV is the Reference Performance Anchor, but the WAV file may contain count-in, leading silence, or export padding. `songStartAudioSec` captures where the song actually starts inside the WAV.

## SyncAnchor

`SyncAnchor` is an arbitrary reference point on the video side. It can be created manually or proposed by analysis.

Examples:

- Song start.
- Song end.
- Chorus start.
- Sync click.
- Manual marker.

A `SyncAnchor` maps a `rawSec` value in the video to a `timelineSec` value on the project timeline.

## MasterAudioAnchor

`MasterAudioAnchor` is an arbitrary reference point on the completed WAV side.

Examples:

- Song start inside the WAV.
- Sync click inside the WAV.
- Chorus start inside the WAV.

A `MasterAudioAnchor` maps an `audioSec` value in the completed WAV to a `timelineSec` value on the project timeline.

## Separate timeline concepts

Do not mix these concepts:

- Recording start.
- Song start.
- First audible sound for that part.
- Selected trim start.

For example, if a vocal enters 40 seconds into the song, `firstSoundRawSec` may be 40 seconds later than `songStartRawSec`. The vocal video can still be aligned from the song start.

## Non-destructive editing

TakeLayer keeps raw videos intact by default. It stores usage decisions as metadata such as `selectedRawStartSec`, `selectedRawEndSec`, anchors, offsets, and layout choices.

Raw media should not be deleted or destructively trimmed automatically. Deletion requires explicit user confirmation.

## Silence handling

TakeLayer must not remove silence inside the song just because the track is quiet. Breaks, rests, part waiting, and dramatic pauses are musical context. Future automatic trim should be based on song-length window search rather than naive silence cutting.

## Future architecture: TakeLayer Core + AI Director

The future AI Music Video Director extends TakeLayer but must not replace the deterministic synchronization core.

```text
┌─────────────────────────────────────────┐
│ Product / Review UI                     │
│ upload → proposals → tweak → approve    │
├─────────────────────────────────────────┤
│ AI Director                             │
│ highlight / lyrics / crop / style /     │
│ title / effects / shot decisions        │
├─────────────────────────────────────────┤
│ Song Intelligence                       │
│ Song Resolver / Song Memory / Metadata  │
│ Preference Memory / Feedback Learning   │
├─────────────────────────────────────────┤
│ Editing Plan + Quality Gate             │
│ deterministic editable representation  │
├─────────────────────────────────────────┤
│ TakeLayer Core                          │
│ timeline / anchors / sync / trim /      │
│ layout / output-audio decisions         │
├─────────────────────────────────────────┤
│ Media Processing                        │
│ AVFoundation / Accelerate / vDSP        │
└─────────────────────────────────────────┘
```

### Dependency rule

The dependency direction is downward only.

AI Director may consume TakeLayer Core analysis and timeline data, but the correctness of sync, anchors, project time, and non-destructive media decisions must never depend on a generative AI response.

### AI responsibility vs renderer responsibility

AI decides intent:

- which short range to propose
- where the hook is
- which lyric line matters
- how restrained or active the edit should be
- which crop / zoom / title / effect strategy fits the music

The renderer executes explicit values:

- timestamps
- coordinates
- crop rectangles
- scale values
- text placement
- effect parameters
- audio levels

The bridge between them is an `EditingPlan`, making edits reproducible, adjustable, comparable, and learnable.

### Memory boundary

Song Memory and Preference Memory are advisory layers.

They may suggest known song information or editing preferences, but must not silently overwrite user-confirmed metadata, anchors, lyrics, or final editing decisions.

See:

- `docs/ai-director-vision.md`
- `docs/song-memory-feedback.md`
- `docs/ai-director-data-model.md`
