# Transaction width through the command line, and the cost of the write order, 2026-11-28

The report times every benchmark point through `demo.jl`, but the width campaign of the [grading-machine width record](bbq-width-profile-2026-11-27.md) ran its cold protocols in the harness's `cold` mode. That mode starts the measurement worker, which compiles on every run, so the optimized variant's `process` time sat at 0.79 to 0.80 s while the same code takes 0.21 to 0.96 s through `demo.jl`. This record reruns the two cold width protocols in `cli` mode and times the write order that Proposal 2 of the report would skip.

## Run

`bbq-width-cli-20261127T223751Z` ran on BBQ from 22:38 to 23:00 UTC on 2026-11-27: Linux, Intel Core i7-11800H fixed at 2.3 GHz with `no_turbo` 1 at start and end, Julia 1.13.2 with one thread, and SPMF 2.67 on Temurin 25.0.4.1. The checkout is revision `8c15198`, whose `src/` and `demo.jl` equal revision `ca60f43` of the runtime campaign, and both worktree patches are empty. The configs are [`width-fixed-cli.toml`](../experiments/configs/width-fixed-cli.toml) and [`width-matched-cli.toml`](../experiments/configs/width-matched-cli.toml), copies of the cold configs with `mode = "cli"`. All 144 attempts (2 protocols, 8 widths, 3 programs, 3 repeats) are `ok` and match SPMF exactly.

The warm `mine` panel and table of the report still come from the 2026-11-27 run, because warm mode does not depend on how the process starts.

## Results

Median `process` seconds of three repeats under matched output:

| Width | Baseline | Optimized | SPMF Eclat |
|---:|---:|---:|---:|
| 5 | 0.346 | 0.221 | 0.639 |
| 10 | 0.592 | 0.220 | 1.140 |
| 15 | 0.961 | 0.224 | 2.175 |
| 20 | 1.583 | 0.225 | 3.670 |
| 25 | 2.227 | 0.228 | 5.688 |
| 30 | 3.049 | 0.229 | 8.979 |
| 35 | 3.945 | 0.235 | 12.356 |
| 40 | 4.976 | 0.234 | 15.527 |

From width 5 to 40 the baseline grows 14.4-fold and SPMF Eclat 24.3-fold, while the optimized variant stays at Julia start-up and reading. Under fixed minsup 0.05 the baseline takes 0.42, 2.27, and 46.9 s at widths 20, 25, and 40, the optimized variant 0.22 to 0.49 s, and SPMF Eclat 0.39 to 152.9 s.

`order_probe.jl` times the write order of the optimized result in a warm process in the checkout of the runtime campaign, as medians of seven calls after two warm-up calls:

| Point | Itemsets | `lexicographic_order` s | Print sorted s | Print in storage order s |
|---|---:|---:|---:|---:|
| chess 0.6 | 254,944 | 0.025 | 0.023 | 0.018 |
| mushroom 0.1 | 574,431 | 0.059 | 0.065 | 0.044 |
| mushroom 0.05 | 3,755,511 | 0.475 | 0.533 | 0.310 |

The 0.30 s sort time in [the I/O record](bbq-io-pass-2026-11-09.md) measured an earlier revision, before exact-size emission, so Proposal 2 now uses these times.

## Evidence

The raw folder is `results/raw/bbq-width-cli-20261127T223751Z`, which Git ignores. Its archive, `results/raw/evidence/bbq-width-cli-20261127T223751Z-results.tgz` without itemset outputs or SPMF references, has SHA-256 `ecfd20d3b178cfb44d215fb754bcd8b49368b3f8a9d037476040e4ec5b6f2552`. It holds `runs.csv`, `summary.csv`, `curves/`, `environment.toml`, and one folder per attempt with its `comparison.toml`, plus the driver `bbq_width_cli.sh`, `order_probe.jl`, and `order_probe.csv`.

## Reproduce

Copy `bbq_width_cli.sh`, the two CLI configs, and a Git bundle of the revision to `incoming/NAME/` under the benchmark root on BBQ, then run `sh bbq_width_cli.sh NAME 8c15198`. The probe runs from the runtime checkout with `julia --project=. order_probe.jl`. The report figures come from:

```sh
R=results/raw/bbq-width-cli-20261127T223751Z
W=results/raw/bbq-width-profile-20261127T044121Z/width-matched-warm/summary.csv
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_width_curves.py \
  $R/width-fixed-cli/curves/curves.csv $R/width-matched-cli/curves/curves.csv --warm-summary $W \
  --language vi --out docs/report/figures
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_width_curves.py \
  $R/width-fixed-cli/curves/curves.csv $R/width-matched-cli/curves/curves.csv --warm-summary $W \
  --out docs/report/figures/en
```
