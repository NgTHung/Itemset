# Eclat optimization plan, 2026-10-28

Eclat needs lower intersection and allocation costs to approach PrePost+ speed while returning every frequent itemset with its exact support. This plan gives the team an experiment sequence, acceptance gates, and reproducible measurements for that goal. Each optimization earns its place through complete-map correctness and measured improvement on both dense and sparse data.

## Scope and evidence

The requirements are in [assignment.md](assignment.md); this checkout has no `docs/requirement` path. The plan follows the [public contract](interface.md), [measurement protocol](../experiments/README.md), and [SPMF procedure](../tools/spmf/README.md). PrePost+ parity is an additional project target, beyond the assignment's requirement for a measured optimization.

The required evidence includes at least five correctness databases, four benchmark datasets, 5–7 support thresholds per dataset, runtime and output-size curves, peak memory at middle thresholds, nested-size scalability, transaction-width experiments, and two evidence-based future proposals. Both applications continue to call the team's Eclat implementation. Returning only closed or maximal patterns, imposing a length cap, or substituting PrePost+ or dEclat would violate this scope.

Repository inspection used commit `42850b5412eb2391754b754970aff85f8aa92ab1`:

- `src/algorithm/eclat.jl` implements only `:baseline`; `:optimized` explicitly throws.
- `bottom_up!` copies `class[i+1:end]`, allocates each intersection through `∩`, and allocates a child class per extension. Their relative costs require profiling.
- `to_class` builds all singleton tid-lists before filtering infrequent items. `mine` canonicalizes input on every call, which belongs in public-API timings.
- `tests/eclat.jl` exercises the baseline against fixtures, committed SPMF outputs, and 300 seeded random databases through the brute-force oracle. Extend this suite instead of creating another correctness framework.
- The experiment runner already records process time, Julia read/mine/write phases, allocations, GC time, peak RSS, checksums, errors, and timeouts. Its `spmf` command and statistics parser are specific to Eclat.
- The runtime config disables output retention. Its output-count check is useful but does not establish equality with a reference map.
- The local JAR matches the documented SPMF 2.66 SHA-256. Portable Temurin 25.0.4.1 runs it; `java` on PATH is version 21 and must not be used for these runs.
- A fresh PrePost+ smoke run on `baskets.txt` at 0.5 returned six patterns and minimum count 2. The existing comparator found 100% exact-map agreement with the committed SPMF Eclat output. This verifies the executable and format on one fixture, not benchmark performance.
- The full repository suite passed 751/751 tests in 50.5 seconds during this planning run, using Julia 1.13.2 on Windows. This validates the existing code, not the proposed optimizations.

### Existing measurements

The [2026-10-22 pilot](threshold-pilot-2026-10-22.md) measured the baseline at `0acb443` on Windows 11, Ryzen 7 H 260, Julia 1.13.2, one Julia thread, and Temurin 25.0.4.1. These are historical single-repeat process measurements, not fresh measurements of the inspected revision or PrePost+.

| Dataset / minsup | Output count | Baseline seconds | SPMF Eclat seconds | Baseline/reference ratio |
|---|---:|---:|---:|---:|
| Chess / 0.6 | 254,944 | 91.3 | 14.4 | 6.3 |
| Mushroom / 0.1 | 574,431 | 80.2 | 3.9 | 20.6 |
| Retail / 0.001 | 7,589 | 102.5 | 1.4 | 73.2 |
| T10I4D100K / 0.00025 | 96,959 | 86.9 | 8.2 | 10.6 |

Ratios above use the rounded displayed times. The pilot's prose summarizes the gap as 6–71 times; retain raw precision when regenerating summaries. The raw run archive is not present in this checkout, so these numbers are context for choosing experiments. They are not a validated baseline for a speedup claim. In particular, none measures the gap to PrePost+.

## Define the speed target before tuning

