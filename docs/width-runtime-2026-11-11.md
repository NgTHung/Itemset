# Transaction width and Eclat runtime, 2026-11-11

Real transaction databases differ in length, density, and output volume at once, so a runtime difference between Chess and Retail cannot be pinned on any one of them. This record varies only the transaction width on synthetic databases and measures baseline Eclat, optimized Eclat, and SPMF Eclat on each. Two protocols separate the width from the output volume it causes.

## Generator

Each database has 10,000 transactions over 100 items. Every transaction is a uniformly random subset of exactly `w` items, for `w` of 5, 10, 15, 20, 25, 30, 35, and 40, drawn independently by a partial Fisher-Yates shuffle and written in ascending order. Items are exchangeable, so no pair co-occurs more than chance. A k-itemset has expected support `N * prod_{j<k} (w - j) / (100 - j)` transactions, which sets where each level of the search stops being frequent.

The generator is SplitMix64 with seed `(42 << 32) | w`, not Julia's `Xoshiro`, because Julia does not promise one random stream across versions. The files are byte-identical on every platform. An independent Python generator reproduces the SHA-256 of the width-5 file and of a 5-transaction database in `tests/width.jl`.

```sh
julia --startup-file=no --project=. scripts/width_experiment.jl freeze
julia --startup-file=no --project=. scripts/width_experiment.jl pilot --out results/raw/width-pilot-20261111
```

`freeze` writes `data/benchmark/width-wNN.txt` and `experiments/configs/width-manifest.toml` with their SHA-256 and refuses to replace an existing manifest. `run` regenerates a missing or changed file and fails if its bytes differ from the manifest.

## Protocols

Fixed minsup uses 0.05 (count 500) at every width. The output volume then jumps with the width, because a pair or triple reaches the count only once the width is large enough. Matched output uses, per width, the largest count that keeps at least 5,000 itemsets, from `pilot`, so the output stays near 5,000 and the width is the only change.

| Width | Density | Pair support, expected | Matched count | Matched minsup | Matched output | Fixed output at 500 |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 0.05 | 20.2 | 10 | 0.001 | 5,028 | 53 |
| 10 | 0.10 | 90.9 | 69 | 0.0069 | 5,016 | 100 |
| 15 | 0.15 | 212.1 | 179 | 0.0179 | 5,007 | 100 |
| 20 | 0.20 | 383.8 | 340 | 0.034 | 5,007 | 100 |
| 25 | 0.25 | 606.1 | 550 | 0.055 | 5,007 | 5,050 |
| 30 | 0.30 | 878.8 | 815 | 0.0815 | 5,002 | 5,050 |
| 35 | 0.35 | 1,202.0 | 1,127 | 0.1127 | 5,002 | 5,050 |
| 40 | 0.40 | 1,575.8 | 1,488 | 0.1488 | 5,001 | 166,749 |

At count 500 the width-25 pairs (expected 606) are frequent and the width-20 pairs (384) are not, which is the first cliff. The width-40 triples (expected 611) are frequent, which is the second. Every minsup above rounds to the same count in `support_threshold` and in SPMF.

## Measurement

Host: AMD Ryzen 7 H 260, 16 logical CPUs, 31.3 GiB, Windows 11, Julia 1.13.2 with one thread, SPMF 2.66 on OpenJDK 25.0.4.1. Code revision `8afea3d` plus the uncommitted width tooling, so the harness reports it as dirty. Each point has three repeats. Variants are baseline, optimized, and SPMF Eclat. The time is `process` scope in cold mode: spawn to exit, with Julia start-up and compilation, as in the other runtime curves. All 480 attempts are `ok`, and every output equals a separate SPMF Eclat run exactly.

A third run repeats the matched protocol for baseline and optimized in warm mode. Its `mine` scope times one call after toy compilation and one full run of the same input, so it excludes Julia start-up and compilation. All 48 attempts are `ok` and exact against SPMF.

