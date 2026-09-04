# Phase 7: Real Corpus Measurement

## Status

**Next operational gate after Phase 7 Consistency Stabilization. Currently paused.**

The Private Corpus Runner is already merged on `main`, but real-corpus measurement is intentionally paused while PR #15 repairs cross-cutting correctness and repository consistency. Resume this gate only after consistency stabilization is merged and the post-merge `main` CI run is green.

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

## Additional resume prerequisite

Before collecting evidence that will influence the next Resolver gate:

- Phase 7 Consistency Stabilization must be merged,
- CLI compilation must be green,
- iOS build must be green,
- full XCTest must be green,
- post-merge `main` CI must be green.

See `phase-7-consistency-stabilization.md`.

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
same Arrangement                  >= 10 cases
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

The runner generates derived evidence and a calibration report while raw WAV files stay local.

## What to inspect

Do not evaluate the Resolver from one headline accuracy number.

Review:

- minimum positive confidence,
- maximum negative confidence,
- observed confidence gap,
- per-threshold confusion matrix,
- precision,
- recall,
- specificity,
- F1,
- balanced accuracy,
- individual false-positive cases,
- individual false-negative cases,
- duration / energy / transient / tonal evidence,
- tonal transposition,
- tonal alignment coverage,
- tonal warp fraction.

## Failure classification

For every meaningful failure, classify the likely missing evidence before changing production logic.

Examples:

### Harmony-similar different songs collide

Possible next gate:

- melody contour / vocal melody evidence.

### Same song with strong arrangement changes scores too low

Possible next gate:

- stronger section-aware structure representation,
- selective melody evidence,
- improved landmark evidence.

### Same master with intro/outro silence differences scores too low

Possible next gate:

- revisit evidence normalization or alignment boundaries before adding a new model.

### Different songs by the same artist collide

Possible next gate:

- melody contour,
- stronger audio landmarks,
- later permitted lyrics identity evidence if justified.

The measured failure class should choose the next technical gate, not the reverse.

## Calibration guardrails

- Do not choose a production threshold from a tiny corpus.
- Do not optimize weights against one user's easiest examples.
- Do not hide false positives behind an aggregate score.
- Do not turn report output into automatic production configuration.
- Do not auto-link Song Memory from benchmark confidence.
- Do not change TimelineMapper or synchronization fields from calibration work.
- Do not commit private WAVs or private benchmark datasets.
- Keep all candidate identity decisions inspectable and user-confirmed.

## Exit criteria

This gate is complete when:

1. the private corpus is large/diverse enough to expose meaningful overlap rather than only easy separation;
2. per-case failures have been reviewed;
3. repeated failure classes are documented;
4. the next Resolver technical gate can be justified from those observed failures;
5. any proposed production threshold/weight change is supported by evidence rather than convenience.

If the current Resolver already separates the real corpus well, the correct next action may be **not** to add another Resolver algorithm and instead move to the next product-value gate.
