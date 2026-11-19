# BBQ diffset probe, 2026-11-08

Plan Stage 5 included switching dense bitset classes to diffsets (Zaki and Gouda, 2003), which store the tids a member lacks relative to its prefix instead of the tids it has. The [plan's prototype](eclat-optimization-plan-2026-10-30.md#tidset-representation-by-dataset) found the switch 1.1 to 2.1 times faster on Accidents. This record measures it against the [sparse-kernel revision](bbq-sparse-kernel-runtime-2026-11-08.md), explains why the optimized variant does not ship it, and records the memory question that came up on the way.

## Where diffsets could help

Diffsets speed up joins only. After Stages 3 to 5, a warm BBQ profile of the sparse-kernel revision found the search under 0.08 s at every Accidents point in the plan, so the [plan addendum](eclat-optimization-plan-2026-10-30.md#addendum-2026-11-08-diffset-stress-points) added two stress points below it before any diffset code ran:

| Accidents minsup | Itemsets | Warm mining s | Search share | Optimized CLI s | PrePost+ s |
|---|---:|---:|---:|---:|---:|
| 0.4 | 32,528 | 0.42 | 19% | | |
| 0.3 | 149,545 | 0.66 | 47% | 1.57 | 2.71 |
| 0.25 | 346,525 | 1.10 | 61% | 2.09 | 3.79 |
| 0.2 | 889,883 | 2.34 | 81% | 3.57 | 4.78 |

The CLI and PrePost+ times are one unverified cold run each. SPMF Eclat ran for more than 15 minutes on Accidents 0.25 before the probe was stopped, so these points cannot be verified within the 900 s stress timeout.

Diffsets do not save meaningful memory in this variant. Bitsets already store one bit per transaction, and the tidsets alive during the search peak at 4.6 MiB, at Accidents 0.2. Peak RSS goes to the input database, 211 MiB for Accidents as `Vector{Vector{Int}}`, and to the packed result, 362 MiB at Mushroom 0.05.

## Implementation

Commit `2ea889d` gave a bitset member's children diffsets when 2 × (support − minsup) was below `DIFF_RATIO` times ⌈N/64⌉. At the switch, child b of member a stored t(Pa) \ t(Pb), computed as a AND NOT b. Inside a diffset class, a join stored d(Qc) \ d(Qb) and returned support(Qb) minus its length. Both differences stopped early once the child could not reach minsup. Commit `9402e20` proved the switch exact. All 12,553 tests passed, including 600 seeded databases against the oracle with diffsets never, always, and by the rule.

## Results

A warm sweep on BBQ, median of five runs per cell, timed `mine_optimized` with each ratio. Times are seconds.

| Point | Never | 1/32 | 1/16 | 1/8 | 1/4 | 1/2 |
|---|---:|---:|---:|---:|---:|---:|
| Accidents 0.4 | 0.420 | 0.418 | 0.419 | 0.417 | 0.421 | 0.427 |
| Accidents 0.25 | 1.158 | 1.162 | 1.225 | 1.240 | 1.259 | 1.324 |
| Accidents 0.2 | 2.436 | 2.442 | 2.457 | 2.486 | 2.560 | 2.691 |
| Chess 0.5 | 0.175 | 0.178 | 0.180 | 0.181 | 0.180 | 0.181 |
| Mushroom 0.05 | 0.412 | 0.403 | 0.420 | 0.405 | 0.416 | 0.415 |
| Retail 0.001 | 0.112 | 0.121 | 0.120 | 0.125 | 0.132 | 0.131 |
| T10I4D100K 0.00025 | 0.882 | 0.935 | 1.147 | 1.329 | 1.426 | 1.511 |

No ratio is faster than bitsets beyond run-to-run noise at any point, and larger ratios slow Accidents by up to 10% and T10I4D100K by up to 71%. A sweep on the development machine with ratios up to 8 slowed Accidents 0.2 from 2.90 s to 7.78 s.

The worst-case bound in the rule could switch too eagerly, so a second check used the exact diffset sizes, which are known after the bitset joins as support(a) − support(child). For every class the bitset search builds, it took the cheaper of its own bitset joins and converting it to diffsets at 8 words per merge step, the cost the [tid-list sweep](eclat-optimized.md#tid-lists-below-the-root) measured. Over all classes, that ideal choice saves 0.0% of join words on Accidents 0.4, Mushroom 0.05, and Chess 0.5, 0.1% on Accidents 0.25, and 0.3% on Accidents 0.2.

Two effects explain the gap to the plan's prototype. Perfect-extension pruning already removes every member whose diffset would be empty, and those are the members where diffsets save most. A diffset merge step costs about 8 bitset words on BBQ, so a diffset pays only below ⌈N/64⌉/16 tids, 332 on Accidents, while most remaining diffsets there are larger. The prototype measured against an earlier bitset search without these changes, so its gains do not carry over.

## Decision

On 2026-11-08 the team dropped the switch: commit `525b0bb` reverts `2ea889d` and `9402e20`, and the code returns to the sparse-kernel revision. Diffsets become a future direction for the report, for a search without perfect-extension pruning or with a slower bitset join. The memory breakdown points instead at the input database and the packed result, which use 64-bit integers.
