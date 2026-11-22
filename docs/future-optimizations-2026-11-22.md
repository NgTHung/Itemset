# Where the optimized Eclat spends its time, and two optimizations the evidence supports, 2026-11-22

The brief asks for at least two concrete next optimizations, based on the weaknesses the experiments find. Its two examples, an adaptive tid-list or bitset representation and early termination of intersections, are already part of `:optimized`. This record measures where the optimized variant spends its time, joins that to the scalability, memory, runtime, and width evidence, and proposes the two changes that evidence points to. It does not implement them.

## What the optimized variant already does

| Direction | State | Where |
|---|---|---|
| Adaptive tid-list or bitset representation | In `:optimized`. `prefer_lists` moves a class to tid lists when that costs less. | [eclat-optimized.md](eclat-optimized.md#tid-lists-below-the-root) |
| Early termination and join bounds | In `:optimized`. `intersect_lists!` stops when the tids found plus the shorter remainder cannot reach minsup, and `BlockCounts` rejects a join without merging. | [eclat-optimized.md](eclat-optimized.md#block-count-bound) |
| Diffsets | Probed and dropped. No ratio beats bitsets beyond noise. | [bbq-diffset-probe-2026-11-08.md](bbq-diffset-probe-2026-11-08.md) |
| Compact results | In `:optimized`. A node stores its perfect extensions once, and `expand_nodes` expands at the end. | [eclat-optimized.md](eclat-optimized.md#emission-order) |
| Parallel search over classes, ahead-of-time compilation | Reserve directions in the plan, with no measurement. | [eclat-optimization-plan-2026-10-30.md](eclat-optimization-plan-2026-10-30.md#future-directions-for-the-report) |

## Evidence

### Where the time goes

`scripts/stage_profile.jl` times the read, mine, and write stages of the CLI path (`read_transactions`, `mine_packed` with `:optimized`, `write_itemsets` to `devnull`) and samples the same passes with the profiler. Times are medians of 5 warm passes after one warm-up pass. The profiler groups samples by the innermost function of the package on the stack and drops idle threads. Layout is reading, item counts, the root bitsets, and the canonical check. Joins are bitset and list intersections, the bitset-to-list conversion, block counts, and the search glue. Output is expanding the nodes, sorting, and formatting.

| Point | Itemsets | Pass s | Read | Mine | Write | Layout | Pair counts | Joins | Output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| chess 0.6 | 254,944 | 0.073 | 2% | 40% | 59% | 3% | 0% | 9% | 88% |
| mushroom 0.1 | 574,431 | 0.143 | 1% | 22% | 76% | 3% | 0% | 0% | 96% |
| mushroom 0.05 | 3,755,511 | 0.924 | 0% | 14% | 86% | 1% | 0% | 0% | 98% |
| retail 0.01 | 159 | 0.048 | 42% | 57% | 0% | 99% | 0% | 1% | 0% |
| retail 0.001 | 7,589 | 0.168 | 12% | 87% | 1% | 47% | 44% | 3% | 6% |
| T10I4D100K 0.01 | 385 | 0.080 | 27% | 73% | 0% | 64% | 36% | 0% | 0% |
| T10I4D100K 0.00025 | 96,959 | 0.613 | 3% | 94% | 3% | 10% | 7% | 78% | 5% |
| accidents 0.95 | 15 | 0.391 | 53% | 47% | 0% | 99% | 0% | 0% | 0% |
| accidents 0.65 | 1,093 | 0.524 | 50% | 50% | 0% | 99% | 0% | 0% | 0% |

Read, Mine, and Write are shares of the timed pass. The last four columns are shares of the profiler samples, which cost time of their own, so the two views differ by a few points. Chess 0.9 and Mushroom 0.5 take 3 to 4 ms, too short to sample. Their 0.21 s on BBQ is process start-up.

Intersections, the core operation of Eclat, dominate at one point, T10I4D100K 0.00025. Output dominates the three dense points, and building the vertical layout and counting pairs dominates the other five. At Accidents the search takes under 1% of the pass.

### Scalability

Hung's BBQ run of the four contenders on nested subsets of Accidents and Retail (`docs/bbq-scalability-runtime-2026-11-19.md` on branch `dat-21-scalability`, DAT-21) fits time as `a + bN`, with R² of at least 0.992. On Accidents the optimized CLI has `a = 0.188 s` and `b = 0.195 s` per 100,000 transactions, against 0.544 for PrePost+, 1.896 for the baseline, and 8.015 for SPMF Eclat. The output stays near 1,100 itemsets at every size, so the slope is the cost of reading and laying out the database. On Retail `b` is 0.182 for the optimized CLI, 0.685 for SPMF Eclat, and 3.510 for PrePost+.

### Output size

Hung's count record (`docs/output-size-2026-11-19.md` on branch `dat-31-output-size`, DAT-31) reads the counts from the same cohort as the runtime record, run `bbq-all-variants-cli-5repeat-20261117T041922Z`, and checks that all four programs report the same count at all 33 thresholds. Its times for Retail 0.001 (baseline 12.59 s), Chess 0.6 (baseline 3.07 s), Mushroom 0.1 (optimized 0.41 s), and T10I4D100K 0.00025 (optimized 0.96 s) equal the ones in this record, so the two analyses cross-check each other. The dense datasets end at long itemsets. The mean length at the lowest minsup is 8.02 on Mushroom, 7.37 on Chess, and 4.00 on Accidents, against 2.07 on Retail and 3.10 on T10I4D100K, and the count grows 5 to 14 times faster on the log-log scale on the dense datasets (slopes 5.23 to 14.33 against 1.55 to 1.68). The bytes the CLI formats grow with the count times the length, so the dense points are where output is the largest cost.

### Memory

Phat's median peak RSS of five CLI runs (DAT-20, report text in PR #39, Windows) is 149.0 to 181.7 MiB for the optimized variant on Chess, Mushroom, Retail, and T10I4D100K, and 313.4 MiB on Accidents, which is 34.7% below the baseline's 479.6 MiB. The Accidents excess of 131 to 164 MiB over the other points is of the order of its input database, which `Base.summarysize` puts at 105 MiB as `Vector{Vector{Int}}` and which Hung's I/O record shows the reader allocating as 151 MiB. The Retail and T10I4D100K databases take 11 and 12 MiB. Hung's [diffset probe](bbq-diffset-probe-2026-11-08.md) reaches the same conclusion on BBQ: the tidsets alive during the search peak at 4.6 MiB while the input database takes 211 MiB. Phat's first verification run could not verify 11 comparisons because the JVM ran out of memory and one because Julia did, at Retail 1% and five Accidents thresholds. She reran all 12 against stored SPMF 2.66 outputs.

### Runtime and width

At matched output, the optimized mining time grows 1.8 times from width 5 to 40 while the baseline's grows 53 times ([width record](width-runtime-2026-11-11.md)). Across the 33 required points the optimized CLI is fastest at every point, between 7.9 and 33.3 times faster than the baseline at the lowest minsup of each dataset (`docs/runtime-curves-2026-11-17.md`, DAT-19). Every run behind these numbers matches an independent SPMF Eclat run exactly, which is Phat's correctness evidence (DAT-32).

## Strengths and weaknesses against SPMF

The comparison rests on measured behavior. This record does not inspect SPMF's source, so it names no cause inside SPMF.

- Per-transaction cost. The optimized slope on Accidents is 41 times below SPMF Eclat's and 2.8 times below PrePost+'s. SPMF Eclat is the one superlinear series: it grows 12.35 times for 10 times the data.
- Start-up. The optimized intercept of 0.19 to 0.22 s is Julia start-up and package load. It is below the 0.48 to 0.52 s of PrePost+ and the 1.0 s of SPMF Eclat on Retail. SPMF Eclat's intercept on Accidents is negative, because its series bends upward, so it says nothing about start-up.
- Width. The bitset join costs 157 words at every width of the synthetic databases, so mining grows 1.8 times, while SPMF Eclat's cold time grows 21 times over the same widths.
- Work that is Eclat's own. At Retail 0.001 the baseline merges 2.17 billion tid-list elements and takes 12.59 s, while SPMF Eclat takes 1.57 s. The optimized variant avoids most of that work with pair counts and tid lists and takes 0.38 s.
- Output. At Mushroom 0.05, the only required or stress point where PrePost+ is faster, the optimized CLI takes 1.445 s against 1.378 s ([BBQ record](bbq-io-emission-runtime-2026-11-09.md)). The profile puts 98% of that pass in output, and the sort alone is 32% of the samples. SPMF writes its output in mining order, so the CLI does a sort that the SPMF programs do not.
- Memory. Phat measured peak RSS for the baseline and the optimized variant only, so no number compares our memory with SPMF's. Her first verification run lost 12 comparisons to out-of-memory failures at the Accidents and Retail 1% points. That shows memory pressure there, and it does not say which program needs more.

## Proposal 1: a flat integer store and an array-indexed vertical layout

Bottleneck. Layout is 99% of the pass at Accidents 0.95 and 0.65 and at Retail 0.01, 64% at T10I4D100K 0.01, and 47% at Retail 0.001. It is also what Hung's slope and Phat's Accidents peak RSS measure. `count_items` hashes every item occurrence into a `Dict{Int,Int}`, `bitset_tidsets` looks every occurrence up in a second `Dict`, `read_transactions` allocates one `Vector{Int}` per transaction at 8 bytes per item, and `canonical_database` scans each transaction again.

Change. Read the database into one flat vector of `Int32` items and an offsets vector, count items in an array indexed by item ID, map frequent items to ranks in an array, and set the bitset bits from that array. IDs above an array bound take the current `Dict` path. The search, the item order, and the bitsets stay the same, and `mine(transactions)` keeps its contract for the applications. Only the CLI path reads into the flat store.

Expected benefit. A scratch prototype (see Reproduce) replaces the two `Dict` passes over the same `Vector{Vector{Int}}` with array lookups:

| Point | `count_items` + `bitset_tidsets` s | Array-indexed s | Faster | Share of the pass saved |
|---|---:|---:|---:|---:|
| accidents 0.65 | 0.177 | 0.062 | 2.9 times | 22% |
| retail 0.001 | 0.051 | 0.034 | 1.5 times | 10% |
| T10I4D100K 0.00025 | 0.030 | 0.021 | 1.4 times | 1% |

Each time is the median of three runs of the snippet in Reproduce, whose runs differ by at most 0.012 s. At Accidents 0.95 the same 0.115 s is 29% of the pass. The prediction for Hung's scalability run is a slope `b` about 22% lower on Accidents, near 0.15 s per 100,000 transactions, and no change on the join-bound points. For memory, the Accidents database takes 105 MiB as `Vector{Vector{Int}}`, 46 MiB as flat `Int32`, and 23 MiB as `UInt16`, since its largest ID is 468. That is 59 to 82 MiB of the 313.4 MiB peak RSS, or 19% to 26%. The prototype leaves out the saving from reading into the flat store, which is unmeasured.

Tradeoff. The CLI gains a second reading path and a second layout builder next to the generic ones, which duplicates logic that must stay equivalent. An array indexed by ID needs a bound, because SPMF files allow large sparse IDs, so the `Dict` fallback stays. The canonical check moves into the parser. More code is more to explain at the oral defense.

Test.
1. Unit test that the flat layout equals `bitset_class` on seeded databases, including N of 63, 64, and 65, an ID of 0, and IDs above the array bound.
2. The CLI output of the new path is byte-identical to the current output at all 33 required points, and `tools/spmf/compare.jl` matches the complete map against SPMF.
3. Rerun `scripts/stage_profile.jl` before and after for the layout share and seconds. Rerun Hung's scalability config for `b`, and Phat's peak RSS harness for the five memory points, predicting 231 to 254 MiB on Accidents.
4. Keep the change if it meets the plan's survival rule: at least 10% on its targeted points, no unexplained regression above 10%, and peak RSS up by at most 20%.

## Proposal 2: an output order that follows the search

Bottleneck. At Chess 0.6, Mushroom 0.1, and Mushroom 0.05, output is 88% to 98% of the samples, and the lexicographic sort is 31% to 34%. On BBQ the sort of Mushroom 0.05 takes 0.30 s of the 1.445 s CLI run, and printing in storage order costs 0.18 s less than printing in sorted order ([BBQ I/O record](bbq-io-pass-2026-11-09.md)). A hand-written radix sort gained 10%, which Hung judged too little for the code. The contract fixes the file order so that outputs are byte-comparable across variants and runs, while the order of itemsets in a result is unspecified (`docs/interface.md`).

Change. `write_itemsets(path, packed; order=:search)` and `demo.jl --order search` write the packed itemsets in storage order and skip `lexicographic_order`. The default stays lexicographic, and the search and the `SupportMap` do not change.

Expected benefit. At Mushroom 0.05 the CLI falls from 1.445 s to between 1.15 s (the sort alone) and 0.97 s (the sort and the out-of-order reads), so R against PrePost+ falls from 1.05 to between 0.83 and 0.70. The profile predicts 31% to 34% of the pass at Chess 0.6 and Mushroom 0.1. Sparse points have no output to sort, so they do not change.

Tradeoff. A file written in search order is not byte-comparable across variants or runs of different code. The comparator parses both files into maps, so it is unaffected. The scored cohort has to record the order it used, because the CLI time then excludes a sort, as the times of the SPMF programs do. The team must decide whether the scored CLI uses the default or the search order.

Test.
1. A search-order file, sorted externally, equals the default output byte for byte.
2. `tools/spmf/compare.jl` matches the complete map against SPMF at all 33 required points and the stress points.
3. Two runs of the same code write identical bytes in search order.
4. A cohort with five repeats of both orders on Chess 0.5, Mushroom 0.1, and Mushroom 0.05. The prediction fails if R at Mushroom 0.05 stays at or above 1.0.

## Directions not proposed

- Adaptive representation and early termination exist already, and the profile shows intersections dominating only at T10I4D100K 0.00025, where the conversion from bitsets to lists is 16% of the samples next to 50% for the two kinds of join.
- Diffsets lost or tied on every point of the probe, and perfect-extension pruning removes the members where they save most.
- Parallel search over equivalence classes has no measurement of how work spreads over the root classes, so the evidence here neither supports nor rules it out.

## To confirm with Hung

These claims rest on reading the code and the records. Hung has not confirmed them.

1. `count_items` and `bitset_tidsets` still hash through a `Dict` on every unmerged branch, and no work in progress replaces them.
2. The sort is `lexicographic_order` only for byte-comparable output, and no consumer other than the comparison scripts reads the file order.
3. Skipping the sort was not considered and rejected on grounds other than the contract.
4. SPMF input IDs can be large and sparse, so an array indexed by ID needs the fallback described.
5. The peak RSS of Accidents above the other points is the input database, as the diffset probe says, and no other structure of that size is alive during the search.

## Reproduce

Run from the repository root at the revision of the PR that adds `scripts/stage_profile.jl`, on a machine that is otherwise idle.

```sh
julia --startup-file=no --project=. scripts/stage_profile.jl --out results/raw/stage-profile-20261122 \
  --repeats 5 experiments/configs/stage-profile.toml
```

The profile ran on a Windows 11 laptop with an AMD Ryzen 7 H 260, 16 logical CPUs, 31.3 GiB, and Julia 1.13.2 with one thread, on package revision `8974798`. Its `stage-profile.csv` has SHA-256 `d3220a11bf865d55653fcd6a10e55eafb67936b5269e7550cb89d428c21657b1`. Git ignores the folder. A rerun gives different seconds and the same shares within sampling noise.

The prototype times the two layout steps and an array-indexed version over the same database. It calls internal functions, so it stays out of the repository's experiments:

```julia
using ItemsetMining, Statistics
med(f) = (f(); median([(@elapsed f()) for _ in 1:5]))

function layout_array(db, minsup)
    maxitem = maximum(maximum, filter(!isempty, db))
    counts = zeros(Int32, maxitem + 1)
    for t in db, x in t
        counts[x + 1] += 1
    end
    frequent = [x for x in 0:maxitem if counts[x + 1] >= minsup]
    sort!(frequent; by=x -> (counts[x + 1], x))
    rank = zeros(Int32, maxitem + 1)
    for (k, x) in enumerate(frequent)
        rank[x + 1] = k
    end
    sets = [zeros(UInt64, cld(length(db), 64)) for _ in frequent]
    for (tid, t) in enumerate(db)
        word, bit = divrem(tid - 1, 64)
        for x in t
            k = rank[x + 1]
            k == 0 || (sets[k][word + 1] |= UInt64(1) << bit)
        end
    end
    return sets
end

dataset, relative = ARGS[1], parse(Float64, ARGS[2])
db = read_transactions("data/benchmark/$dataset.txt")
minsup = support_threshold(relative, length(db))
items = first.(ItemsetMining.frequent_items_by_support(db, minsup))
current = med(() -> ItemsetMining.count_items(db)) + med(() -> ItemsetMining.bitset_tidsets(db, items))
array = med(() -> layout_array(db, minsup))
println(dataset, " ", relative, ": current ", round(current; digits=3), " s, array ", round(array; digits=3),
        " s, database ", round(Base.summarysize(db) / 2^20), " MiB")
```

Run it as `julia --startup-file=no --project=. proto.jl accidents 0.65`.

## Limits

- The profile is warm and in-process on one Windows machine, not a scored BBQ cohort. It shows shares of time, which BBQ numbers from Hung's records support at the points they share. A BBQ rerun would replace the seconds.
- The profile samples the CLI path of the optimized variant only. It does not cover the `SupportMap` that applications receive.
- The prototype changes only the two layout passes, so its saving is a lower bound on proposal 1 and no measurement of reading into a flat store.
- The expected benefits are predictions with the tests above as their checks. None is implemented.
- Hung's scalability and count results (branches `dat-21-scalability` and `dat-31-output-size`) and Phat's memory and correctness results (PR #39) are not on `main` when this record is written. The record cites them by name and file.
