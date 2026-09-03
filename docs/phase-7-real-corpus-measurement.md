# Phase 7: Real Corpus Measurement

## Status

Active operational gate after the merged Private Corpus Runner.

This gate is intentionally **data collection and measurement**, not a new Resolver algorithm implementation.

## Goal

Measure the current Song Resolver against a meaningful set of real, human-labeled audio relationships before changing confidence thresholds, weights, or adding another evidence source.

The question for this gate is not "How can Resolver become more complex?" It is:

> Where does the current Resolver actually fail on real music?

## Prerequisites merged on `main`

- human-confirmed Song Memory,
- Resolver Evidence Foundation,
- Tonal Evidence Foundation,
- Elastic Tonal Alignment,
- Resolver Calibration Harness,
- Private Corpus Runner.

## Private corpus location

Keep raw benchmark audio under:

```text
ResolverBenchmarks/Private/
```

That directory is gitignored. Do not commit or upload private, unreleased, or copyrighted WAV files as part of this gate.

Use `ResolverBenchmarks/manifest.example.json` as the starting point for a local `manifest.json`.

## Minimum useful corpus

A first report should include multiple examples from each category below rather than one convenient pair per category.

### Positive: same Arrangement

Examples:

- same master with level change,
- same master with different limiter / mastering pass,
- re-export with leading/trailing silence differences,
- lossless re-render of the same arrangement.

### Positive: same Song / different Arrangement

Examples:

- studio vs acoustic solo,
- studio vs duo,
- studio vs live,
- full band vs stripped arrangement,
- different key,
- different tuning reference,
- modest tempo change,
- longer intro / outro,
- shortened verse / repeated chorus,
- alternate instrumental balance.

### Negative: different Song

Include both easy and adversarial negatives:

- unrelated song,
- different song by the same artist,
- similar instrumentation,
- similar BPM,
- same or nearby key,
- similar common chord progression,
- similar duration,
- two songs with similar intros.

The adversarial negatives are especially important because easy negatives can make a weak Resolver appear unrealistically accurate.

## Recommended first target

Before discussing production thresholds, aim for at least:

```text
same Arrangement                 >= 10 cases
same Song / different Arrangement >= 20 cases
different Song                    >= 30 cases
```

This is a practical first checkpoint, not a statistical guarantee. More diversity is more important than simply increasing pair count.

## Run

```bash
bash tools/run-resolver-calibration.sh \
  --manifest ResolverBenchmarks/Private/manifest.json \
  --thresholds 0.50,0.60,0.65,0.70,0.75,0.80,0.85,0.90,0.95
```

The runner produces derived evidence and an inspectable report while leaving production Resolver behavior unchanged.

## Review order

When a report is produced, review in this order:

1. `minimumPositiveConfidence`
2. `maximumNegativeConfidence`
3. `confidenceGap`
4. false positives at candidate thresholds
5. false negatives at candidate thresholds
6. per-case duration / energy / transient / tonal evidence
7. estimated transposition
8. tonal structure coverage
9. elastic warp fraction

Do not choose a threshold solely because one F1 value is numerically highest on a small corpus.

## Failure classification

Every important false positive / false negative should be assigned a likely failure class before adding another algorithm.

Suggested classes:

- `exact_signature_weakness`
- `similar_harmony_collision`
- `arrangement_structure_change`
- `tempo_or_section_change`
- `energy_transient_mismatch`
- `melody_needed`
- `landmark_fingerprint_needed`
- `lyrics_or_vocal_identity_may_help`
- `label_or_source_quality_problem`
- `unknown`

The classification is a human review note at this gate. It is not an automatic model diagnosis.

## Decision rules after measurement

Only choose a new technical gate after inspecting repeated real failures.

### If harmony-similar different songs collide

Consider Melody Contour Evidence before simply increasing tonal weight.

### If the same recording / mix family is not stable enough

Consider stronger audio landmark fingerprinting.

### If live / acoustic structures still miss despite good tonal content

Inspect Elastic Alignment coverage / warp and consider section-aware evidence.

### If components separate well but total confidence is poorly calibrated

Consider a separately reviewed Resolver weight / threshold calibration gate.

### If the current Resolver already separates the corpus well

Do not add complexity merely because another algorithm exists. Move toward song sections / highlights or the next product-facing gate.

## Safety boundaries

This gate must not:

- automatically alter production thresholds,
- automatically alter Resolver weights,
- auto-link Song Memory,
- treat benchmark labels as synchronization truth,
- modify TimelineMapper,
- upload private WAVs,
- commit private benchmark media,
- introduce AI Director editing decisions.

## Completion criterion

This gate is complete when:

- a meaningful private corpus has been collected,
- a report has been generated using the merged runner,
- notable false positives and false negatives have been reviewed,
- failure classes are documented,
- the next technical gate is chosen from observed evidence rather than speculation.

Until real audio exists, further Resolver-complexity work should remain paused.
