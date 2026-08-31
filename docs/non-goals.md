# Non-goals

The initial implementation does not do the following:

- DAW API integration.
- DAW operation.
- Sound source production.
- Mixing / mastering.
- Full-featured video editing.
- 4K export.
- HDR editing.
- AI automatic crop.
- Lyric captions.
- Automatic social posting.
- Cloud sync.
- Android support.
- Mac Companion.
- Fully automatic adoption.
- Automatic deletion of silence inside the song.
- FFmpegKit as a core dependency.

These are non-goals so TakeLayer can stay focused: completed-WAV-based alignment and safe performance-video export.

## Future vision clarification

`AI automatic crop`, `Lyric captions`, Song Memory, AI Director, and preference learning are **non-goals for the current core implementation**, not permanent product prohibitions.

They may be introduced only when the corresponding future phase in `docs/phases.md` is explicitly activated and only if they preserve TakeLayer Core guarantees.

Even in future AI phases:

- synchronization must remain deterministic and inspectable;
- user-confirmed information must remain authoritative;
- AI output must be presented as proposals rather than irreversible truth;
- raw media remains non-destructive by default;
- low-confidence decisions return to user confirmation.

See `docs/ai-director-vision.md` for the long-term direction.
