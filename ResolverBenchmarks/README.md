# Resolver Benchmarks

This directory documents the local, private benchmark workflow for Phase 7 Song Resolver calibration.

## Privacy rule

Do not commit benchmark WAV files or private manifests.

`ResolverBenchmarks/Private/` is gitignored. Keep copyrighted, unreleased, personal, or otherwise private audio there only.

The committed `manifest.example.json` contains placeholder paths only.

## Recommended local layout

```text
ResolverBenchmarks/
├── manifest.example.json
└── Private/                  # gitignored
    ├── manifest.json
    ├── songs/
    │   ├── song-a/
    │   │   ├── studio.wav
    │   │   └── acoustic.wav
    │   └── song-b/
    │       └── studio.wav
    ├── derived-dataset.json  # generated, gitignored with Private/
    └── report.json           # generated, gitignored with Private/
```

## Run

Copy `manifest.example.json` to `ResolverBenchmarks/Private/manifest.json`, edit its cases, place the referenced WAV files under the same private root, then run:

```bash
bash tools/run-resolver-calibration.sh \
  --manifest ResolverBenchmarks/Private/manifest.json
```

Optional diagnostic threshold sweep:

```bash
bash tools/run-resolver-calibration.sh \
  --manifest ResolverBenchmarks/Private/manifest.json \
  --thresholds 0.50,0.60,0.70,0.80,0.90,0.95
```

Before any audio evidence extraction begins, the runner preflights the full manifest: effective case IDs, path confinement, file existence, and WAV extension are validated for every case. A later bad path therefore fails before earlier valid cases spend time on signal analysis.

Within one dataset build, each resolved WAV URL is analyzed at most once. If the same studio/master/live file appears in many labeled pairs, its `AudioEvidenceVector` is cached in memory and reused for every case in that run.

The command compiles a small macOS developer CLI from the same Resolver / Evidence code used by the app, then writes:

- `derived-dataset.json` — derived `AudioEvidenceVector` values only,
- `report.json` — labeled confidence distributions, evidence components, and threshold metrics.

Raw WAV bytes are never serialized into either output. The in-memory evidence cache is per run only; it does not create a persistent audio cache outside the private benchmark workflow.

## Manifest labels

- `sameArrangement` — same arrangement / recording family.
- `sameSongDifferentArrangement` — same musical work but a different arrangement, live version, acoustic version, key, or structure.
- `differentSong` — known negative pair.

Use both easy and adversarial negatives. For example, include different songs by the same artist, songs with similar keys, and songs with similar chord movement.

## Safety boundaries

The runner is measurement-only. It does not:

- change production Resolver thresholds,
- change Resolver weights,
- attach Song Memory automatically,
- modify TimelineMapper,
- modify synchronization fields,
- upload audio or datasets.

Review the report before proposing any scoring change. A synthetic or tiny private corpus is not sufficient evidence for automatic identity adoption.
