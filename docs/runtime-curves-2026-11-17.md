# Runtime against minsup on the BBQ host, 2026-11-17

A runtime curve is only safe to cite when every point comes from a verified run in one session. This record fixes the cohort behind the runtime figure and tables of the report, the commands that rebuild them from the raw run, and the checks that make the numbers citable.

## Cohort

`bbq-all-variants-cli-5repeat-20261117T041922Z` runs four programs in one session on the scored BBQ host: Linux 6.12, Intel i7-11800H fixed at 2.30 GHz, 16 logical CPUs, 7.4 GiB, Julia 1.13.2 with one thread, Temurin 25.0.4.1, and SPMF 2.66 (jar SHA-256 `4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a`). The programs are the baseline and optimized Eclat of this repository, SPMF Eclat, and SPMF PrePost+. Both Julia variants run through `demo.jl` at revision `ca60f43`, and both worktree patches are empty, so the code is clean. The time is `process` scope: spawn to exit, with Julia or JVM start-up, reading, and writing.

The grid is the 33 points of `config.toml` (Chess, Mushroom, Retail, T10I4D100K, Accidents) with five repeats each. That is 660 attempts. They add 990 rows to `runs.csv`, because a baseline or optimized attempt records one `process` row and an SPMF or PrePost+ attempt records two (`process`, `spmf_total`). All 660 attempts are `ok`, and every output equals an independent SPMF Eclat run exactly.

## Provenance

Git ignores the run folder. Hung ran it and holds the original. The files below identify it:

| File | SHA-256 |
|---|---|
| `runs.csv` | `18cd97a286c0278cd09fff062f02914fc13392d7f946b906798feb9296435893` |
| `summary.csv` | `c2be97c03c216421a840062953af70035d8beb1905568bfd0d3dab4171a55107` |
| `audit.json` | `7f70c7291bc1c5d1e0901c8c03f7ac580dee01dc236f82c92f94a2b6f7f7d926` |
| `config.toml` | `746f092638b33178eb274fc5585d366e25ab16615b34bc4df5938bffb5e2f638` |
| `environment.toml` | `199e71f5c770a2b03145239b29ecb00c81bee2dccf04c419e090a1c3a71734b9` |
| `evidence-files.json` | `78ab246d03708eef4c603951aabb201cb7a181f7e3e846f32011d5c287746dcc` |

`evidence-files.json` lists the size and SHA-256 of the other 4,244 files of the folder. Every one matches the copy under `data/raw/` and no file is missing.

## Reproduce

Place the folder under `data/raw/`. Run from the repository root.

```sh
R=data/raw/bbq-all-variants-cli-5repeat-20261117T041922Z
julia --startup-file=no --project=. scripts/runtime_curves.jl --out results/figures/runtime \
  --ratio Baseline/Optimized --ratio SPMF/Optimized --ratio PrePost/Optimized --ratio Baseline/PrePost \
  "Baseline=$R:baseline" "Optimized=$R:optimized" "SPMF=$R:spmf" "PrePost=$R:prepost"
julia --startup-file=no --project=. scripts/join_work.jl --out results/figures/runtime/join-work $R/config.toml
uv run --no-project --python 3.12 --with matplotlib==3.11.2 python scripts/plot_runtime_curves.py \
  results/figures/runtime/curves.csv --out results/figures/runtime
```

The first command prints the geometric mean of each ratio per dataset and writes `curves.csv` and `ratios.csv`. The second counts the baseline's tid-list joins and merged elements, which do not depend on timing. The third draws the figure, and `docs/report/figures/runtime-curves.png` is its `runtime-curves.png`. The three commands reproduce the report's CSV files and figure byte for byte.

## Checks

- Each of the 132 variant and point groups has five exact samples.
- The quartiles of `curves.csv` equal the linear interpolation of those five samples in all 132 groups, which is how `experiments/summary.jl` computes them.
- Output counts agree across the four programs and with the earlier cohorts, and the SHA-256 of the five datasets equals theirs.
- Within the run, the interquartile range over the median is at most 2.9% for the baseline, 1.9% for the optimized variant, 11.3% for SPMF, and 13.9% for PrePost+.
- Across sessions, PrePost+ runs the same Java command in every cohort, so it measures drift. Against the cohorts of 2026-10-31, 2026-11-09, and 2026-11-12 the geometric mean of its time ratio is 1.030, 1.019, and 0.977, at most 14.4% at one point. The optimized variant against the 2026-11-12 run at the same revision has a geometric mean of 0.985 and at most 5.6% at one point.
- The four programs run in one session, so a ratio between two of them has only the noise within the run. The report calls a ratio real when it exceeds the sum of the two largest interquartile ranges: about 5% between the Julia variants and about 16% when one side is a Java program. The drift between sessions applies only to a comparison with another cohort.

## Limits

- One machine, and `process` scope includes start-up, so points where the baseline and optimized times are close mostly show start-up. The report names them.
- The baseline is the baseline of revision `ca60f43`, which already uses the faster reading and writing of later stages. It is not the baseline of the cohort of 2026-10-31, which ran in cold harness mode at revision `583abe3`, and the two are not comparable.
- The join counts run on one thread outside the timed session.
