# BBQ perfect-extension runtime, 2026-11-06

The [prototype](eclat-optimization-plan-2026-10-30.md#dense-prototype) showed that perfect-extension pruning cut the count-only search on Mushroom 0.05 from 0.627 s to 0.040 s. This record measures what that saving is worth in the cold CLI. It times the [optimized variant with pruning](eclat-optimized.md#perfect-extensions) against the dense-kernel revision and PrePost+ in one session, on the [host of the baseline record](bbq-baseline-runtime-2026-10-31.md).

## Method

- Required grid: run `bbq-perfect-extensions-cli-20261106T091449Z`, 2026-11-06T09:17:57Z to 09:38:37Z, covering the 33 points in [runtime.toml](../experiments/configs/runtime.toml) with five repeats.
- Stress series: run `bbq-perfect-extensions-stress-cli-20261106T094935Z`, 09:49:51Z to 10:19:07Z, covering Chess 0.55 and 0.5 and Mushroom 0.05 with five repeats and a 900 s timeout.
- Both runs time two revisions of the `demo.jl` CLI with `--variant optimized`. The control is `dense-kernel` at `8c043fb`, and the candidate is `perfect-extensions` at `210ae36`. PrePost+ runs once per repeat. The revision order reverses on every other repeat, as in the [measurement protocol](../experiments/README.md#compare-revisions-in-one-run).
- The ratio below is the candidate's median process time divided by the control's at the same point. R is the candidate's median divided by PrePost+'s.
- Every output is compared with a separate SPMF Eclat run after timing ends. The controller refuses to start, and fails the audit, unless `no_turbo` is 1 and every policy's maximum clock is 2.3 GHz at both ends. Both runs pass.

The controller's audit was written for one revision. It keyed attempts by dataset, threshold, repeat, and variant, so the two `optimized` revisions collided and the first audit failed on that key alone. `bbq_audit.py` in the run folder adds the stage to the key and otherwise repeats every check. Its result is in `audit.json`, with the original error recorded next to it.

## Results

All 495 required outputs and all 45 stress outputs match SPMF Eclat exactly, with no failures or timeouts. All evidence files match their recorded SHA-256 after transfer. Both revisions write the same itemset count at every point.

| Measure | Required grid | Stress series |
|---|---|---|
| Candidate / control time | 0.931 to 1.044, median 1.003 | 0.931 to 0.988 |
| Geometric mean of that ratio | Chess 0.995, Mushroom 0.988, Retail 0.988, T10I4D100K 1.009, Accidents 1.018 | |
| Geometric mean R | T10I4D100K 0.36, Retail 0.41, Accidents 0.62, Mushroom 0.77, Chess 0.79 | |
| Points with R at most 1 | 32 of 33 | 0 of 3 |
| Peak RSS, candidate / control | 0.95 to 1.00 | 0.90 to 0.96 |
| Largest IQR | 12.0% of its median (PrePost+, Mushroom 0.25) | 4.4% (PrePost+, Mushroom 0.05) |

| Point | Itemsets | Dense kernel s | Perfect extensions s | Ratio | PrePost+ s | R |
|---|---:|---:|---:|---:|---:|---:|
| Chess 0.6 | 254,944 | 0.541 | 0.537 | 0.993 | 0.592 | 0.91 |
| Chess 0.55 | 574,998 | 0.858 | 0.847 | 0.988 | 0.640 | 1.32 |
| Chess 0.5 | 1,272,932 | 1.555 | 1.516 | 0.975 | 0.924 | 1.64 |
| Mushroom 0.1 | 574,431 | 0.888 | 0.826 | 0.931 | 0.670 | 1.23 |
| Mushroom 0.05 | 3,755,511 | 4.431 | 4.123 | 0.931 | 1.411 | 2.92 |
| Retail 0.001 | 7,589 | 1.859 | 1.751 | 0.942 | 3.681 | 0.48 |
| T10I4D100K 0.00025 | 96,959 | 1.793 | 1.798 | 1.003 | 4.352 | 0.41 |
| Accidents 0.65 | 1,093 | 1.254 | 1.286 | 1.026 | 2.342 | 0.55 |

The stage misses the [survival rule](eclat-optimization-plan-2026-10-30.md#survival-rule). Its targeted development points, Chess 0.75 and 0.6 and Mushroom 0.25 and 0.1, change by +0.7%, −0.7%, +0.8%, and −6.9%, and no stress point gains 10% either. Peak RSS falls slightly everywhere, and no point regresses by more than 4.4%.

The search is a small part of each process. A warm in-process check on the development machine timed the search alone on Mushroom 0.1 at 0.131 s before pruning and 0.071 s after, a saving of 60 ms, which matches the 62 ms the CLI gained. The rest of the 0.83 s is Julia start-up, reading, emitting 574,431 itemsets, and writing them. At Mushroom 0.05 the CLI saves 0.31 s out of 4.4 s for the same reason: emitting and writing 3.76 million itemsets dominate, and pruning does not reduce the number of itemsets written.

Accidents runs 1% to 2.6% slower in every repeat. The search there takes about 3 ms in both revisions, so pruning cannot explain it. A probe of eight cold processes per revision on BBQ found the gap in reading the input: `read_transactions` took 19 ms longer in the candidate, with identical source, allocations, and GC time. The two package images differ, so the difference is in their compiled code, not in the algorithm.

The [required-grid figure](../results/figures/bbq-perfect-extensions-cli-20261106/comparison.png) and the [stress figure](../results/figures/bbq-perfect-extensions-stress-cli-20261106/comparison.png) show every point with median and IQR. Raw rows are in `results/raw/` under the two run names. The archive SHA-256s are `9de89c28a9f59fb8757ea1b35947e942cfb71fa29bbea642da4a2ad87ab2b336` for the required grid and `10ce3099e23ffcfbe9018f32b51315d8c32d73b69d712ca7e905ea079bdf5c81` for the stress series. Regenerate a figure with:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/compare_runs.py \
  "Dense kernel=results/raw/bbq-perfect-extensions-cli-20261106T091449Z:optimized@dense-kernel" \
  "Perfect extensions=results/raw/bbq-perfect-extensions-cli-20261106T091449Z:optimized@perfect-extensions" \
  "SPMF PrePost+=results/raw/bbq-perfect-extensions-cli-20261106T091449Z:prepost" \
  --out results/figures/bbq-perfect-extensions-cli-20261106
```
