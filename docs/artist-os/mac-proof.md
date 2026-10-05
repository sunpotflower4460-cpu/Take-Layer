# Mac proof log (Take-Layer side)

Canonical log: Artist-OS `docs/audit/TAKE_LAYER_MAC_PROOF.md`. Summary of what this repo has executed:

| Item | Level |
|---|---|
| `swift build --target TakeLayerCore` | `CI_MACOS` (workflow `macOS Core`) |
| 22 existing XCTests on macOS (`tools/swiftpm-short`, `swift test`) | `CI_MACOS` |
| `tools/build-render-cli.sh` + `take-layer-render self-test` → MP4 passing Render Quality Validation v1 | `CI_MACOS` |
| `RENDER_EDIT_PLAN` from Artist OS's Runner (real handler, real renderer) | `CI_MACOS` (throwaway branch `ci/artist-os-render-e2e`) |
| anything on the user's own Mac | **not yet run** (`REAL_MAC_VERIFIED` = none) |

Run it yourself on a Mac:

```bash
swift --version
swift build --target TakeLayerCore
(cd tools/swiftpm-short && swift test)
bash tools/build-render-cli.sh /tmp/take-layer-render
/tmp/take-layer-render self-test --workdir /tmp/tl-selftest --result /tmp/tl-selftest/result.json && cat /tmp/tl-selftest/result.json
```
