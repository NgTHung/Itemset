# Report figures

Every figure and measured table in the report comes from a raw run on the grading machine (BBQ: Intel i7-11800H fixed at 2.3 GHz, Julia 1.13.2 with one thread, SPMF on Temurin 25.0.4.1). Git ignores `results/raw/`, so the team shares a run folder on request. This file names the run behind each figure and the commands that redraw it from that folder. Run them from the repository root.

| Figure | Raw run |
|---|---|
| `correctness-grid.pdf`, `runtime-curves.png`, `output-size.pdf` | `bbq-all-variants-cli-5repeat-20261117T041922Z`, `runs.csv` SHA-256 `18cd97a286c0278cd09fff062f02914fc13392d7f946b906798feb9296435893` |
| `scalability.pdf` | `bbq-scalability-cli-20261119T140526Z`, archive SHA-256 `55340c7242bce9df9bba262d6941fd66f94601cc8782838205b540b1babd0abe` |
| `width-curves.png` | Cold panels from `bbq-width-cli-20261127T223751Z`, warm panel from `bbq-width-profile-20261127T044121Z` |
| `semeion-source-contrast.png` | `semeion-k24`, from the [image-pattern guide](../../../applications/image_patterns/README.md#reproduce-the-sensitivity-study) |

## Correctness, runtime, and output size

The plotting script refuses to draw a run whose outputs do not all match SPMF. The report's peak RSS table is the median of the `peak_rss_bytes` column of `runs.csv` at the lowest minsup of each database.

```sh
R=results/raw/bbq-all-variants-cli-5repeat-20261117T041922Z
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_report_validation.py $R --out docs/report/figures
julia --startup-file=no --project=. scripts/runtime_curves.jl --out results/figures/runtime \
  --ratio Baseline/Optimized --ratio SPMF/Optimized --ratio PrePost/Optimized --ratio Baseline/PrePost \
  "Baseline=$R:baseline" "Optimized=$R:optimized" "SPMF=$R:spmf" "PrePost=$R:prepost"
julia --startup-file=no --project=. scripts/join_work.jl --out results/figures/runtime/join-work $R/config.toml
uv run --no-project --python 3.12 --with matplotlib==3.11.2 python scripts/plot_runtime_curves.py \
  results/figures/runtime/curves.csv --out docs/report/figures
julia --startup-file=no --project=. scripts/output_size.jl $R --out results/figures/output-size
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_output_size.py \
  results/figures/output-size/output-size.csv --out results/figures/output-size
cp results/figures/output-size/output-size.pdf docs/report/figures/
```

`runtime_curves.jl` prints the geometric mean of each ratio and writes `curves.csv` and `ratios.csv`. `join_work.jl` counts the baseline's tid-list joins and merged elements, which do not depend on timing. `output_size.jl` checks that the four programs agree on every count and writes the counts, length profiles, and growth slopes.

## Scalability

```sh
R=results/raw/bbq-scalability-cli-20261119T140526Z
julia --startup-file=no --project=. scripts/runtime_curves.jl --out results/figures/scalability \
  "Baseline Eclat=$R:baseline@final#cli" "Optimized Eclat=$R:optimized@final#cli" \
  "SPMF Eclat=$R:spmf" "SPMF PrePost+=$R:prepost"
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_scalability.py \
  results/figures/scalability/curves.csv --subsets data/benchmark/subsets.toml --out results/figures/scalability
cp results/figures/scalability/scalability.pdf docs/report/figures/
```

## Width and stage profile

```sh
R=results/raw/bbq-width-cli-20261127T223751Z
W=results/raw/bbq-width-profile-20261127T044121Z/width-matched-warm/summary.csv
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_width_curves.py \
  $R/width-fixed-cli/curves/curves.csv $R/width-matched-cli/curves/curves.csv --warm-summary $W \
  --out docs/report/figures
julia --startup-file=no --project=. scripts/stage_profile.jl --out results/raw/stage-profile --repeats 5 \
  experiments/configs/stage-profile.toml
```

[experiments/README.md](../../../experiments/README.md#scalability-and-width) describes how to run the width and scalability campaigns from scratch.