```sh
julia --startup-file=no --project=. scripts/width_experiment.jl run experiments/configs/width-fixed.toml --out results/raw/width-fixed-20261111
julia --startup-file=no --project=. scripts/width_experiment.jl run experiments/configs/width-matched.toml --out results/raw/width-matched-20261111
for p in fixed matched; do
  julia --startup-file=no --project=. scripts/runtime_curves.jl --out results/raw/width-$p-20261111/curves \
    --ratio baseline/optimized --ratio spmf/baseline \
    "baseline=results/raw/width-$p-20261111:baseline#cold" "optimized=results/raw/width-$p-20261111:optimized#cold" \
    "spmf=results/raw/width-$p-20261111:spmf"
  julia --startup-file=no --project=. scripts/join_work.jl --manifest experiments/configs/width-manifest.toml \
    --out results/raw/width-$p-20261111/join-work experiments/configs/width-$p.toml
done
julia --startup-file=no --project=. scripts/width_experiment.jl run experiments/configs/width-matched-warm.toml --out results/raw/width-matched-warm-20261111
python scripts/plot_width_curves.py results/raw/width-fixed-20261111/curves/curves.csv \
  results/raw/width-matched-20261111/curves/curves.csv   --warm-summary results/raw/width-matched-warm-20261111/summary.csv --out results/raw/width-figure
```

The figure `results/raw/width-figure/width-curves.png` has four panels: both cold protocols, the output volume of each, and the warm `mine` time. The raw files are `runs.csv`, `summary.csv`, `curves/curves.csv`, `curves/ratios.csv`, and `join-work/join-work.csv` in each run folder under `results/raw/`, which Git ignores.

## Results

Median seconds of three repeats at matched output, with the baseline's work counted by `join_work`. Joins and itemsets stay level, so the merged elements, the sum of both tid-list lengths over every join, carry the whole change.

| Width | Itemsets | Joins | Successful joins | Merged elements | Baseline s | Optimized s | SPMF s |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 5 | 5,028 | 165,023 | 4,928 | 11.4 M | 0.99 | 0.86 | 0.60 |
| 10 | 5,016 | 164,394 | 4,916 | 38.9 M | 1.14 | 0.95 | 1.06 |
| 15 | 5,007 | 163,856 | 4,907 | 82.4 M | 1.31 | 0.82 | 1.65 |
| 20 | 5,007 | 163,883 | 4,907 | 142.0 M | 2.05 | 0.88 | 2.76 |
| 25 | 5,007 | 163,571 | 4,907 | 217.2 M | 2.46 | 0.86 | 3.60 |
| 30 | 5,002 | 163,602 | 4,902 | 308.8 M | 2.95 | 0.76 | 5.95 |
| 35 | 5,002 | 163,549 | 4,902 | 416.4 M | 3.50 | 0.82 | 8.53 |
| 40 | 5,001 | 163,320 | 4,901 | 538.8 M | 4.86 | 0.96 | 12.67 |

Cold `process` time hides the optimized variant, because it includes about 0.8 s of Julia start-up and compilation that does not depend on the width. The warm `mine` scope removes it. Medians of three repeats at matched output:

| Width | Merged elements | Baseline mine s | Baseline ns per merged element | Optimized mine ms |
|---:|---:|---:|---:|---:|
| 5 | 11.4 M | 0.0724 | 6.3 | 5.99 |
| 10 | 38.9 M | 0.2264 | 5.8 | 6.35 |
| 15 | 82.4 M | 0.4443 | 5.4 | 7.21 |
| 20 | 142.0 M | 0.9338 | 6.6 | 7.92 |
| 25 | 217.2 M | 1.5943 | 7.3 | 8.50 |
| 30 | 308.8 M | 2.2974 | 7.4 | 9.31 |
| 35 | 416.4 M | 3.0520 | 7.3 | 10.15 |
| 40 | 538.8 M | 3.8243 | 7.1 | 10.58 |

