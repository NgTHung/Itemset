# BBQ scalability runtime, 2026-11-19

The brief asks whether runtime grows linearly or nonlinearly with database size. This record times the four contenders on seeded nested subsets of Accidents and Retail at one fixed relative minsup each, under the [measurement protocol](../experiments/README.md#scalability-and-width). The report discusses the results in Chapter 2, section "Khả năng mở rộng".

## Method

- Run `bbq-scalability-cli-20261119T140526Z`, 2026-11-19T14:15:15Z to 14:30:57Z, on BBQ (i7-11800H at a fixed 2.3 GHz, Julia 1.13.2 with one thread, SPMF 2.66 on Temurin 25.0.4.1 with a 4 GiB heap).
- Config: [scalability.toml](../experiments/configs/scalability.toml) at revision `ecd9534`. The baseline and optimized `demo.jl` CLIs, SPMF Eclat, and PrePost+ run five interleaved repeats on every subset.
- Subsets: [prepare_subsets.jl](../experiments/prepare_subsets.jl) keeps the first 10, 25, 50, 75, and 100 percent of one `DEFAULT_SEED` permutation. Preflight regenerated every subset on BBQ, and each matched the SHA-256 in [subsets.toml](../data/benchmark/subsets.toml).
- Thresholds: minsup 0.65 on Accidents, giving σ from 22,112 to 221,119, and minsup 0.001 on Retail, giving σ from 9 to 89.
- Every output is compared with a separate SPMF Eclat run after timing ends. The controller checks the clock at both ends and audits every row.
- The fit is ordinary least squares of the median process time on N, T(N) = a + bN, over the five subsets.

## Results

All 200 outputs match SPMF Eclat exactly, with no failures or timeouts, and the audit passes. The largest IQR is 1.9% of the median for the two Julia variants and 7.6% for the SPMF programs.

| Database | Program | a (s) | b (s per 100k transactions) | R² | T(100%) / T(10%) |
|---|---|---:|---:|---:|---:|
| Accidents | Baseline | 0.185 | 1.896 | 0.99988 | 8.13 |
| Accidents | Optimized | 0.188 | 0.195 | 0.99862 | 3.27 |
| Accidents | SPMF Eclat | -1.158 | 8.015 | 0.99508 | 12.35 |
| Accidents | PrePost+ | 0.516 | 0.544 | 0.99869 | 3.47 |
| Retail | Baseline | 0.613 | 12.873 | 0.99960 | 6.73 |
| Retail | Optimized | 0.215 | 0.182 | 0.99784 | 1.61 |
| Retail | SPMF Eclat | 0.997 | 0.685 | 0.99229 | 1.53 |
| Retail | PrePost+ | 0.475 | 3.510 | 0.99826 | 4.42 |

| Subset | N | Frequent items | Itemsets | Baseline s | Optimized s | SPMF Eclat s | PrePost+ s |
|---|---:|---:|---:|---:|---:|---:|---:|
| Accidents 10% | 34,018 | 18 | 1,095 | 0.818 | 0.258 | 2.162 | 0.678 |
| Accidents 100% | 340,183 | 18 | 1,093 | 6.653 | 0.846 | 26.706 | 2.352 |
| Retail 10% | 8,816 | 2,270 | 8,895 | 1.777 | 0.232 | 1.041 | 0.797 |
| Retail 100% | 88,162 | 2,117 | 7,589 | 11.953 | 0.374 | 1.590 | 3.523 |

Every series is linear in N, with R² of at least 0.992. A fixed relative minsup keeps the frequent itemsets almost unchanged, so the number of intersections stays constant while each tidset grows with N. The optimized intercept of 0.19 to 0.22 s is Julia start-up and package load, which is why its time grows only 3.3 and 1.6 times for 10 times the data. Its marginal cost is 9.7 times lower than the baseline's on Accidents and 71 times lower on Retail, where root pair counting replaces most root intersections. The optimized CLI is faster than PrePost+ at all ten points, with R from 0.35 to 0.38 on Accidents and from 0.29 down to 0.11 on Retail.

The Retail 10% subset carries extra work: at σ = 9, sampling noise lifts more near-threshold itemsets above σ than it drops, so it has 17% more itemsets than the full database. The largest residual from the fitted line is 4 ms for the optimized CLI and 0.12 s for the baseline, so the effect does not bend either curve. SPMF Eclat on Accidents is the one mildly superlinear series: it grows 12.35 times for 10 times the data, and its quadratic term is positive.

## Reproduce

The raw rows are in `results/raw/bbq-scalability-cli-20261119T140526Z/`, with archive SHA-256 `55340c7242bce9df9bba262d6941fd66f94601cc8782838205b540b1babd0abe`. The run folder also keeps the BBQ `prepare.py`, `launch.sh`, `resume.sh`, and controller. Regenerate the curves and the figure with:

```sh
RUN=results/raw/bbq-scalability-cli-20261119T140526Z
OUT=results/figures/bbq-scalability-cli-20261119T140526Z
julia --startup-file=no --project=. scripts/runtime_curves.jl --out $OUT \
  "Baseline Eclat=$RUN:baseline@final#cli" "Optimized Eclat=$RUN:optimized@final#cli" \
  "SPMF Eclat=$RUN:spmf" "SPMF PrePost+=$RUN:prepost"
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_scalability.py \
  $OUT/curves.csv --subsets data/benchmark/subsets.toml --out $OUT
```

`scripts/plot_scalability.py` also writes `scalability.csv` with every point. `docs/report/figures/scalability.pdf` is a copy of the figure.
