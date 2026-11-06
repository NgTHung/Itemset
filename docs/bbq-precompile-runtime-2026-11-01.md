# BBQ precompilation runtime, 2026-11-01

Compilation added about 2 s to every cold Julia run, and at high thresholds that was nearly the whole run. This record measures how much of that cost the package image removes. The baseline CLI runs before and after precompilation in one session on the [host of the baseline record](bbq-baseline-runtime-2026-10-31.md).

## Method

- Control: `bbq-baseline-cli-20261101T082039Z`, 2026-11-01T08:22:33Z to 08:43:24Z. It measures the `demo.jl` of revision `583abe3`.
- Candidate: `bbq-precompile-cli-20261101T082039Z`, 08:44:21Z to 08:59:25Z. It measures the `demo.jl` of revision `ebd2ac643c9be3dd7b8a6d44e183f6a0fb051ca1`, which adds [`src/precompile.jl`](../src/precompile.jl).
- Both use the harness at `ebd2ac6` in `cli` mode, so no measurement code runs in the timed process. Each has all 33 points in [runtime.toml](../experiments/configs/runtime.toml) with five repeats: 165 attempts per run.
- The two runs follow each other. They are not interleaved, so a slow drift between them would count toward the difference. The difference is far larger than the spread within either run.
- SPMF is not timed here. Every output is still compared with a separate SPMF Eclat run. PrePost+ times come from the [baseline record](bbq-baseline-runtime-2026-10-31.md), so R is an estimate from another session.
- The controller refuses to start, and fails the audit, unless `no_turbo` is 1 and every policy's maximum clock is 2.3 GHz at both ends. Both runs pass.

## Results

All 330 outputs match SPMF Eclat exactly, with no failures or timeouts. Both audits pass, and all 1248 evidence files of each run match their recorded SHA-256 after transfer. Output counts and hashes are identical across the two runs. The largest IQR is 4.1% of a median.

| Measure | Result over the 33 points |
|---|---|
| Time saved per process | 1.77 to 2.67 s, median 2.04 s |
| Precompiled / control time | 0.14 to 0.83 |
| Precompiled / PrePost+ time (R) | 0.70 to 9.52 |
| Points with R at most 1 | 11 of 33 |
| Geometric mean R | Accidents 1.25, Retail 1.31, Mushroom 1.60, Chess 1.71, T10I4D100K 2.78 |
| Peak RSS, precompiled / control | 0.82 to 0.97 |

Package load rises from 0.164 s to 0.176 s (median of nine), and the package image grows from 230,448 to 1,581,536 bytes. Chess 0.9 falls from 2.36 s to 0.33 s, against 0.40 s for PrePost+.

The stage passes the [survival rule](eclat-optimization-plan-2026-10-30.md#survival-rule): every point improves by at least 17%, nothing regresses, and peak RSS falls. The speed target is not met. No dataset's geometric mean R reaches 1.0, and Mushroom 0.1 stays at 9.52, because the remaining time at low thresholds is mining.

The control also isolates the worker's cost. The cold worker of the baseline record takes a median of 0.47 s longer than the control CLI at the same point, across two sessions.

The [figure](../results/figures/bbq-precompile-cli-20261101/comparison.png) shows every point with median and IQR. Raw rows are in `results/raw/bbq-baseline-cli-20261101T082039Z/` and `results/raw/bbq-precompile-cli-20261101T082039Z/`. The archive SHA-256 values are `15d2dfab455a9d382ebfaedd9c807fea935ba172e80bd1f6d3c1d38bda5774a3` and `adf9cdfc4162b295041abd7b08da8197e4b3c6e1b7a65a790fce1e98b71846fb`. Regenerate the figure with:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/compare_runs.py \
  "Before precompilation=results/raw/bbq-baseline-cli-20261101T082039Z:baseline" \
  "Precompiled=results/raw/bbq-precompile-cli-20261101T082039Z:baseline" \
  "SPMF PrePost+ (2026-10-31)=results/raw/bbq-b2-runtime-20261031T150716Z:prepost" \
  --out results/figures/bbq-precompile-cli-20261101
```