From width 5 to 40 at matched output, the baseline's mining time grows 53 times while its merged elements grow 47 times, and its cost stays between 5.4 and 7.4 ns per merged element. The optimized mining time grows 1.8 times, from 6.0 to 10.6 ms. In cold `process` scope the baseline slows 4.9 times and SPMF 21 times, and optimized stays within 0.76 to 0.96 s, all dominated by start-up at the small widths.

At fixed minsup 0.05:

| Width | Itemsets | Joins | Successful joins | Merged elements | Baseline s | Optimized s | SPMF s |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 5 | 53 | 1,378 | 0 | 1.4 M | 0.86 | 0.76 | 0.35 |
| 10 | 100 | 4,950 | 0 | 9.9 M | 0.91 | 0.89 | 0.37 |
| 15 | 100 | 4,950 | 0 | 14.9 M | 0.93 | 0.97 | 0.40 |
| 20 | 100 | 4,950 | 0 | 19.8 M | 1.12 | 0.81 | 0.40 |
| 25 | 5,050 | 166,650 | 4,950 | 220.7 M | 2.64 | 0.85 | 4.15 |
| 30 | 5,050 | 166,650 | 4,950 | 313.9 M | 3.35 | 0.92 | 7.20 |
| 35 | 5,050 | 166,650 | 4,950 | 423.5 M | 3.91 | 1.02 | 11.31 |
| 40 | 166,749 | 4,087,798 | 166,649 | 5,335.5 M | 43.72 | 1.18 | 145.17 |

## Reading

Width acts on Eclat in two ways, and the two protocols pull them apart.

Output volume. A wider transaction contains more pairs and triples, so more of them reach the count. At fixed minsup the output rises 53, 100, 5,050, 166,749 in steps, and the runtime follows the steps: baseline 1.1 s at width 20, 2.6 s at 25, 43.7 s at 40. A plot of runtime against width at one minsup mostly shows the output, so it is not evidence of a width effect.

Tid-list length at matched output. With the output level, Eclat makes the same number of joins (about 164,000, of which 4,900 succeed) at every width, yet the baseline's mining time grows 53 times. The baseline merges sorted tid-lists, so one join costs the sum of both lengths. An item sits in `w / 100` of the transactions, so its tid-list grows with the width, and the lists of the deeper itemsets grow with a higher power of it, because a pair holds `w (w - 1) / (100 * 99)` of them. The merged elements therefore grow 47 times for a width that grows 8 times, and the baseline's time follows them at a near-constant 5.4 to 7.4 ns per element. The optimized variant joins bitsets of `ceil(10000 / 64)` = 157 words whatever the lists hold, so its cost grows only 1.8 times. This record does not isolate the source of that growth. SPMF slows more than the baseline in cold `process` scope (21 times against 4.9). This record does not inspect SPMF's source, so a cause stays a hypothesis.

Deeper and wider enumeration. At fixed minsup the search goes one level deeper at widths 25 (pairs) and 40 (triples), and the number of equivalence classes it opens and joins multiplies (166,650 joins at width 25, 4.1 M at width 40). That is the tree getting both deeper and wider. At matched output the tree has the same size at every width, so only the cost per join changes.

## Scope and limits

- The model has independent items. It excludes the correlation that makes Chess and Mushroom dense, so it isolates width and does not stand in for those datasets.
- Eight widths at one `N` and one item universe. A different `N` or universe moves the expected supports and therefore the cliffs, and is not measured here.
- Three repeats on one Windows machine. The cold curves use `process` scope, which cannot separate the optimized variant's mining from start-up, so the warm `mine` scope carries that comparison. The warm run has no SPMF series. A run on the scored BBQ host would replace both.
- The matched target of 5,000 is a choice. A target of 50,000 would move every matched count and not the shape.
- The raw folders are local and untracked. Rerun the commands above on a clean revision to attach a clean `code_revision`.
