# Codex Instructions for TakeLayer

## Repository baseline

`main` already contains the merged Phase 1 (MVP-α) integrated flow, building on Phase 0.5A and 0.5B. Preserve that behavior unless a task explicitly changes it.

Do not infer that Phase 2 or later is active. The requested task scope is authoritative.

## Mandatory rules

- Do not implement multiple phases at once.
- Do not add features outside the specified phase.
- Do not break existing code.
- Explain the reason before deleting files.
- Do not make FFmpegKit a core dependency.
- Do not add DAW integration without explicit instruction.
- Do not implement automatic adoption without explicit instruction.
- Do not automatically delete raw videos.
- Do not weaken or replace the `songStartRawSec` / `songStartAudioSec` concepts.
- Do not delete silence inside the song automatically.
- Always report what changed and what remains unimplemented after implementation.
- Generative AI must never be the source of truth for synchronization.
- User-confirmed song metadata and lyrics must not be silently overwritten by AI or external metadata.

## Historical Phase 0 rules

Phase 0 was for design fixation and repository scaffolding only. Those restrictions describe the historical Phase 0 scope; they are not a statement that the repository is still in Phase 0.

## Design reminders

- Project timeline 0:00 means song start.
- Completed WAV is the Reference Performance Anchor.
- `songStartRawSec` maps raw video time to Project timeline 0:00.
- `songStartAudioSec` maps completed WAV time to Project timeline 0:00.
- `firstSoundRawSec` is separate from song start.
- `selectedRawStartSec` / `selectedRawEndSec` are usage ranges, not necessarily song-start markers.
- TakeLayer suggests candidates; the user confirms.
- Raw videos remain intact unless the user confirms deletion.

## Future AI Director architecture

The AI Director documents are future design references. Do not implement Song Memory, Song Resolver, external metadata lookup, lyric captions, AI crop, automatic short-video generation, preference learning, or edit-delta learning until the corresponding future phase is explicitly activated.

When a future AI phase is explicitly activated, read these before coding:

- `docs/ai-director-vision.md`
- `docs/song-memory-feedback.md`
- `docs/ai-director-data-model.md`
- `docs/phases.md`
- `docs/architecture.md`

The architecture rule is:

```text
AI Director
   ↓
Editing Plan / Quality Gate
   ↓
TakeLayer Core timeline + sync
   ↓
Deterministic media processing
```

AI should decide editing intent; renderable timestamps, crops, text placement, camera moves, and effect parameters should be represented explicitly so they can be inspected, adjusted, compared, undone, and learned from.

## Final report checklist

Every implementation report should include:

- Implemented content.
- Changed files.
- Checks performed.
- Unimplemented items.
- Notes / cautions.
- Recommended next step.
