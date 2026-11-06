# BBQ dense-kernel runtime, 2026-11-06

After precompilation, the remaining gap to PrePost+ at low thresholds was mining: the baseline merged long sorted tid-lists and allocated gigabytes on dense data. This record measures the [bitset variant](eclat-optimized.md) against the precompiled baseline and PrePost+ in one session on the [host of the baseline record](bbq-baseline-runtime-2026-10-31.md).

## Method

- Run: `bbq-dense-kernel-cli-20261106T081816Z`, 2026-11-06T08:20:50Z to 08:47:57Z. It measures the `demo.jl` of revision `d2ca660ff4b1885c98e2f86fe51018e5c34d473b` in `cli` mode, so no measurement code runs in the timed process.
- Within each repeat of each point, the baseline, the optimized variant, and PrePost+ run one after another, so drift spreads evenly across all three. The run covers all 33 points in [runtime.toml](../experiments/configs/runtime.toml) with five repeats: 495 attempts.
- R is the median process time of the optimized CLI divided by that of PrePost+ at the same point. Both are cold processes that read the same file and write every itemset.
- Every output is compared with a separate SPMF Eclat run after timing ends.
- The controller refuses to start, and fails the audit, unless `no_turbo` is 1 and every policy's maximum clock is 2.3 GHz at both ends. The run passes.

## Results

All 495 outputs match SPMF Eclat exactly, with no failures or timeouts. The audit passes, and all 3,244 evidence files match their recorded SHA-256 after transfer. The three programs write the same itemset count at every point. The largest IQR is 10.4% of its median (optimized, Retail 0.001), and every other point stays under 8.5%.

| Measure | Result over the 33 points |
|---|---|
| Optimized / baseline time | 0.10 to 0.97, median 0.37 |
| Optimized / PrePost+ time (R) | 0.30 to 1.29 |
| Points with R at most 1 | 32 of 33 |
| Geometric mean R | T10I4D100K 0.36, Retail 0.41, Accidents 0.61, Mushroom 0.78, Chess 0.79 |
| Geometric mean R of the baseline | Accidents 1.27, Retail 1.34, Mushroom 1.62, Chess 1.72, T10I4D100K 2.91 |
| Peak RSS, optimized / baseline | 0.68 to 0.99 |
| Peak RSS, optimized / PrePost+ | 1.00 to 1.60, at most 548 MiB |

| Point | Itemsets | Baseline s | Optimized s | PrePost+ s | R |
|---|---:|---:|---:|---:|---:|
| Chess 0.6 | 254,944 | 3.24 | 0.54 | 0.59 | 0.92 |
| Mushroom 0.1 | 574,431 | 6.28 | 0.88 | 0.68 | 1.29 |
| Retail 0.001 | 7,589 | 12.80 | 1.90 | 3.64 | 0.52 |
| T10I4D100K 0.00025 | 96,959 | 10.92 | 1.72 | 4.33 | 0.40 |
| Accidents 0.65 | 1,093 | 7.13 | 1.26 | 2.35 | 0.54 |

The stage passes the [survival rule](eclat-optimization-plan-2026-10-30.md#survival-rule). Every dense development point gets faster by at least 37% (Mushroom 0.25) and up to 86% (Mushroom 0.1), no point regresses, and peak RSS falls everywhere. The sparse datasets gain too, by 6.8 times on Retail 0.001 and 6.4 times on T10I4D100K 0.00025, although bitsets cost more per join there than sorted lists would.

The run also meets the [speed target](eclat-optimization-plan-2026-10-30.md#speed-target). Every dataset's geometric mean R is below 1.0, and R is at most 0.70 at all 17 points where PrePost+ takes at least 1 s. The one point above 1 is Mushroom 0.1, where PrePost+ takes 0.68 s and the optimized CLI writes 574,431 itemsets. At the highest thresholds the optimized CLI takes 0.32 s, close to the cost of starting Julia and loading the package.

The [figure](../results/figures/bbq-dense-kernel-cli-20261106/comparison.png) shows every point with median and IQR. Raw rows are in `results/raw/bbq-dense-kernel-cli-20261106T081816Z/`. The archive SHA-256 is `4f32279ef44a5f43b810992ccd7d0705418909aa2a51cae3aff1b538ef9b0e3e`. Regenerate the figure with:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/compare_runs.py \
  "Baseline=results/raw/bbq-dense-kernel-cli-20261106T081816Z:baseline" \
  "Optimized=results/raw/bbq-dense-kernel-cli-20261106T081816Z:optimized" \
  "SPMF PrePost+=results/raw/bbq-dense-kernel-cli-20261106T081816Z:prepost" \
  --out results/figures/bbq-dense-kernel-cli-20261106
```
