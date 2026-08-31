# Future AI Director Data Model

This document extends the existing TakeLayer conceptual data model for future AI Director phases. It is design-only and does not change the current Phase 0 implementation scope.

## SongIdentity

```ts
type SongIdentity = {
  id: string
  canonicalTitle: string
  artistName?: string
  aliases: string[]
  isOriginal: boolean
  externalIds?: {
    isrc?: string
    musicBrainzRecordingId?: string
    appleMusicSongId?: string
  }
  confidence: number
  userConfirmed: boolean
  createdAt: Date
  updatedAt: Date
}
```

## SongProfile

```ts
type SongProfile = {
  id: string
  songId: string
  bpm?: number
  key?: string
  tuningHz?: number
  themeTags: string[]
  visualMoodTags: string[]
  formalLyricsId?: string
  sections: SongSectionMemory[]
  preferredHookRegions: TimeRange[]
  preferredSubtitlePresetId?: string
  metadataSourceRefs: MetadataSourceRef[]
  createdAt: Date
  updatedAt: Date
}
```

## ArrangementProfile

A Song may have multiple arrangements or recording families.

```ts
type ArrangementProfile = {
  id: string
  songId: string
  name: string
  type: 'studio' | 'acoustic_solo' | 'live' | 'duo' | 'band' | 'alternate'
  masterAudioId?: string
  fingerprintIds: string[]
  expectedDurationSec?: number
  tempoHint?: number
  keyHint?: string
  createdAt: Date
}
```

## SongMatchResult

```ts
type SongMatchResult = {
  inputAssetId: string
  candidates: SongMatchCandidate[]
  resolvedSongId?: string
  resolvedArrangementId?: string
  needsUserConfirmation: boolean
}

type SongMatchCandidate = {
  songId: string
  arrangementId?: string
  confidence: number
  evidence: {
    fingerprint?: number
    chroma?: number
    melody?: number
    lyrics?: number
    duration?: number
    metadata?: number
  }
}
```

## FormalLyrics

```ts
type FormalLyrics = {
  id: string
  songId: string
  text: string
  source: 'user_confirmed' | 'licensed_provider' | 'transcription_estimate'
  userConfirmed: boolean
  language?: string
  version: number
}
```

## LyricsAlignment

```ts
type LyricsAlignment = {
  id: string
  songId: string
  arrangementId?: string
  assetId: string
  lines: LyricsLineTiming[]
  overallConfidence: number
}

type LyricsLineTiming = {
  lineIndex: number
  startSec: number
  endSec: number
  confidence: number
  words?: { text: string; startSec: number; endSec: number; confidence: number }[]
}
```

## EditProposal

```ts
type EditProposal = {
  id: string
  projectId: string
  songId?: string
  arrangementId?: string
  style: 'natural' | 'cinematic' | 'lyric_focus' | 'social_hook' | 'minimal' | 'custom'
  editingPlan: EditingPlan
  rationale: string[]
  qualityGate: QualityGateResult
  preferenceSources: PreferenceApplication[]
  createdAt: Date
}
```

## EditingPlan

```ts
type EditingPlan = {
  sourceTakeIds: string[]
  trim: TimeRange
  targetAspectRatio: '9:16' | '16:9' | '1:1'
  cropEvents: CropEvent[]
  titleEvents: TextEvent[]
  lyricEvents: LyricEvent[]
  cameraMoveEvents: CameraMoveEvent[]
  transitionEvents: TransitionEvent[]
  colorTreatment?: ColorTreatment
  effectEvents: EffectEvent[]
  audioConfig: OutputAudioConfig
}
```

The actual schema for event objects should remain deterministic and renderable. The AI Director should produce this plan rather than directly mutating media.

## EditDecision

```ts
type EditDecision = {
  id: string
  proposalId: string
  decision: 'approved' | 'rejected' | 'edited_then_approved' | 'abandoned'
  explicitRating?: number
  note?: string
  finalEditingPlanId?: string
  createdAt: Date
}
```

## EditDelta

Stores meaningful user changes between the AI proposal and the approved final plan.

```ts
type EditDelta = {
  id: string
  proposalId: string
  path: string
  before: unknown
  after: unknown
  semanticTag?: string
  magnitude?: number
}
```

Examples:

```text
lyrics.fontSize: 54 -> 42
camera.zoomScale: 1.10 -> 1.04
trim.startSec: 42.0 -> 38.4
color.saturation: 0.15 -> 0.03
```

## PreferenceSignal

```ts
type PreferenceSignal = {
  id: string
  source: 'approval' | 'rejection' | 'edit_delta' | 'explicit_feedback'
  polarity: number
  featureKey: string
  featureValue: unknown
  scope: PreferenceScope
  context: EditContext
  weight: number
  createdAt: Date
}
```

## LearnedEditingPreference

```ts
type LearnedEditingPreference = {
  id: string
  ruleKey: string
  preferredValue: unknown
  scope: PreferenceScope
  contextFilter?: Partial<EditContext>
  evidenceCount: number
  positiveWeight: number
  negativeWeight: number
  confidence: number
  lastObservedAt: Date
}
```

## PreferenceScope

```ts
type PreferenceScope =
  | { type: 'song'; songId: string }
  | { type: 'arrangement'; arrangementId: string }
  | { type: 'artist'; artistId: string }
  | { type: 'user' }
```

## EditContext

```ts
type EditContext = {
  songId?: string
  arrangementId?: string
  performanceType?: string
  platform?: 'tiktok' | 'instagram_reels' | 'youtube_shorts' | 'x' | 'other'
  aspectRatio?: string
  proposalStyle?: string
  sectionType?: string
  energyBand?: 'low' | 'medium' | 'high'
  cameraSetup?: 'single_static' | 'single_handheld' | 'multi_camera' | 'unknown'
}
```

## MetadataCandidate

External metadata must remain a candidate until trusted or user-confirmed.

```ts
type MetadataCandidate = {
  id: string
  provider: string
  title?: string
  artist?: string
  album?: string
  releaseDate?: string
  isrc?: string
  artworkRef?: string
  confidence: number
  fetchedAt: Date
}
```

## QualityGateResult

```ts
type QualityGateResult = {
  passed: boolean
  checks: QualityCheck[]
}

type QualityCheck = {
  key: string
  severity: 'info' | 'warning' | 'error'
  passed: boolean
  message?: string
}
```

## Design rule

These models extend, rather than replace, the current core entities such as `Project`, `Take`, `MasterAudio`, `SyncAnchor`, `SyncResult`, and `OutputAudioConfig`.

The dependency direction should remain:

```text
AI Director models
        ↓
TakeLayer Core timeline + sync models
        ↓
AVFoundation / deterministic media processing
```

Core synchronization must never depend on a generative AI model to remain correct.
