# TakeLayer Glossary

## Project timeline

The shared musical timeline for a project. Every video take and the completed WAV are placed on this timeline.

## Project timeline 0:00

The song start. It is the common origin used to align all media.

## songStartRawSec

The second value inside a raw video that corresponds to Project timeline 0:00.

## songStartAudioSec

The second value inside the completed WAV that corresponds to Project timeline 0:00.

## SyncAnchor

A video-side reference point that maps a raw video position to a project timeline position.

## MasterAudioAnchor

A completed-WAV-side reference point that maps an audio position to a project timeline position.

## selectedRawStartSec

The second value inside a raw video where the actually used range begins. This is not necessarily the song start.

## selectedRawEndSec

The second value inside a raw video where the actually used range ends.

## firstSoundRawSec

The first point where the part actually starts making sound in the raw video. For parts that enter later, this differs from `songStartRawSec`.

## Reference Performance Anchor

The completed WAV exported from the DAW. It is the final audio source and the reference performance for video alignment.

## 曲尺ウィンドウ探索

A future automatic candidate strategy that searches for a natural window matching the song length. It is not silence cutting.

## 非破壊編集

An editing approach where raw media remains intact and usage decisions are stored as metadata.

## Import-first Export PoC

The first proof of concept after Phase 0. It imports existing videos and a completed WAV, sets both song-start anchors, and validates single-screen export.

## Zenモード

A minimal recording UI mode that avoids distracting the performer during recording.

## Strict Sync

A future sync mode that prioritizes exact alignment.

## Natural Sync

A future sync mode that preserves human performance feel while still making the result usable.
