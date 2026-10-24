# Threshold pilot, 2026-10-22

The runtime, memory, and correctness charts need 5 to 7 minsup values per dataset that both programs finish, spanning cheap to expensive runs. This pilot ran a coarse grid once per point to find where each series becomes slow, and proposes the values in [experiments/configs/runtime.toml](../experiments/configs/runtime.toml) for the team to agree on.

## Setup

- Baseline Eclat at `0acb443`, the revision merged as PR #4, measured from a worktree with `--project`.
- SPMF v2.66, JAR SHA-256 `4aa46838…`, on Temurin Java 25.0.4.1.
- Windows 11 (NT 10.0.26200), AMD Ryzen 7 H 260, 31.3 GiB RAM, Julia 1.13.2 with one thread.
- One repeat per point and a 300 s timeout. The harness revision was `4d1d1a4` with uncommitted documentation edits.

```sh
julia --startup-file=no --project=. experiments/run.jl experiments/configs/pilot.toml \
  --out results/raw/pilot-20261022 --project .tools/dat-8 --java .tools/jdk-25.0.4.1+1-jre/bin/java.exe
```

The 162 rows and every attempt's command, stdout, stderr, and output are in the run folder, attached to DAT-12.

## Results

Times are whole-process wall time in seconds, and memory is peak RSS in MiB.

| Dataset | minsup | Itemsets | Baseline s | SPMF s | Baseline MiB | SPMF MiB |
|---|---|---|---|---|---|---|
| chess | 0.9 | 622 | 3.8 | 0.4 | 246 | 134 |
| chess | 0.7 | 48,731 | 22.5 | 2.3 | 276 | 778 |
| chess | 0.6 | 254,944 | 91.3 | 14.4 | 290 | 936 |
| chess | 0.55 | 574,998 | 189.9 | 19.3 | 361 | 753 |
| chess | 0.5 | 1,272,932 | timeout | 38.8 | | 1,111 |
| mushroom | 0.5 | 153 | 2.5 | 0.4 | 251 | 124 |
| mushroom | 0.2 | 53,583 | 12.9 | 1.2 | 286 | 607 |
| mushroom | 0.1 | 574,431 | 80.2 | 3.9 | 370 | 1,096 |
| mushroom | 0.05 | 3,755,511 | timeout | 16.6 | | 965 |
| retail | 0.01 | 159 | 4.5 | 0.9 | 303 | 809 |
| retail | 0.0025 | 1,882 | 29.1 | 1.2 | 308 | 829 |
| retail | 0.001 | 7,589 | 102.5 | 1.4 | 320 | 860 |
| retail | 0.0005 | 19,242 | timeout | 1.8 | | 894 |
| T10I4D100K | 0.01 | 385 | 22.5 | 0.9 | 319 | 220 |
| T10I4D100K | 0.001 | 27,532 | 59.7 | 2.6 | 331 | 388 |
| T10I4D100K | 0.00025 | 96,959 | 86.9 | 8.2 | 329 | 431 |

The baseline and SPMF maps were equal at all 25 points where both finished, with no missing, extra, or mismatched itemsets. A one-off script parsed both outputs into maps; the team comparator (DAT-9) repeats this check.

The baseline is 6 to 71 times slower end to end. Its time follows the number of tid-list intersections, not the output size: T10I4D100K at minsup 0.01 takes 18.8 s in `mine` for 385 itemsets, because its 375 frequent items give 70,125 pair intersections. At the finished points, peak RSS ranges from 246 to 370 MiB for the baseline and from 124 to 1,111 MiB for SPMF; the memory experiment (DAT-20) explains the difference.

The same point varies between days: Chess at 0.6 took 57.5 s on 2026-10-21 and 91.3 s here. The runtime config therefore uses 3 repeats.

## Proposed thresholds

| Dataset | minsup values | Slowest baseline point in the pilot |
|---|---|---|
| chess | 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6 | 91 s |
| mushroom | 0.5, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1 | 80 s |
| retail | 0.01, 0.0075, 0.005, 0.0025, 0.0015, 0.001 | 103 s |
| T10I4D100K | 0.01, 0.005, 0.0025, 0.001, 0.0005, 0.00025 | 87 s |

Every value finishes for the baseline with room for slower repeats, and SPMF rounds each to the same count as `support_threshold`. Retail's 0.0075 and 0.0015 were not in the pilot; they fall between measured points.