Use SPMF `PrePost+` from the pinned JAR as the executable comparator. The [SPMF documentation](https://www.philippe-fournier-viger.com/spmf/documentation_218.php) identifies its command and all-frequent-itemset output. Keep SPMF Eclat as the independent correctness reference and a second speed comparison.

For each dataset/threshold point, let R be median optimized time divided by median PrePost+ time, using the same timing scope. R below 1 means optimized Eclat is faster. The proposed operational definition of reaching PrePost+ level is:

1. Every scored run passes exact-map comparison, including supports and duplicate detection.
2. Every required point completes within the fixed resource budget. No omitted failures or replacement with easier thresholds after tuning.
3. Geometric mean R is at most 1.0 for each dataset, and R is at most 1.10 at every required point. The 10% allowance is a declared engineering tolerance, not a statistical claim of equality.
4. Report uncertainty alongside each R. An interval crossing a decision boundary makes that point inconclusive; run additional predeclared repeats before claiming success.
5. Show peak RSS separately. Meet an initial 8 GiB per-process ceiling, subject to host qualification before any scored run. A speed win with unacceptable memory growth is not an accepted implementation.

The headline comparison uses cold file-to-file process time: launch the executable, read the identical file, mine, write every pattern and support to a real local file, and exit. Use one Julia mining thread; record JVM GC/JIT settings and worker-thread behavior. This is a single mining-thread comparison, not a claim that either runtime has only one OS thread.

Julia's public `mine` time and SPMF's reported internal time are diagnostic series with different boundaries. Do not use their ratio to certify parity. A second warmed comparison may be added only after both sides have documented equivalent work and warmup; otherwise report the asymmetry. For application latency, report warmed `mine` separately because callers receive a complete `SupportMap`.

PrePost+ uses N-lists and Children–Parent Equivalence pruning, so lower allocation alone may not close the gap on dense data ([Deng and Lv, 2015](https://www.philippe-fournier-viger.com/spmf/prepost%2B.pdf)). The stages below investigate representation and redundant search while retaining Eclat's vertical intersections. Parity is an experimental goal, not a promised result.

## Freeze the experiment matrix

Use the exact files and checksums in [the dataset manifest](../data/benchmark/manifest.toml), including its Mushroom copy and positive-ID Retail/T10I4D100K encodings. Do not substitute a similarly named download.

| Dataset | Required relative minsup values | Middle point for memory |
|---|---|---|
| Chess | 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6 | 0.75 |
| Mushroom | 0.5, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1 | 0.25 |
| Retail | 0.01, 0.0075, 0.005, 0.0025, 0.0015, 0.001 | 0.0025 |
| T10I4D100K | 0.01, 0.005, 0.0025, 0.001, 0.0005, 0.00025 | 0.001 |

Use these 26 existing points as the final evaluation grid. For rapid development, use the four middle points plus one harder point from each dataset: Chess 0.6, Mushroom 0.1, Retail 0.001, and T10I4D100K 0.00025. Reserve the remaining points for release evaluation; record any tuning after looking at them.

After the required grid, test Chess 0.55 and 0.5, Mushroom 0.05, and Retail 0.0005 and 0.00025 as a separate stress series. These include historical baseline timeouts. Preserve failures in the charts and do not let stress results replace the required grid.

Resolve an absolute support count before every run. Test the threshold conversion of PrePost+ itself rather than assuming it matches SPMF Eclat. Include boundary cases such as 0.07 of 100 transactions. Only compare matching counts; never change the package's decimal threshold semantics to fit a reference. Check counts again on scalability subsets.

Use a 300-second per-attempt timeout on the required grid and a separately declared 900-second stress limit. Specify and test how the chosen OS enforces the memory limit; the existing measurement wrapper observes RSS but does not enforce an RSS ceiling. Mark timeout, memory-limit, error, and skipped outcomes distinctly. Do not treat a skipped point as a measured timeout or use a timeout duration as a completed runtime.

## Stage 1: Establish comparable measurements

Owner: Thien for the runner and runtime protocol; Hung for baseline profiling; Phat for output verification. Estimate: 1–2 person-days, plus benchmark execution.

Extend the existing runner instead of creating a parallel benchmark system:

- Add a separate PrePost+ reference identity while preserving the meaning of historical `spmf` rows. Put reference command/statistics handling in `experiments/references.jl` and test it in `tests/harness.jl` or a focused new test file.
- Parse real PrePost+ stdout. The smoke run prints `Minsup =`, `Number of transactions:`, `Number of frequent  itemsets:`, and `Total time ~:`. The Eclat parser cannot read this block unchanged.
- Add a genuine cold execution mode with no benchmark-only toy warmup. Retain existing worker measurements under their explicit historical scope. The current process measurement includes its toy warmup and is not the same workload as the normal CLI.
- Add warmed Julia measurement as a separate mode. Warm the actual dataset/threshold and relevant representation paths, release warmup results, and collect measured calls in the same process. Record compilation time where supported, and isolate warmup memory from any cold-process peak claim.
- Connect successful outputs to the existing exact comparator after timing ends. Keep output files until comparison completes. Record reference digest, comparison status, and missing/extra/duplicate/support-error counts separately from execution status. A verification error invalidates a performance claim.
- Extend the schema with algorithm identity, stage/ablation identity, correctness status, memory limit, and relevant warmup details. Preserve raw process, phase, allocation, and GC fields. Do not compare order-dependent output hashes as if they establish map equality.

Run all variants serially on one qualified machine. Pin Julia/JAR/JRE versions, commits, input checksums, power mode, Julia threads, JVM options, OS, CPU, RAM, and seed. Record background load and thermal throttling; do not collect timing concurrently with tests, downloads, or profiling.

Use five measured repeats per final point, with a seeded randomized variant order inside each repeat block. Use at least three repeats for development screens. Report median, IQR, all samples, and the ratio of medians. For borderline conclusions, extend all contenders at that point to ten repeats and compute a seeded bootstrap interval; five-sample intervals are exploratory. Never discard a slow sample without a documented run fault and a retained record.

The main grid is 26 points × 4 contenders × 5 repeats = 520 process attempts. At 300 seconds each, its execution ceiling is about 43.3 hours before setup and verification, so development uses the smaller screen. Successful runs should take less; schedule from the first measured batch rather than assuming a fixed wall-clock duration.

Acceptance: tests cover both reference adapters, threshold disagreement, missing/truncated output, duplicate patterns, timeout records, and unchanged historical row meanings. Run baseline, SPMF Eclat, and PrePost+ on the development screen and archive exact-map evidence. Establish the actual PrePost+ gap before selecting the next stage.

## Stage 2: Locate the cost and build sorted joins

Owner: Hung; correctness checks with Phat. Estimate: 1–2 person-days.

First profile unmodified baseline runs with Julia's standard-library `Profile` tools and `@timed`, in separate diagnostic executions. Record input normalization, index construction, search, result insertion, and writing costs. Check hot helper inference with `@code_warntype`; a type-stable return from `mine` alone does not prove a type-stable recursion. Measure allocations around representative joins at several lengths and overlap ratios, with data construction outside timing.

Implement `:optimized` behind the existing `mine` contract in a new `src/algorithm/eclat_optimized.jl`. Keep the baseline algorithm frozen as the control. Extract only genuinely shared setup/dispatch logic. Implement a sorted two-pointer tidset intersection in `src/algorithm/tidsets.jl`; replace suffix slices with indexed iteration and use concrete containers.

Add early rejection: after h matches with rA and rB remaining tids, the largest possible final support is h + min(rA, rB). Reject only when that bound is below the required count. Reaching the threshold is not permission to stop, because the caller needs the exact support and the complete child tidset.

Compare reusable scratch plus survivor copy against a count-first/materialize-second join. The latter avoids allocating rejected candidates but scans successful pairs twice. Preserve ownership of every live child tidset; a reused buffer must not overwrite a parent or sibling. Grow capacities from observed needs rather than reserving N for every candidate.

Tests first: empty/disjoint/equal/nested tidsets, highly unequal lengths, exact threshold boundaries, rejection at several scan positions, and unchanged parents after sibling recursion. Add `:optimized` to the common fixture/oracle tests only once it implements the complete contract. Include repeated calls and input immutability.

Acceptance: exact maps on all toy/SPMF cases and 300 seeded oracle cases, inferred join helpers, and before/after allocation and runtime records. This stage establishes a readable optimized Eclat even if later experiments are rejected.

## Stage 3: Test packed tidsets for dense search

Owner: Hung; Phat checks memory and boundary cases. Estimate: 1–2 person-days.

Represent dense tidsets with owned `Vector{UInt64}` words and cached support. Intersect by wordwise AND and accumulate `count_ones` in the same loop. Compare this with a standard `BitVector` implementation during development; choose from measurements and avoid depending on private BitArray storage.

Test N = 0, 1, 63, 64, 65, 127, 128, and 129; mask unused trailing bits and verify support exactly. Parents and live siblings own distinct mutable buffers. No bounds-check removal or SIMD annotation precedes proof of safe indices.

Measure pure sorted-list and pure packed-word configurations before introducing selection. With 64-bit Int tids, payload storage is approximately 8k bytes for k tids versus 8 ceil(N/64) bytes for dense words. This suggests a storage crossover near k = N/64, but object overhead, cache behavior, and join cost determine the measured runtime crossover.

Only add a deterministic representation policy if mixed workloads justify it. Prefer concrete containers per equivalence class and a function barrier at conversion, rather than an abstract tidset field in every hot node. Record conversion bytes/time and representation counts by depth. A policy uses tidset lengths/density, not dataset names or benchmark-specific thresholds.

Acceptance: full correctness suite plus dense and sparse screen comparisons. Dense wins must not hide a Retail/T10I4D100K regression. Keep the sorted implementation available for a class when it measures better.

## Stage 4: Avoid provably useless root joins

Owner: Hung. Estimate: 1–2 person-days.

The [baseline description](eclat.md) identifies a paper step omitted by the baseline: counting frequent pairs from horizontal transactions before vertical intersections. Test that step independently, especially on sparse data with many singleton candidates.

After singleton filtering, map frequent items to compact ranks and count co-occurring pairs in each transaction. A pair below the threshold cannot appear in a frequent extension. Skip its root tidset intersection; qualifying pairs still need tidsets for deeper Eclat search. Item IDs and output keys remain unchanged.

Before allocating a triangular table, compute m(m−1)/2 counters and their byte cost with overflow checks. Retail has 16,470 distinct items in the manifest, so a full-universe table of Int64 counters is about 1.01 GiB before overhead. Base sizing on frequent items at that threshold. Compare a bounded dense table, sparse counts, and no pre-counting; select by measured cost and the memory budget.

Measure pair-count construction time, candidate pairs rejected, intersections avoided, and net public `mine` time. Counting all pairs costs the sum of choose(filtered transaction width, 2), so it can lose on dense or wide inputs. Keep this stage only when total time improves, including construction.

Tests first: duplicate input items do not inflate pairs, filtering preserves supports, rank maps handle ID 0 and large sparse IDs, and table/sparse modes agree with brute-force counts. Run an ablation with this stage disabled on the same revision.

## Stage 5: Test ordering and reduce retained workspace

Owner: Hung. Estimate: 1 person-day, conditional on profiles.

Test one global increasing-singleton-support order, breaking ties by original item ID, against the baseline item order. Use the fixed rank consistently throughout suffix ownership so every itemset has one generation path. Canonicalize original item IDs only when constructing output keys. Do not assume a different order must be faster; record join counts, tidset sizes, maximum depth, output-key cost, and wall time.

Use a reusable mutable prefix with push/pop and create immutable tuple keys at emission. Reuse per-depth class containers only after their children finish. Bound pooled capacity and release pathological large buffers between runs so an allocation win does not become a peak-RSS regression. Check deep-pattern specialization and type stability before changing recursion structure.

Acceptance: complete maps and duplicate-emission counters, shuffled item labels/transaction order, repeat-call isolation, and an ablation separating order changes from workspace reuse. Keep each concern in a separate commit.

## Stage 6: Investigate equivalent extensions if dense cases remain behind

Owner: Hung, with Phat's independent human review. Estimate: 2–3 person-days. Start only if residual profiles justify the complexity.

For a prefix P and extension x, T(Px) is a subset of T(P). If their supports are equal, their tidsets are equal. For every later extension Y, T(PYx) = T(PY). This allows sharing intersection work across patterns that differ only by such an equivalent item.

Derive the rule from this tidset identity, document its relation to Children–Parent Equivalence pruning, and retain Eclat's prefix classes and vertical intersections. Do not copy reference implementation source. An implementation needs explicit ownership of equivalent extensions and a proof that each subset combination is emitted once with the correct support.

All frequent patterns must still be emitted. With k equivalent items there can be 2^k output combinations; pruning repeated intersections does not remove output materialization. Equal support of unrelated siblings alone does not establish equal tidsets and must not trigger merging.

Test universal items, equivalent groups, equal-support but different-tidset siblings, nested equivalence, interleaved rank orders, and all threshold boundaries. Use small generated cases where a brute-force map fits, then exact SPMF comparisons on dense benchmarks. Count attempted emissions as well as final dictionary keys so dictionary overwrites cannot conceal duplicate generation.

Acceptance: a written coverage/uniqueness proof, independent review, exact maps, and a measured reduction in redundant intersections that translates into runtime improvement. Reject the stage if it adds complexity without sufficient measured gain. dEclat, N-list mining, GPU execution, and multithreaded search remain separate future proposals, not silent changes to `:optimized`.

## Decide which changes survive

Record cumulative variants B0 baseline, B1 sorted joins, B2 packed representation, B3 pair pruning, B4 ordering/workspace, and B5 equivalent extensions. Also remove one accepted feature at a time from the final candidate to expose interactions. Run all comparisons with matching input, threshold, output handling, and timing scope.

For each stage, archive: hypothesis; parent and candidate commit; affected files; correctness result; median/IQR; bytes allocated and GC seconds; peak RSS; output count; candidate joins; early rejections; tid/word visits; representation conversions; and maximum live workspace. Counters run in diagnostic executions, with their overhead excluded from scored timings.

A default screening gate is at least 10% improvement on the targeted development cases, no unexplained regression above 10% elsewhere, and no peak-RSS increase above 20% without a recorded tradeoff. These are decision thresholds, not forecast speedups. A reproducible smaller gain may be retained when it is simple and does not compromise correctness or maintainability. The final PrePost+ target remains the stricter release gate defined above.

If writing or `SupportMap` construction dominates, measure that fraction explicitly. Even eliminating all remaining intersection time can improve total time only by 1/(1−f), where f is the fraction spent in intersections. Use this bound to decide whether another join optimization can close the gap. Keep public-map creation in the application metric and all output in the file-to-file metric.

If parity is missed, report the per-point gap, the limiting phase, and the best validated implementation. Do not weaken the target by relabeling a several-fold baseline improvement as PrePost+ parity.

## Complete the assignment experiments

Thien owns runtime curves and output-size analysis through [DAT-19](https://linear.app/nguyen-tuan-hung/issue/DAT-19) and width experiments through [DAT-22](https://linear.app/nguyen-tuan-hung/issue/DAT-22). Phat owns exact benchmark comparisons through [DAT-32](https://linear.app/nguyen-tuan-hung/issue/DAT-32) and peak RSS through [DAT-20](https://linear.app/nguyen-tuan-hung/issue/DAT-20). Hung owns implementation through [DAT-17](https://linear.app/nguyen-tuan-hung/issue/DAT-17) and scalability through [DAT-21](https://linear.app/nguyen-tuan-hung/issue/DAT-21). These are existing ownership assignments, not new calendar commitments.

- Runtime: four contender curves over the full grid, with uncertainty, output count, and failed/censored points. Use the same output counts for the output-size plots.
- Memory: all four middle points, baseline versus optimized, five cold-process repeats, peak RSS in bytes/MiB. Show allocated bytes and GC separately; the Java-reported heap number is not RSS.
- Scalability: Retail nested subsets at 10%, 25%, 50%, 75%, 100%, built from one seeded permutation. Start at relative minsup 0.0025, verify count agreement at every size, and freeze it after a feasibility pilot. Record subset hashes, actual N, output count, and width.
- Width: propose N = 10,000, a universe of 100 items, and widths 5, 10, 20, 30, 40. Take prefixes of seeded per-row permutations so rows have unique items and widths are nested. Pilot relative minsup 0.1, then freeze feasible settings before scoring. Use the same files across variants and separate output growth from intersection work. Describe this uniform model's limits for real receipts.
- Applications: run existing market-basket tests and the image-transaction fixture with both variants. Re-run real application notebooks after the optimized release; matching benchmark maps alone does not verify the whole application.
- Report: reproducible plots, captions, tested revision, raw evidence location, timing definitions, correctness rates, limits, and two future optimizations motivated by residual profiles. Vietnamese report prose follows the assignment.

Store raw runs and generated figures under their ignored directories. Publish a checksum-addressed evidence archive outside Git and link it from Linear and the dated evaluation record. Correctness checking may need more RAM than mining when loading two large maps; keep it outside the timed process and test a bounded-memory comparison path before scoring stress outputs.

## Delivery order and stopping rule

1. Qualify the machine, reference adapters, correctness integration, and cold/warm scopes. Freeze the benchmark definition and measure the three existing contenders.
2. Land sorted joins as the smallest coherent optimized implementation. Run the screen and attach correctness/allocation evidence.
3. Evaluate packed words and pair pre-counting in separate changes, then test their interaction. Add ordering/workspace work only where profiles support it.
4. Re-measure the gap. Attempt equivalent-extension pruning only if dense search remains the obstacle and the team can explain and review its proof.
5. Freeze the candidate revision, run the complete grid and assignment experiments, and produce the release decision. If full-grid regressions require tuning, identify a new candidate and rerun its affected comparisons.

Each stage follows test-first development: add the failing test, observe failure, implement, run relevant tests, then run the complete suite before release. Keep complex diffs under 700 changed lines and other nonmechanical diffs under 1000. Use issue branches, Conventional Commits with issue references, concrete hot-loop types, and standard libraries only. Human review is requested through [DAT-41](https://linear.app/nguyen-tuan-hung/issue/DAT-41); agents do not mark it complete.

The estimated core work is 5–9 person-days through representation, pair pruning, and workspace decisions, plus 2–3 person-days if equivalence pruning is justified, and 1–2 person-days for final analysis/integration. These are planning estimates with benchmark waiting time separate. Thien and Phat can prepare measurement and validation while Hung implements; timed experiments remain serial on the benchmark host.

Stop implementing when the correctness, PrePost+ speed, memory, and assignment evidence gates pass. If the estimated work finishes without parity, deliver the measured gap and make a separate decision about further algorithmic work. Preserve the validated Eclat release for both applications throughout that decision.

## Commands and preflight evidence

Existing commands, from the repository root:

```powershell
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. experiments/prepare_benchmarks.jl
julia --startup-file=no --project=. experiments/run.jl experiments/configs/runtime.toml --java .tools/jdk-25.0.4.1+1-jre/bin/java.exe
```

The runtime command above runs the existing baseline/Eclat configuration. It does not run the proposed four-contender experiment; that config and its tests are Stage 1 deliverables.

The planning smoke check used:

```powershell
New-Item -ItemType Directory -Force results/raw/prepost-plan-preflight-20261028
& '.tools/jdk-25.0.4.1+1-jre/bin/java.exe' -jar tools/spmf/spmf.jar run 'PrePost+' data/toy/baskets.txt results/raw/prepost-plan-preflight-20261028/prepost-baskets.txt 0.5
julia --startup-file=no --project=. tools/spmf/compare.jl data/toy/spmf/baskets-0.5.txt results/raw/prepost-plan-preflight-20261028/prepost-baskets.txt
```

It returned no missing, extra, duplicate, or support-mismatched patterns. No optimized miner or benchmark speedup is claimed by this planning change.
