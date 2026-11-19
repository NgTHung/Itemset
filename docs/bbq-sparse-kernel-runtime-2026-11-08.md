# BBQ sparse-kernel runtime, 2026-11-08

After the [precompiled CLI](bbq-precompiled-cli-runtime-2026-11-06.md), Retail and T10I4D100K spent most of each run in bitset joins: 91% of a warm Retail 0.001 profile was in `intersect_bitsets!`. This record measures the two parts of plan Stage 5 that the [optimized variant](eclat-optimized.md) keeps, root pair counts and tid lists below the root, against the precompiled CLI and PrePost+ in one session.

## Where the joins went

A join count on the precompiled-CLI revision found two different patterns:

| Point | Joins at the root | Root failure rate | Joins at depth 2 | Depth-2 failure rate | Mean child support |
|---|---:|---:|---:|---:|---:|
| Retail 0.001 | 2,239,786 | 99.9% | 4,236 | 57.6% | 199 |
| T10I4D100K 0.00025 | 365,940 | 87.5% | 2,256,822 | 99.1% | 104 |
| T10I4D100K 0.001 | 317,206 | 97.2% | 65,118 | 89.1% | 213 |

Each bitset join reads ⌈N/64⌉ words: 1,378 on Retail and 1,563 on T10I4D100K. Root pair counts remove the failing root joins. Tid lists make the short depth-2 tidsets of T10I4D100K 0.00025 cheaper to join.

## Tuning the list rule

A first full run on 2026-11-06, `bbq-sparse-kernel-cli-20261106T142755Z`, switched a class to lists when its mean support was below ⌈N/64⌉/16. It cut T10I4D100K 0.00025 by 15% but slowed Retail 0.00025 by 12%. At that ratio the switched classes on Retail made 2.4 joins per child, against 50 on T10I4D100K 0.00025, so converting each child from a bitset cost about what its joins saved. The rule now counts that conversion, as described in [eclat-optimized.md](eclat-optimized.md#tid-lists-below-the-root), and a warm BBQ sweep set its list cost to 8 words per merge step. This record measures that rule.

## Method

- Required grid: run `bbq-sparse-kernel-cli-20261108T085523Z`, 2026-11-08T08:58:30Z to 09:22:48Z, covering the 33 points in [runtime.toml](../experiments/configs/runtime.toml) with five repeats.
- Stress series: run `bbq-sparse-kernel-stress-cli-20261108T085523Z`, 09:26:14Z to 09:29:55Z, covering Retail 0.0005 and 0.00025 with five repeats and a 900 s timeout.
- Both runs time three revisions of the `demo.jl` CLI with `--variant optimized`: `precompiled-cli` at `a50f0f0`, `pair-counts` at `0a9199e`, and `sparse-lists` at `006627a`, which adds tid lists to the pair counts. PrePost+ runs once per repeat, and the revision order reverses on every other repeat.
- Each step's ratio divides its median process time by that of the revision before it. R is the `sparse-lists` median divided by PrePost+'s.
- Every output is compared with a separate SPMF Eclat run after timing ends. The controller checks the fixed 2.3 GHz clock at both ends.
- A VS Code server and a second login were active on the host during the run. The candidate's largest IQR is 3.9% of its median, and PrePost+'s is 19.8% (T10I4D100K 0.0025).

## Results

All 660 required outputs and all 40 stress outputs match SPMF Eclat exactly, with no failures or timeouts. Both audits pass, and all evidence files match their recorded SHA-256 after transfer.

| Measure | Pair counts / precompiled CLI | Sparse lists / pair counts |
|---|---|---|
| Ratio over the 33 required points | 0.244 to 1.011 | 0.830 to 1.017 |
| Geometric mean, Retail | 0.665 | 1.002 |
| Geometric mean, T10I4D100K | 0.835 | 0.974 |
| Geometric mean, Chess, Mushroom, Accidents | 0.999 to 1.003 | 0.993 to 1.009 |
| Retail stress, 0.0005 and 0.00025 | 0.084 and 0.040 | 0.998 and 1.010 |
| Peak RSS ratio | 1.00 to 1.03; stress 1.10 and 1.20 | 1.00 to 1.01 |

| Point | Itemsets | Precompiled CLI s | Pair counts s | Sparse lists s | PrePost+ s | R |
|---|---:|---:|---:|---:|---:|---:|
| Retail 0.0025 | 1,882 | 0.457 | 0.356 | 0.359 | 1.913 | 0.19 |
| Retail 0.001 | 7,589 | 1.720 | 0.420 | 0.417 | 3.531 | 0.12 |
| Retail 0.0005 | 19,242 | 5.792 | 0.486 | 0.485 | 5.088 | 0.10 |
| Retail 0.00025 | 47,448 | 14.551 | 0.587 | 0.592 | 5.573 | 0.11 |
| T10I4D100K 0.001 | 27,532 | 0.568 | 0.420 | 0.422 | 1.921 | 0.22 |
| T10I4D100K 0.0005 | 53,385 | 0.745 | 0.582 | 0.590 | 2.496 | 0.24 |
| T10I4D100K 0.00025 | 96,959 | 1.653 | 1.463 | 1.214 | 4.310 | 0.28 |

Both steps pass the [survival rule](eclat-optimization-plan-2026-10-30.md#survival-rule). Pair counts cut their targeted points by 22% to 76% on Retail and by 26% on T10I4D100K 0.001, and up to 96% at the Retail stress points. Tid lists cut T10I4D100K 0.00025, the one point with many short depth-2 tidsets, by 17%. Neither step moves another point by more than 1.7%. Pair counts raise peak RSS by 20% on Retail 0.00025, from 333 MiB to 400 MiB, because the triangular table for its 5,918 frequent items holds 17,508,403 counts, or 67 MiB.

The optimized CLI is faster than PrePost+ at every required point, with R from 0.12 to 0.76. Geometric mean R is 0.22 on Retail, 0.24 on T10I4D100K, 0.52 on Mushroom, 0.53 on Chess, and 0.54 on Accidents. On Retail and T10I4D100K, R stops falling at the lowest thresholds because each CLI run is now mostly fixed cost: Retail 0.001 takes 0.42 s, of which Julia start-up and loading the package take 0.19 s.

The [pair-count figure](../results/figures/bbq-pair-counts-cli-20261108/comparison.png), the [tid-list figure](../results/figures/bbq-sparse-lists-cli-20261108/comparison.png), and the [stress figure](../results/figures/bbq-sparse-kernel-stress-cli-20261108/comparison.png) show every point with median and IQR. Raw rows are in `results/raw/` under the two run names. The archive SHA-256s are `a158d83bc6df70c8d3a403f3a6fcd52020b81604dd9d240c5a565bbfe6b86dc9` for the required grid and `c02e417bca0ee49aa948cfc42d8cf89198a80cab1b1f324ec6d1c75e0993279b` for the stress series. Regenerate a figure with:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/compare_runs.py \
  "Pair counts=results/raw/bbq-sparse-kernel-cli-20261108T085523Z:optimized@pair-counts" \
  "Sparse lists=results/raw/bbq-sparse-kernel-cli-20261108T085523Z:optimized@sparse-lists" \
  "SPMF PrePost+=results/raw/bbq-sparse-kernel-cli-20261108T085523Z:prepost" \
  --out results/figures/bbq-sparse-lists-cli-20261108
```
