# BBQ precompiled-CLI runtime, 2026-11-06

The package image held the native code of every mining call, but `demo.jl` defined the command line itself, so every cold run compiled the script's `main`. On BBQ, `--trace-compile-timing` charged 108.6 ms to it on Chess 0.9, a third of the 0.32 s run. This record measures moving the command line into the package, `src/cli.jl`, and running it in the precompile workload, against the [sorted-output revision](bbq-sorted-output-runtime-2026-11-06.md) and PrePost+ in one session.

## Change

`cli_main` holds the argument parsing and the mining call, and `cli_exit_code` turns an error into exit code 1 with an `ERROR:` line on stderr. `demo.jl` only calls `cli_exit_code(ARGS)`. The precompile workload runs both on a file stream, for `--help`, `--check-input`, and mining with each variant and each threshold type. A test runs `demo.jl` cold under `--trace-compile` and requires that it compiles no method at all.

## Method

- Run `bbq-precompiled-cli-20261106T131647Z`, 2026-11-06T13:19:47Z to 13:39:58Z, covering the 33 points in [runtime.toml](../experiments/configs/runtime.toml) with five repeats.
- It times two revisions of the `demo.jl` CLI with `--variant optimized`. The control is `sorted-output` at `1ac9a6c`, and the candidate is `precompiled-cli` at `4cf9514`. PrePost+ runs once per repeat, and the revision order reverses on every other repeat.
- The ratio is the candidate's median process time divided by the control's. R is the candidate's median divided by PrePost+'s.
- Every output is compared with a separate SPMF Eclat run after timing ends. The controller checks the fixed 2.3 GHz clock at both ends.

## Results

All 495 outputs match SPMF Eclat exactly, with no failures or timeouts. The audit passes, and all 3,240 evidence files match their recorded SHA-256 after transfer. The largest IQR is 9.4% of its median (PrePost+, Mushroom 0.2), and the candidate's largest is 7.0% (Retail 0.0015).

| Measure | Result over the 33 points |
|---|---|
| Time saved per run | 0.096 to 0.160 s, median 0.111 s |
| Candidate / control time | 0.663 to 0.936, median 0.769 |
| Geometric mean of that ratio | Chess 0.691, Mushroom 0.699, Retail 0.796, T10I4D100K 0.837, Accidents 0.882 |
| Optimized / PrePost+ time (R) | 0.25 to 0.74 |
| Geometric mean R | T10I4D100K 0.30, Retail 0.33, Mushroom 0.51, Chess 0.53, Accidents 0.53 |
| Peak RSS, candidate / control | 0.91 to 1.03 |

| Point | Itemsets | Sorted output s | Precompiled CLI s | PrePost+ s | R |
|---|---:|---:|---:|---:|---:|
| Chess 0.9 | 622 | 0.325 | 0.217 | 0.401 | 0.54 |
| Chess 0.6 | 254,944 | 0.466 | 0.358 | 0.610 | 0.59 |
| Mushroom 0.5 | 153 | 0.329 | 0.219 | 0.445 | 0.49 |
| Mushroom 0.1 | 574,431 | 0.644 | 0.525 | 0.712 | 0.74 |
| Retail 0.001 | 7,589 | 1.763 | 1.606 | 3.518 | 0.46 |
| T10I4D100K 0.00025 | 96,959 | 1.759 | 1.647 | 4.336 | 0.38 |
| Accidents 0.65 | 1,093 | 1.260 | 1.118 | 2.348 | 0.48 |

Every point gets faster by about the compile time that the trace measured, so the relative gain is largest where the run is shortest. The change passes the [survival rule](eclat-optimization-plan-2026-10-30.md#survival-rule): every development point gains at least 8.9% (Retail 0.001), and none regresses. Accidents saves 0.14 to 0.16 s, more than the 103 ms that the trace charged to `main` on Accidents 0.65. The trace counts compile time only, so the rest is unexplained.

A cold Chess 0.9 run now takes 0.217 s. Starting an empty Julia process takes 0.17 s and loading the package 0.018 s on the same host, so less than 0.03 s of the run is reading, mining, and writing. The remaining fixed cost is the Julia runtime itself, which only an ahead-of-time build such as `juliac` could remove.

The [figure](../results/figures/bbq-precompiled-cli-20261106/comparison.png) shows every point with median and IQR. Raw rows are in `results/raw/bbq-precompiled-cli-20261106T131647Z/`. The archive SHA-256 is `82865a69075ec083398bf443a5132d7c33bf1f914bc888f72e30429973542bcf`. Regenerate the figure with:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/compare_runs.py \
  "Sorted output=results/raw/bbq-precompiled-cli-20261106T131647Z:optimized@sorted-output" \
  "Precompiled CLI=results/raw/bbq-precompiled-cli-20261106T131647Z:optimized@precompiled-cli" \
  "SPMF PrePost+=results/raw/bbq-precompiled-cli-20261106T131647Z:prepost" \
  --out results/figures/bbq-precompiled-cli-20261106
```
