# Mac proof log (Take-Layer side)

Canonical log: Artist-OS `docs/audit/TAKE_LAYER_MAC_PROOF.md`. Summary of what this repo has executed:

| Item | Level |
|---|---|
| `swift build --target TakeLayerCore` | `CI_MACOS` and `REAL_MAC_VERIFIED` (user's Mac, 2026-10-05) |
| 22 existing XCTests (`tools/swiftpm-short`, `swift test`) | `CI_MACOS` and `REAL_MAC_VERIFIED` (22 executed, 0 failures) |
| renderer self-test → MP4 passing Render Quality Validation v1 **and the final-frame guards** (`title_visible_*`, `lyric_visible_during_cue`, `lyric_not_visible_before/after_cue`) | `CI_MACOS` and `REAL_MAC_VERIFIED` |
| `RENDER_EDIT_PLAN` pipeline / text overlay / timed cues (Runner + queue + real renderer) | `REAL_MAC_VERIFIED` |
| `RENDER_EDIT_PLAN` crop on a generated pattern | `REAL_MAC_VERIFIED` (human-attested, no automated guard) |
| `RENDER_EDIT_PLAN` with a real performance video + completed WAV (sync, real-person crop, real decode) | **`NOT_VERIFIED`** (so `RENDER_EDIT_PLAN` itself is `NOT_VERIFIED`) |
| `RESOLVER_CALIBRATION` | `REAL_MAC_PLUMBING_VERIFIED` (synthetic corpus; quality `NOT_MEASURED`) |

Bug found by this verification: headless `CATextLayer` text was never displayed (title and lyrics missing while all container checks passed). Fixed with `displayIfNeeded()`; guarded on final MP4 frames.

Run it yourself on a Mac:

```bash
swift --version
swift build --target TakeLayerCore
(cd tools/swiftpm-short && swift test)
bash tools/build-render-cli.sh /tmp/take-layer-render
/tmp/take-layer-render self-test --workdir /tmp/tl-selftest --result /tmp/tl-selftest/result.json && cat /tmp/tl-selftest/result.json
```
