# BBQ sorted-output runtime, 2026-11-06

`write_itemsets` writes itemsets in numeric lexicographic order, so output files are byte-comparable across variants. The optimized variant emits itemsets in increasing-support order, so the writer had to sort them. A profile of the [perfect-extension revision](bbq-perfect-extensions-runtime-2026-11-06.md) on BBQ found that this comparison sort took 64% of a warm Mushroom 0.05 run, against 11% for mining. This record measures the replacement, a radix sort on packed prefix keys, against that revision and PrePost+ in one session.

## Profile

The profile ran on BBQ with Julia's `Profile` at 1 ms sampling, over three warm runs per point of revision `2cd24d1`.

- Mushroom 0.05, 10,718 samples: `checked_order` took 64%, nearly all of it in `sort!` calling `itemset_isless`. Writing took 25%, mostly digit formatting in `append_digits!`; `unsafe_write` was about 6% of it. Mining took 11%, two thirds of it copying itemsets into the packed result.
- Retail 0.001: 91% of samples were in `intersect_bitsets!`.
- Accidents 0.65: `read_transactions` took 59%, and counting items for `bitset_class` about 19%.

The baseline emits in item order, so its output is already sorted, and the old check cost one scan: 28 ms on Mushroom 0.1, against 285 ms for the optimized output.

## Change

`lexicographic_order` in `src/itemset_order.jl` keeps the one-scan path for sorted output. Otherwise it packs each itemset into a `UInt128`. The low bits hold the itemset's index, and the high bits hold its first items as digits of `item + 1`, first item highest, with 0 past the end. Comparing two keys as integers then compares those items in lexicographic order with a prefix first, so one radix sort orders all itemsets. Only itemsets whose keyed items are all equal are compared in full, and the same pass rejects a repeated itemset. On Mushroom 0.05 a key holds 15 items, and the longest itemset has 17.

A warm check on the development machine timed `checked_order` on the optimized output before and after: Mushroom 0.05 went from 2.23 s to 0.53 s, Mushroom 0.1 from 0.275 s to 0.072 s, and Chess 0.5 from 0.67 s to 0.17 s.

## Method

- Required grid: run `bbq-sorted-output-cli-20261106T105240Z`, 2026-11-06T10:55:34Z to 11:16:05Z, covering the 33 points in [runtime.toml](../experiments/configs/runtime.toml) with five repeats.
- Stress series: run `bbq-sorted-output-stress-cli-20261106T105240Z`, 11:18:42Z to 11:47:25Z, covering Chess 0.55 and 0.5 and Mushroom 0.05 with five repeats and a 900 s timeout.
- Both runs time two revisions of the `demo.jl` CLI with `--variant optimized`. The control is `perfect-extensions` at `2cd24d1`, and the candidate is `sorted-output` at `1d7d9a1`. PrePost+ runs once per repeat, and the revision order reverses on every other repeat.
- The ratio is the candidate's median process time divided by the control's. R is the candidate's median divided by PrePost+'s.
- Every output is compared with a separate SPMF Eclat run after timing ends. The controller checks the fixed 2.3 GHz clock at both ends and audits with the revision stage in each attempt key.

## Results

All 495 required outputs and all 45 stress outputs match SPMF Eclat exactly, with no failures or timeouts. Both audits pass, and all evidence files match their recorded SHA-256 after transfer.

| Measure | Required grid | Stress series |
|---|---|---|
| Candidate / control time | 0.773 to 1.021, median 0.992 | 0.598 to 0.757 |
| Geometric mean of that ratio | Chess 0.968, Mushroom 0.953, Retail 0.994, T10I4D100K 0.991, Accidents 0.993 | |
| Geometric mean R | T10I4D100K 0.35, Retail 0.41, Accidents 0.61, Mushroom 0.73, Chess 0.77 | |
| Points with R at most 1 | 33 of 33 | 1 of 3 |
| Peak RSS, candidate / control | 1.00 to 1.02 | 1.03 to 1.08 |
| Largest IQR | 8.2% of its median (candidate, Retail 0.001) | 6.6% (candidate, Mushroom 0.05) |

| Point | Itemsets | Perfect extensions s | Sorted output s | Ratio | PrePost+ s | R |
|---|---:|---:|---:|---:|---:|---:|
| Chess 0.6 | 254,944 | 0.538 | 0.462 | 0.859 | 0.582 | 0.79 |
| Chess 0.55 | 574,998 | 0.848 | 0.642 | 0.757 | 0.695 | 0.92 |
| Chess 0.5 | 1,272,932 | 1.512 | 1.000 | 0.661 | 0.885 | 1.13 |
| Mushroom 0.1 | 574,431 | 0.831 | 0.643 | 0.773 | 0.712 | 0.90 |
| Mushroom 0.05 | 3,755,511 | 4.058 | 2.429 | 0.598 | 1.364 | 1.78 |
| Retail 0.001 | 7,589 | 1.779 | 1.785 | 1.003 | 3.521 | 0.51 |
| T10I4D100K 0.00025 | 96,959 | 1.740 | 1.708 | 0.982 | 4.324 | 0.40 |
| Accidents 0.65 | 1,093 | 1.285 | 1.255 | 0.976 | 2.326 | 0.54 |

The change passes the [survival rule](eclat-optimization-plan-2026-10-30.md#survival-rule). It cuts the targeted points Chess 0.6 by 14.1% and Mushroom 0.1 by 22.7%, and the stress points by 24% to 40%. No point regresses by more than 2.1%. Peak RSS rises by at most 8%, on Mushroom 0.05, where the 3.76 million 16-byte keys add 57 MiB. The datasets with few itemsets, Retail, T10I4D100K, and Accidents, change by less than run-to-run noise.

The required grid now meets the [speed target](eclat-optimization-plan-2026-10-30.md#speed-target) at every point. Mushroom 0.1, the last point above 1, falls from R 1.17 to 0.90. R is at most 0.70 at every point where PrePost+ takes at least 1 s. On the stress series, Chess 0.5 and Mushroom 0.05 stay slower than PrePost+, at R 1.13 and 1.78. There the remaining costs are writing 41 MiB and 129 MiB of text, the radix sort, which took about 0.27 s warm on the development machine, and copying itemsets into the packed result.

The [required-grid figure](../results/figures/bbq-sorted-output-cli-20261106/comparison.png) and the [stress figure](../results/figures/bbq-sorted-output-stress-cli-20261106/comparison.png) show every point with median and IQR. Raw rows are in `results/raw/` under the two run names. The archive SHA-256s are `fd0165a68599b4c8d7c8946814e753d5d264bdc69357abd4fb60dd6062bdcf52` for the required grid and `3fd10f8bacbb01c3aae523d663ebf3e4ea8d8b5ab7e8e7946a683636bab6ee29` for the stress series. Regenerate a figure with:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/compare_runs.py \
  "Perfect extensions=results/raw/bbq-sorted-output-cli-20261106T105240Z:optimized@perfect-extensions" \
  "Sorted output=results/raw/bbq-sorted-output-cli-20261106T105240Z:optimized@sorted-output" \
  "SPMF PrePost+=results/raw/bbq-sorted-output-cli-20261106T105240Z:prepost" \
  --out results/figures/bbq-sorted-output-cli-20261106
```
