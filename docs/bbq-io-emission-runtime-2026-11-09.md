# BBQ input-output and emission runtime, 2026-11-09

The [input and output pass](bbq-io-pass-2026-11-09.md), the [exact-size emission](bbq-exact-emission-2026-11-09.md), and the [depth-ordered nodes with the block-count bound](bbq-depth-nodes-block-bound-2026-11-09.md) were measured as probes, with no SPMF check and no PrePost+ ratio. This record scores them under the [measurement protocol](../experiments/README.md) against the [sparse-kernel revision](bbq-sparse-kernel-runtime-2026-11-08.md) and PrePost+ in one session.

## Method

- Required grid: run `bbq-emission-cli-20261109T082431Z`, 2026-11-09T08:27:15Z to 08:48:51Z, covering the 33 points in [runtime.toml](../experiments/configs/runtime.toml) with five repeats.
- Stress series: run `bbq-emission-stress-cli-20261109T082431Z`, 08:52:32Z to 09:32:57Z, covering the declared stress points (Chess 0.55 and 0.5, Mushroom 0.05, Retail 0.0005 and 0.00025, Accidents 0.6, 0.5, and 0.4) with five repeats and a 900 s timeout.
- Both runs time three revisions of the `demo.jl` CLI with `--variant optimized`: `sparse-kernel` at `8b2fd33`, `io-pass` at `026c479`, and `emission-bound` at `d8bdfc4`, which adds exact-size emission, depth-ordered nodes, and the block-count bound. PrePost+ runs once per repeat, and the revision order reverses on every other repeat.
- Each step's ratio divides its median process time by that of the revision before it. R is the `emission-bound` median divided by PrePost+'s.
- Every output is compared with a separate SPMF Eclat run after timing ends. The controller checks the fixed 2.3 GHz clock at both ends.
- The candidate's largest IQR is 3.0% of its median, and PrePost+'s is 9.7% (Mushroom 0.05).

## Results

All 660 required outputs and all 160 stress outputs match SPMF Eclat exactly, with no failures or timeouts. Both audits pass, and both archives match their recorded SHA-256 after transfer.

| Measure | I/O pass / sparse kernel | Emission and bound / I/O pass |
|---|---|---|
| Ratio over the 33 required points | 0.757 to 0.990 | 0.821 to 1.027 |
| Geometric mean, Accidents | 0.763 | 1.006 |
| Geometric mean, Retail | 0.915 | 1.007 |
| Geometric mean, T10I4D100K | 0.897 | 0.971 |
| Geometric mean, Chess and Mushroom | 0.962 and 0.955 | 0.993 and 0.985 |
| Stress ratio | 0.748 to 0.948 | 0.810 to 1.003 |
| Peak RSS ratio | 0.74 to 1.00; stress 0.75 to 1.00 | 0.83 to 1.02; stress 0.75 to 1.00 |

| Point | Itemsets | Sparse kernel s | I/O pass s | Emission and bound s | PrePost+ s | R |
|---|---:|---:|---:|---:|---:|---:|
| Chess 0.6 | 254,944 | 0.359 | 0.327 | 0.300 | 0.591 | 0.51 |
| Chess 0.55, stress | 574,998 | 0.536 | 0.469 | 0.434 | 0.667 | 0.65 |
| Chess 0.5, stress | 1,272,932 | 0.903 | 0.749 | 0.697 | 0.891 | 0.78 |
| Mushroom 0.1 | 574,431 | 0.525 | 0.450 | 0.401 | 0.680 | 0.59 |
| Mushroom 0.05, stress | 3,755,511 | 2.209 | 1.784 | 1.445 | 1.378 | 1.05 |
| Retail 0.001 | 7,589 | 0.422 | 0.378 | 0.382 | 3.516 | 0.11 |
| Retail 0.00025, stress | 47,448 | 0.592 | 0.557 | 0.557 | 5.933 | 0.09 |
| T10I4D100K 0.00025 | 96,959 | 1.247 | 1.176 | 0.966 | 4.340 | 0.22 |
| Accidents 0.65 | 1,093 | 1.099 | 0.849 | 0.856 | 2.341 | 0.37 |
| Accidents 0.4, stress | 32,528 | 1.235 | 0.984 | 0.953 | 3.032 | 0.31 |

Both steps pass the [survival rule](eclat-optimization-plan-2026-10-30.md#survival-rule). The I/O pass cuts every Accidents point by 20% to 25%, because reading the 34 MB file was the largest cost there, and it lowers Accidents peak RSS from 533 MiB to 397 MiB. It cuts Retail and T10I4D100K by 5% to 12%. The emission step cuts its targets by 10.8% on Mushroom 0.1, 17.9% on T10I4D100K 0.00025, and 19.0% on Mushroom 0.05, and its largest slowdown is 2.7% on Accidents 0.8. It lowers Mushroom 0.05 peak RSS from 911 MiB to 686 MiB and Mushroom 0.1 from 363 MiB to 302 MiB.

The optimized CLI is faster than PrePost+ at every required point, with R from 0.11 to 0.59. Geometric mean R is 0.20 on Retail, 0.21 on T10I4D100K, 0.41 on Accidents, 0.49 on Mushroom, and 0.51 on Chess. Among the stress points, PrePost+ is faster only on Mushroom 0.05, by 0.067 s, where the CLI writes 3,755,511 lines. Chess 0.5 closes to R 0.78.

The [I/O pass figure](../results/figures/bbq-io-pass-cli-20261109/comparison.png), the [emission figure](../results/figures/bbq-emission-bound-cli-20261109/comparison.png), and the [stress figure](../results/figures/bbq-emission-stress-cli-20261109/comparison.png) show every point with median and IQR. Raw rows are in `results/raw/` under the two run names. The archive SHA-256s are `149839561c758c039dfff6c37e65673c2df8b3e06348bd9bfdeccd302a069880` for the required grid and `40b026e4db9055dd568f5a9e2ef750415be221e802bb216da65b6c87161b8561` for the stress series. Regenerate a figure with:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/compare_runs.py \
  "I/O pass=results/raw/bbq-emission-cli-20261109T082431Z:optimized@io-pass" \
  "Emission and bound=results/raw/bbq-emission-cli-20261109T082431Z:optimized@emission-bound" \
  "SPMF PrePost+=results/raw/bbq-emission-cli-20261109T082431Z:prepost" \
  --out results/figures/bbq-emission-bound-cli-20261109
```
