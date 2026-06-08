# TakeLayer Data Model

This is a TypeScript-style conceptual model. Phase 0 does not implement SwiftData models yet.

## Project

A song/video assembly project. It owns the timeline, parts, takes, master audio, layouts, and storage policy.

```ts
type Project = {
  id: string
  title: string
  timeline: ProjectTimeline
  parts: Part[]
  takes: Take[]
  masterAudio?: MasterAudio
  layouts: LayoutPreset[]
  storagePolicy: StoragePolicy
  createdAt: string
  updatedAt: string
  schemaVersion: number
}
```

## ProjectTimeline

The shared song timeline. `zeroPointLabel` fixes Project timeline 0:00 as the song start.

```ts
type ProjectTimeline = {
  durationSec: number
  bpm?: number
  timeSignature?: { numerator: number; denominator: number }
  countInBars?: number
  zeroPointLabel: 'song_start'
  sections: Section[]
  tempoMap?: TempoSegment[]
}
```

## Section

A named musical region such as intro, verse, chorus, or bridge.

```ts
type Section = {
  id: string
  name: string
  startBeat: number
  endBeat: number
}
```

## MasterAudio

The DAW-exported completed WAV. `songStartAudioSec` is the point inside this WAV that maps to Project timeline 0:00.

```ts
type MasterAudio = {
  id: string
  projectId: string
  fileUri: string
  durationSec: number
  sampleRate: number
  bitDepth?: number
  songStartAudioSec: number
  anchors: MasterAudioAnchor[]
  importedAt: Date
}
```

## MasterAudioAnchor

A reference marker inside the completed WAV. It may represent song start, sync click, chorus start, or another useful point.

```ts
type MasterAudioAnchor = {
  id: string
  masterAudioId: string
  audioSec: number
  timelineSec: number
  kind: 'manual' | 'sync_cue' | 'detected_silence' | 'imported_marker'
  confidence: number
}
```

## Part

A musical part such as vocal, guitar, bass, drums, keys, or other.

```ts
type Part = {
  id: string
  projectId: string
  name: string
  type: 'drums' | 'bass' | 'guitar' | 'vocal' | 'chorus' | 'keys' | 'other'
  color?: string
  order: number
}
```

## Take

A raw performance video associated with a part. `songStartRawSec` maps the raw video to Project timeline 0:00. `firstSoundRawSec` records when this part first becomes audible, which can be later than the song start. `selectedRawStartSec` and `selectedRawEndSec` define the non-destructive range actually used from the raw video.

```ts
type Take = {
  id: string
  projectId: string
  partId: string
  media: MediaInfo
  songStartRawSec?: number
  selectedRawStartSec?: number
  selectedRawEndSec?: number
  firstSoundRawSec?: number
  anchors: SyncAnchor[]
  recordedAt: Date
  offsetMs: number
  driftPpm?: number
  userRating?: number
  userNote?: string
  analysis?: AnalysisResult
  confidence: number
  status: 'raw' | 'analyzed' | 'selected' | 'rejected'
  userAdjusted: boolean
}
```

## SyncAnchor

A video-side marker mapping `rawSec` to `timelineSec`.

```ts
type SyncAnchor = {
  id: string
  takeId: string
  rawSec: number
  timelineSec: number
  kind: 'manual' | 'audio_match' | 'sync_cue' | 'app_count_in' | 'imported_marker'
  confidence: number
  locked: boolean
}
```

## MediaInfo

Basic metadata for a video or audio asset. It supports warnings for HDR, 4K, missing audio, unexpected FPS, or large files.

```ts
type MediaInfo = {
  uri: string
  durationSec: number
  width: number
  height: number
  fps?: number
  hasAudio: boolean
  audioSampleRate?: number
  orientation?: 'portrait' | 'landscape'
  codec?: string
  colorSpace?: 'sdr' | 'hdr' | 'unknown'
  fileSizeBytes?: number
}
```

## AnalysisResult

Stores analysis output as suggestions and warnings. Analysis must not automatically decide the final edit.

```ts
type AnalysisResult = {
  takeId: string
  candidates: TakeCandidate[]
  waveformAssetId?: string
  syncResultIds: string[]
  warnings: string[]
}
```

## TakeCandidate

A suggested usable window in a raw take. It explains why the candidate may be useful.

```ts
type TakeCandidate = {
  id: string
  takeId: string
  startSec: number
  endSec: number
  durationSec: number
  confidence: number
  reasons: {
    durationMatch?: number
    audioActivity?: number
    syncConfidence?: number
    startNaturalness?: number
    endNaturalness?: number
  }
  warning?: string
}
```

## SyncResult

A sync-assistance result. `driftMsAtEnd` is the estimated end-position error after aligning the start, and `driftPpm` is the rate difference estimate. MVP may warn about drift but does not automatically correct it.

```ts
type SyncResult = {
  id: string
  takeId: string
  masterAudioId: string
  method: 'manual' | 'sync_click' | 'audio_match' | 'gcc_phat' | 'imported_marker'
  offsetMs: number
  confidence: number
  driftMsAtEnd?: number
  driftPpm?: number
  needsManualReview: boolean
  createdAt: Date
}
```

## OutputAudioConfig

Describes the output audio mix. `cameraAudioVolume` is normally `0` in the MVP because the completed WAV is the main output audio, but camera audio is retained for future momentary mix features.

```ts
type OutputAudioConfig = {
  primary: 'master_audio' | 'camera_audio'
  masterAudioVolume: number
  cameraAudioVolume: number
  cameraAudioMoments?: { startSec: number; endSec: number; volume: number }[]
}
```

## LayoutPreset

A named output layout such as single-screen or grid. Phase 0.5A validates single-screen first.

```ts
type LayoutPreset = {
  id: string
  projectId: string
  name: string
  type: 'single' | 'grid_2x1' | 'grid_2x2' | 'vertical_3' | 'custom'
  aspectRatio: '16:9' | '9:16' | '1:1'
  resolution: '720p' | '1080p' | '4K'
  placements: PartPlacement[]
}
```

## PartPlacement

Places a take or part inside a layout frame.

```ts
type PartPlacement = {
  partId?: string
  takeId: string
  position: { x: number; y: number }
  size: { width: number; height: number }
  cropRect?: { x: number; y: number; width: number; height: number }
}
```

## StoragePolicy

Controls storage-related defaults. `keepOriginalAfterTrim` must default to preserving raw videos after trims because TakeLayer is non-destructive by default.

```ts
type StoragePolicy = {
  defaultResolution: '720p' | '1080p'
  defaultFps: 30
  keepOriginalAfterTrim: boolean
  autoSuggestDeleteRejectedTakes: boolean
  warnWhenFreeSpaceBelowGB: number
}
```
