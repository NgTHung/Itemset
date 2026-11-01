# Eclat optimization plan, 2026-10-30

The baseline Eclat returns the same maps as SPMF, but on the [scored host](bbq-baseline-runtime-2026-10-31.md) it runs 2.2 to 12.8 times slower than SPMF PrePost+. Two costs explain the gap. Mining takes 51% to 81% of process time at each dataset's lowest threshold, and compilation adds a fixed 2.8 s to every cold run. This plan sets the order in which the team builds `:optimized`, the evidence each stage must produce, and the target that counts as reaching PrePost+.

The requirements are in [assignment.md](assignment.md). The plan follows the [public contract](interface.md), the [measurement protocol](../experiments/README.md), and the [SPMF procedure](../tools/spmf/README.md). Implementation is tracked in [DAT-17](https://linear.app/nguyen-tuan-hung/issue/DAT-17).

## Evidence

All measurements below ran on 2026-10-28 to 2026-10-30 at revisions `811eb0d` and `d5091b1`. The machine was Windows 11 (NT 10.0.26100), Intel Core i7-12700H, and 15.7 GiB RAM, running Julia 1.13.2 with one thread, SPMF v2.66, and Temurin 25.0.4.1. Each point ran once. The numbers choose the stage order. They do not replace the scored runs that Stage 1 defines.

The prototypes are throwaway scripts outside the repository. Each stage reimplements its technique test-first, so every author can explain the submitted code. Prototype outputs and the PrePost+ reference files are in `results/raw/` under the `proto-`, `ref-`, and `cold-` prefixes.

### Reference times

SPMF times are its internal "Total time", which includes reading the input and writing every pattern. They set the prototype targets below. Baseline times on the scored host are in the [baseline record](bbq-baseline-runtime-2026-10-31.md).

| Dataset / minsup | Itemsets | PrePost+ s | SPMF Eclat s |
|---|---:|---:|---:|
| Chess / 0.6 | 254,944 | 0.25 | 14.0 |
| Chess / 0.5 | 1,272,932 | 0.64 | 64.0 |
| Mushroom / 0.1 | 574,431 | 0.40 | 7.3 |
| Mushroom / 0.05 | 3,755,511 | 1.25 | 16.1 |
| Retail / 0.001 | 7,589 | 2.89 | 0.91 |
| T10I4D100K / 0.00025 | 96,959 | 4.20 | 7.69 |
| Accidents / 0.65 | 1,093 | 2.22 | 21.5 (pilot wall) |
| Accidents / 0.5 | 8,057 | 2.55 | 114.3 (pilot wall) |
| Accidents / 0.4 | 32,528 | 3.07 | not run |

PrePost+ wins on dense data. On Retail it is slower than SPMF Eclat, so the sparse target is easier than the dense one.

### Where the time goes after a fast kernel

A bitset kernel with items in increasing support order mines dense data faster than PrePost+ does the whole job, so the output path decides the total.

| Point | Kernel, count only s | Insert into `SupportMap` s | `print` to `IOBuffer` s |
|---|---:|---:|---:|
| Chess / 0.6 | 0.052 | 1.04 | 0.46 |
| Mushroom / 0.1 | 0.148 | 1.52 | 1.03 |
| Mushroom / 0.05 | 0.627 | 12.41 | 6.95 |

`SupportMap` costs this much because `Itemset = Tuple{Vararg{Int}}` is an abstract type, so every key is boxed and hashed through dynamic dispatch. A `Dict{Vector{Int},Int}` is not a fix: it took 11.04 s on Mushroom 0.05, because millions of small vectors load the garbage collector. Both variants therefore emit a packed result and write it with a byte writer, and `mine` builds the `SupportMap` only for applications.

Cold start sets a floor under every run. Loading `ItemsetMining` takes 0.35 s, and a cold `demo.jl` run on Chess 0.9 takes 2.36 s, mostly compilation. PrePost+ takes 0.55 s wall for the same point, including JVM start-up.

### Dense prototype

The dense prototype combines three techniques:
- bitset tidsets (`Vector{UInt64}` with AND and `count_ones`) in increasing-support order;
- perfect-extension pruning (defined in Stage 4);
- a packed result written by a byte writer.

Times are warm file-to-file, covering read, mine, pack, and write. All four outputs matched the PrePost+ maps exactly in `tools/spmf/compare.jl`.

| Point | Total s | Mine and pack s | Write s | PrePost+ s |
|---|---:|---:|---:|---:|
| Chess / 0.6 | 0.14 | 0.065 | 0.053 | 0.25 |
| Chess / 0.5 | 0.60 | 0.30 | 0.28 | 0.64 |
| Mushroom / 0.1 | 0.31 | 0.156 | 0.12 | 0.40 |
| Mushroom / 0.05 | 1.87 | 0.98 | 0.86 | 1.25 |

Perfect-extension pruning cut the count-only kernel on Mushroom 0.05 from 0.627 s to 0.040 s. What remains on that point is building each subset key and writing 3.76 million lines.

The same prototype run cold took 2.47 s on Chess 0.9, 2.51 s on Chess 0.6, and 4.23 s on Mushroom 0.05. PrePost+ took 0.55 s, 0.73 s, and 1.66 s wall on those points.

### Sparse prototype

The sparse prototype uses sorted tidsets with a two-pointer merge in increasing-support order. Early stop rejects a join once the matches found plus the shorter remaining list cannot reach the threshold. Pair counting is the paper's triangular count of 2-itemsets from the horizontal database. Times include reading the input.

| Point | Merge s | + early stop s | + pair counting s | Both s | Failed joins |
|---|---:|---:|---:|---:|---:|
| Retail / 0.001 | 6.93 | 3.58 | 0.63 | 0.66 | 99.8% |
| T10I4D100K / 0.00025 | 7.54 | 7.22 | 4.14 | 3.39 | 96% |
| Chess / 0.6 | 4.95 | 4.74 | 3.92 | 3.94 | 2% |
| Mushroom / 0.1 | 2.95 | 3.17 | 3.04 | 3.13 | 1% |

On Retail, pair counting removes nearly all failing root joins (2.24 million joins drop to 8,193), so early stop adds nothing after it. On T10I4D100K the failures happen below the root, and early stop saves about 20%. Applying the pair table at every depth changed T10I4D100K joins only from 2.37 to 2.33 million. On dense data almost every join succeeds, so neither technique helps. The bitset kernel mines Chess 0.6 in 0.052 s and Mushroom 0.1 in 0.148 s.

### Tidset representation by dataset

Three representations can hold a tidset. A bitset stores one bit per transaction, a sorted list stores the tids, and a diffset (Zaki and Gouda, 2003) stores the tids of P that lack X, so support(PX) = support(P) − |d(PX)|.

Each has a different cost per join. A bitset join reads all N/64 words, whatever the support, at about 0.48 ns per word. That is 2.56 µs for Accidents' 5,316 words and 54 ns for Chess's 50. A list or diffset join costs about 1.5 ns per element while the lists fit in cache, and 6.3 ns per element at 16,384 elements. A diffset kept for prefix P holds at most support(P) − minsup tids, because a longer one makes the extension infrequent. That bound is large at the root and small deep in the search, where support(P) approaches minsup. Pure diffsets therefore pay the most where the search starts, and a switch partway down avoids that cost.

The prototypes tested two switches. A dense class mines with bitsets and moves its children to diffsets when 2 × (support(P) − minsup) < ratio × N/64. A sparse class mines with sorted lists and moves its children to diffsets when their diffsets hold fewer tids in total than their tidsets. Every variant used perfect-extension pruning. The tables give the median mining time of five warm runs in one process, with the input read once.

| Point | Bitset s | Diffset s | Switch, ratio 0.31 s | Ratio 1 s | Ratio 3 s | Ratio 10 s |
|---|---:|---:|---:|---:|---:|---:|
| Chess / 0.6 | 0.069 | 0.086 | 0.069 | 0.066 | 0.067 | 0.067 |
| Chess / 0.5 | 0.494 | 0.498 | 0.513 | 0.467 | 0.469 | 0.529 |
| Mushroom / 0.1 | 0.206 | 0.366 | 0.269 | 0.243 | 0.276 | 0.242 |
| Mushroom / 0.05 | 1.328 | 1.790 | 1.072 | 1.453 | 1.330 | 1.213 |
| Accidents / 0.5 | 0.351 | 1.095 | 0.208 | 0.210 | 0.206 | 0.164 |
| Accidents / 0.3 | 2.819 | 6.453 | 3.140 | 2.671 | 2.361 | 2.374 |

| Point | Sorted list s | List with diffset switch s | Bitset s |
|---|---:|---:|---:|
| Retail / 0.0025 | 0.214 | 0.221 | 1.494 |
| Retail / 0.001 | 0.663 | 0.621 | 9.179 |
| T10I4D100K / 0.001 | 0.777 | 0.813 | 1.746 |
| T10I4D100K / 0.00025 | 3.743 | 3.059 | 12.855 |

The outputs of the ratio-3 dense switch at Chess 0.5, Mushroom 0.05, and Accidents 0.5, and of the sparse switch at all four sparse points, matched PrePost+ exactly.

The results split by dataset:
- Chess: the representation barely matters. Every switch setting stays within 7% of bitsets and pure diffsets cost up to 25% more, because a 50-word join costs 54 ns and output dominates the run.
- Mushroom: no switch setting wins reliably. Its times do not move monotonically with the ratio, so the 19% gain at ratio 0.31 on Mushroom 0.05 is within run-to-run noise.
- Accidents: the switch wins at every ratio from 1 up, by 1.7 to 2.1 times at 0.5 and 1.1 to 1.2 times at 0.3, because a full bitset join costs 2.56 µs.
- Retail and T10I4D100K: bitsets lose by 2.2 to 14 times, because a frequent item covers a small fraction of N, and sorted lists are the right base. The diffset switch fires often there, in deep classes whose children are almost as frequent as their parent, but it changes the time by −18% to +5%. Only T10I4D100K 0.00025 shows a clear gain.

One earlier sweep on Accidents (minsup 0.65 to 0.3, same machine) gave the switch 1.3 to 2.8 times at ratio 3. That run was 30% to 100% slower overall than the single runs before it, so these numbers compare only within one table. At the required Accidents points, prototype mining takes under 0.1 s. The switch matters for the stress series and for any lower threshold the optimized variant makes affordable.

## Decisions

1. Share the byte reader, the packed result, and the byte writer between both variants, so `:optimized` differs from the baseline only in how it mines.
2. Add a precompile workload to the package first, because compilation adds 2.8 s to every cold run and dominates every point below 5 s.
3. Mine dense data with bitsets in increasing-support order.
4. Add perfect-extension pruning, with a written proof and independent review, because it is the dense-data counterpart of PrePost+'s Children–Parent Equivalence pruning.
5. Mine sparse data with the baseline's sorted-list merge, plus pair counting at the root and early stop.
6. Choose the representation per class from tidset length and N, never from the dataset name.
7. Use diffsets only through a switch inside the search, never from the root. Pure diffsets lost or tied on every dense point. The bitset-to-diffset switch wins on Accidents (1.1 to 2.1 times) and is neutral on Chess and Mushroom. The list-to-diffset switch ranges from 18% faster to 5% slower on Retail and T10I4D100K. Both switches are the last step of the representation policy, and each is kept only if the scored points confirm its gain.
8. Keep the baseline unchanged as the control. Precompilation lives in the shared package, so Stages 3 to 5 use the [precompiled baseline](bbq-precompile-runtime-2026-11-01.md) as their control. Every stage compares `:optimized` against it and against SPMF on complete maps.

## Speed target

Use SPMF `PrePost+` from the pinned JAR as the speed comparator, and SPMF Eclat as the independent correctness reference. For each point, R is the median cold process wall time of `:optimized` divided by that of PrePost+. Both runs read the same file, write every pattern to a local file, and exit. Julia mines with one thread.

Reaching PrePost+ means:
1. Every scored run passes exact-map comparison, including duplicate detection.
2. Every required point finishes within the 300 s timeout. A failure stays in the results and is never replaced by an easier threshold.
3. Geometric mean R is at most 1.0 for each dataset.
4. R is at most 1.10 at every point where PrePost+ takes at least 1 s of wall time. Faster points are reported with R and the measured Julia start-up floor, because the floor alone can exceed half of PrePost+'s time there.
5. Peak RSS stays under 8 GiB per process and is reported next to time.

This bar is fixed before scoring. If the target is missed, the report states the per-point gap and the limiting phase. A several-fold improvement over the baseline is never relabeled as parity.

Warm in-process times of `mine` are a separate application-latency series. They include building the `SupportMap` that applications receive, and they are never compared with SPMF's internal time.

## Experiment matrix

Use the files and checksums in [the dataset manifest](../data/benchmark/manifest.toml) and the thresholds in [runtime.toml](../experiments/configs/runtime.toml).

| Dataset | Required relative minsup | Memory point | Development points | Stress points |
|---|---|---|---|---|
| Chess | 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6 | 0.75 | 0.75, 0.6 | 0.55, 0.5 |
| Mushroom | 0.5, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1 | 0.25 | 0.25, 0.1 | 0.05 |
| Retail | 0.01, 0.0075, 0.005, 0.0025, 0.0015, 0.001 | 0.0025 | 0.0025, 0.001 | 0.0005, 0.00025 |
| T10I4D100K | 0.01, 0.005, 0.0025, 0.001, 0.0005, 0.00025 | 0.001 | 0.001, 0.00025 | |
| Accidents | 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65 | 0.8 | 0.8, 0.65 | 0.6, 0.5, 0.4 |

The required grid has 33 points. Development uses the ten development points. The stress series uses a separately declared 900 s timeout, keeps failures in the charts, and never replaces a required point. Resolve the absolute count before every run, and only compare runs whose counts match.

## Stages

Each stage writes its failing tests first and lands as small commits on its own branch. It passes the full suite and exact SPMF comparison on the development points before the next stage starts. Complex diffs stay under 700 changed lines.

### Stage 1: Comparable measurements

Owners: Thien for the runner, Phat for output verification.

- Add a PrePost+ reference to the runner next to the existing `spmf` rows, in `experiments/references.jl`. It parses PrePost+'s stdout block (`Minsup =`, `Number of transactions:`, `Number of frequent  itemsets:`, `Total time ~:`).
- Add a cold mode with no benchmark-only warm-up, and a warm in-process mode for the application-latency series.
- Run `tools/spmf/compare.jl` on every successful output after timing ends, and record its result next to the timing row. A failed comparison invalidates the row.
- Add `accidents` and PrePost+ to the runtime config and record variant, stage, and correctness status in each row.
- Use five repeats per scored point and three per development screen. Report median, IQR, and every sample.

Acceptance: tests cover the PrePost+ parser, threshold disagreement, truncated output, and duplicate patterns. The baseline, SPMF Eclat, and PrePost+ runs on the development points are archived with exact-map results.

### Stage 2: Cold start

Owner: Hung, with Thien measuring.

Run `mine` and the packed writer on toy data at module top level, guarded by `ccall(:jl_generating_output, Cint, ()) == 1`, so the package image caches the compiled code. This needs only the standard library. Record cold Chess 0.9 time and package load time before and after.

### Stage 3: Dense kernel

Owner: Hung, with Phat checking boundaries.

- Store bitsets as owned `Vector{UInt64}` words with a cached support. Intersect with AND and `count_ones` in one loop.
- Order items by increasing support, breaking ties by item ID.
- Implement it in `src/algorithm/eclat_optimized.jl` and shared tidset helpers in `src/algorithm/tidsets.jl`.

Tests cover N = 0, 1, 63, 64, 65, 127, 128, and 129, masked trailing bits, parents left unchanged after child searches, and `Test.@inferred` on the join helpers. Add `:optimized` to the fixture, SPMF, and 300-case seeded oracle tests once it implements the whole contract.

### Stage 4: Perfect-extension pruning

Owner: Hung, with Phat's independent human review.

For a prefix P and a later item x, t(P ∪ {x}) is a subset of t(P). If their supports are equal, the two tidsets are equal. Then every frequent itemset P ∪ Y ∪ {x} has the same support as P ∪ Y, so x is never intersected again. Instead, P plus every subset of these perfect items is emitted with the support of P.

Write the coverage and uniqueness proof in [eclat.md](eclat.md) style before the code. Emit subsets straight into the packed result in Gray-code order, so each step adds or removes one item and the key is not rebuilt from scratch.

Tests: universal items, groups of equivalent items, siblings with equal support but different tidsets, nested equivalence, and threshold boundaries. Count attempted emissions as well as final keys, so a duplicate cannot hide behind a dictionary overwrite.

### Stage 5: Sparse kernel

Owner: Hung.

- Add early stop to the two-pointer merge. The bound h + min(rA, rB) < minsup rejects a join; reaching the threshold never stops a scan, because the exact support and the child tidset are both needed.
- Count frequent pairs with a triangular table over frequent-item ranks, sized and overflow-checked before allocation. Skip root joins whose pair count is below the threshold.
- Choose bitsets or sorted lists per class from tidset length and N. Storage crosses near k = N/64, and the measured runtime crossover sets the rule.
- Switch a bitset class's children to diffsets when 2 × (support(P) − minsup) falls below a ratio times N/64. Fix the ratio from a sweep on the Chess, Mushroom, and Accidents development and stress points before scoring.
- Test, as a separate ablation, a switch from list classes to diffsets when the children's diffsets hold fewer tids than their tidsets. Keep it only if Retail and T10I4D100K gain beyond run-to-run noise.
- For both switches, test that support stays exact across the switch, that a perfect extension is detected from an empty diffset, and that diffsets after the switch never reference the parent's tidset.

Acceptance: an ablation on Retail and T10I4D100K with each technique disabled on the same revision, and no regression above 10% on the dense development points.

## Survival rule

Keep a stage when it improves its targeted development points by at least 10%, causes no unexplained regression above 10% elsewhere, and raises peak RSS by no more than 20% without a recorded reason. Record the cumulative variants in stage order: baseline, then precompile, dense kernel, perfect extensions, and sparse kernel. Also run the final candidate with one accepted stage removed at a time.

For each stage, archive its hypothesis, commits, correctness result, median and IQR, allocation and GC time, peak RSS, output count, and join counts.

## Future directions for the report

The brief asks for at least two concrete next optimizations, based on the weaknesses the experiments find. The prototype measured two that fit the residual costs. Re-measure both on the final revision before they enter the report.

1. Compact results. Store each search node once, as a prefix, its set of perfect-extension items, and the shared support, instead of expanding every subset. This needs 111 times fewer records than the expanded itemsets on Mushroom 0.05 (33,819 against 3,755,511) and 51 times fewer on Mushroom 0.1, but only 2.6 to 3.4 times fewer on Chess. It helps applications and peak memory, not SPMF file output, which needs every itemset.
2. A block-count bound before sparse joins. Split the tids into B blocks and store each tidset's count per block. The sum over blocks of min(cA, cB) is an upper bound on the joined support. On T10I4D100K 0.00025 it rejects 58%, 77%, and 86% of failing joins for B = 64, 256, and 1,024, without merging. Its runtime is unmeasured. A failing merge scans about 358 tids on average, so B = 64 is the likely balance.

Parallel search over independent equivalence classes with `Threads.@spawn`, and ahead-of-time compilation with `juliac`, are reserve directions without measurements. If the diffset switch does not ship in `:optimized`, it becomes the third direction, backed by the per-dataset results above: a gain on Accidents, none on Chess and Mushroom, and a mixed result on the sparse datasets.

## Assignment experiments

Thien owns runtime and output-size curves through [DAT-19](https://linear.app/nguyen-tuan-hung/issue/DAT-19) and width experiments through [DAT-22](https://linear.app/nguyen-tuan-hung/issue/DAT-22). Phat owns exact benchmark comparisons through [DAT-32](https://linear.app/nguyen-tuan-hung/issue/DAT-32) and peak RSS through [DAT-20](https://linear.app/nguyen-tuan-hung/issue/DAT-20). Hung owns scalability through [DAT-21](https://linear.app/nguyen-tuan-hung/issue/DAT-21).

- Runtime: baseline, optimized, SPMF Eclat, and PrePost+ over the 33-point grid, with uncertainty, output counts, and failures.
- Memory: peak RSS at the five memory points, baseline against optimized, from five cold repeats.
- Scalability: Retail and Accidents nested subsets at 10%, 25%, 50%, 75%, and 100%, from one seeded permutation, with the count verified at every size.
- Width: seeded synthetic databases with N = 10,000, 100 items, and widths 5, 10, 20, 30, and 40, at a minsup frozen after a pilot.
- Applications: rerun the market-basket and image-pattern pipelines with `:optimized` after release.

Raw runs and figures stay in their ignored directories. A checksum-addressed evidence archive is linked from Linear. Human review is requested through [DAT-41](https://linear.app/nguyen-tuan-hung/issue/DAT-41), and agents do not mark it complete.

## Delivery order and stopping rule

Stage 1 comes first, because no claim counts without it. Stage 2 removes the start-up floor. Stages 3 and 4 close the dense gap, and Stage 5 closes the sparse gap. Stop when the correctness, speed, memory, and assignment gates pass. If the gates are not met, ship the best validated revision, report the measured gap, and decide separately whether further work is worth it.
