# Frequent-itemset counts against minsup, 2026-11-19

The brief asks how the number of frequent itemsets grows as minsup falls, and how dense and sparse databases differ. This record reads the counts from the scored timing run instead of mining again, checks them, and measures each dataset's growth rate. The report discusses the results in the section "Number of frequent itemsets against minsup".

## Method

- Source: run `bbq-all-variants-cli-5repeat-20261117T041922Z` on BBQ, covering the 33 points of [runtime.toml](../experiments/configs/runtime.toml) with five repeats of the baseline, optimized, SPMF Eclat, and PrePost+ CLIs. All 660 outputs match SPMF Eclat exactly, and the run keeps every output.
- [scripts/output_size.jl](../scripts/output_size.jl) checks three properties and writes the count and itemset-length profile of every threshold:
  - all four programs report the same count at each threshold;
  - no count falls when minsup falls, as anti-monotonicity requires;
  - at each pair of adjacent thresholds, the itemsets of the lower output with support at least the higher count are exactly the higher output, with equal supports.
- [scripts/plot_output_size.py](../scripts/plot_output_size.py) fits log F = c - s log(minsup) by least squares over each dataset's thresholds. `output-growth.csv` also holds the fit's R², the slope between each pair of adjacent thresholds, and the slope of log F per 0.01 of minsup, which the report uses to show why the fit takes the log of minsup.

## Results

All 33 thresholds pass the three checks, including all 28 adjacent pairs.

| Dataset | Kind | minsup range | F at highest | F at lowest | Slope s | Longest itemset at lowest | Mean length, highest to lowest |
|---|---|---|---:|---:|---:|---:|---|
| Chess | dense | 0.9 to 0.6 | 622 | 254,944 | 14.33 | 14 | 3.80 to 7.37 |
| Accidents | dense | 0.95 to 0.65 | 15 | 1,093 | 11.28 | 8 | 2.13 to 4.00 |
| Mushroom | dense | 0.5 to 0.1 | 153 | 574,431 | 5.23 | 16 | 2.90 to 8.02 |
| Retail | sparse | 0.01 to 0.001 | 159 | 7,589 | 1.68 | 5 | 1.79 to 2.07 |
| T10I4D100K | sparse | 0.01 to 0.00025 | 385 | 96,959 | 1.55 | 11 | 1.03 to 3.10 |

Dense databases grow 3 to 9 times faster on the log-log scale than sparse ones, since their slopes of 5.23 to 14.33 against 1.55 to 1.68 give ratios from 5.23/1.68 to 14.33/1.55. They grow faster because their frequent itemsets are long and every frequent k-itemset brings 2^k - 1 frequent subsets. Mushroom grows 9.7 times between minsup 0.25 and 0.2, the step where its longest itemset goes from 11 to 15 items. On T10I4D100K 0.00025, 47% of the itemsets are pairs.

Output size does not set runtime alone. In the same run, the baseline takes 12.59 s on Retail 0.001 with 7,589 itemsets and 3.07 s on Chess 0.6 with 254,944, because Retail's 2,117 frequent items give over two million root intersections that mostly fail. The optimized CLI takes 0.41 s on Mushroom 0.1 with 574,431 itemsets and 0.96 s on T10I4D100K 0.00025 with 96,959.

## Reproduce

```sh
RUN=results/raw/bbq-all-variants-cli-5repeat-20261117T041922Z
OUT=results/figures/bbq-output-size-20261117
julia --startup-file=no --project=. scripts/output_size.jl $RUN --out $OUT
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_output_size.py \
  $OUT/output-size.csv --out $OUT
```

`output-size.csv` holds every threshold's count and length profile, and `output-growth.csv` holds the slopes. `docs/report/figures/output-size.pdf` is a copy of the figure.
