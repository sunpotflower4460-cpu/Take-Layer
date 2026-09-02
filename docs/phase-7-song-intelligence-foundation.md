# Phase 7: Song Intelligence Foundation

## Status

Active foundation branch: `phase-7-song-intelligence-foundation`.

This phase begins the future AI Director track without introducing generative editing decisions or automatic identity adoption.

## Goal

Give TakeLayer a safe, inspectable memory of the musical work itself so later Song Resolver, lyric alignment, and AI Short Director features can reuse user-confirmed information.

The first implementation intentionally starts with **human-confirmed Song Memory**, not automatic recognition.

## Implemented in this foundation

- `SongIdentity`
  - canonical title
  - artist / unit
  - aliases
  - original / cover flag
  - external ID slots
  - confidence
  - explicit `userConfirmed`
- `SongProfile`
  - canonical BPM
  - canonical key
  - tuning Hz
  - formal lyrics reference
- `ArrangementProfile`
  - Song / Arrangement separation
  - multiple Arrangements per Song
  - studio / acoustic solo / live / duo / band / alternate types
  - Arrangement-specific tempo and key hints so alternate versions do not overwrite the Song Profile
- `FormalLyrics`
  - user-confirmed source
  - language
  - versioning
  - provenance-preserving behavior so a future provider record is not overwritten when the user confirms different lyrics
- `ProjectSongMemoryLink`
  - connects an existing TakeLayer Project to a Song and Arrangement without changing timeline math
  - replacing an existing master WAV detaches the old link so a potentially different song is never silently inherited
- Local `SongMemoryStore`
  - JSON persistence under the app Documents directory
- Song Memory editor in the MVP flow
  - create a new remembered song
  - select an existing Song Memory entry
  - select, update, or add an Arrangement for the same Song
  - update confirmed metadata
  - add or replace user-confirmed formal lyrics
  - detach a Project from Song Memory without deleting the memory
- Regression tests for:
  - identity/profile/arrangement creation
  - stable IDs on update
  - multiple Arrangements under one Song
  - separate Song and Arrangement tempo/key values
  - lyric versioning and provenance
  - alias normalization
  - invalid numeric hints
  - Song Memory Codable round-trip
  - legacy Project JSON decoding without `songMemoryLink`

## Authority and precedence

TakeLayer now has two separate authorities:

```text
Synchronization truth
= TimelineMapper + explicit song-start anchors + completed WAV

User-confirmed song-information truth
= Song Memory
```

Song Memory must never modify `songStartRawSec`, `songStartAudioSec`, `offsetMs`, trim ranges, or rendering synchronization.

Information precedence remains:

```text
1. User-confirmed value
2. Previously confirmed Song Memory
3. Trusted imported metadata candidate
4. Analysis estimate
5. Unknown
```

No future provider or AI estimate may silently overwrite a user-confirmed title, artist, arrangement, or formal lyrics.

## Explicitly not implemented yet

- Audio fingerprint generation.
- Chroma / melody / lyric-based same-song matching.
- Automatic Song Resolver candidate ranking.
- External MusicBrainz / Apple Music metadata lookup.
- Automatic lyric transcription.
- Known-lyrics forced alignment.
- Song section analysis.
- Highlight / hook candidate analysis.
- AI Short Director proposals.
- Preference learning.
- Multi-part AI Director.

## Next gate

The next safe sub-phase is **Song Resolver Evidence Foundation**:

1. derive deterministic evidence from imported master audio,
2. store fingerprints per Arrangement,
3. compare against known Arrangement profiles,
4. return confidence-scored candidates,
5. require user confirmation before attaching a match.

The resolver must propose; it must not silently adopt low-confidence identity.
