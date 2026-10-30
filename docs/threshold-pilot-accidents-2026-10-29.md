# Accidents threshold pilot, 2026-10-29

The runtime, memory, and correctness charts need 5 to 7 minsup values for Accidents that both programs finish, as the [2026-10-22 pilot](threshold-pilot-2026-10-22.md) found for the other four benchmarks. Accidents has 340,183 transactions with a mean width of 33.8, so every tidset is long and the series becomes slow at a much higher minsup than Chess or Mushroom. This pilot found that point and proposes the Accidents values in [experiments/configs/runtime.toml](../experiments/configs/runtime.toml).

## Setup

- Baseline Eclat at `030927f`, the commit that adds Accidents to the manifest, measured in this checkout.
- SPMF v2.66, JAR SHA-256 `4aa46838…`, on Temurin Java 25.0.4.1.
- Windows 11 (NT 10.0.26100), Intel Core i7-12700H, 15.7 GiB RAM, Julia 1.13.2 with one thread. This is a different machine from the 2026-10-22 pilot, so compare times only within this note.
- One repeat per point and a 300 s timeout, as in the first pilot.

The coarse pass ran 0.9 down to 0.2. The baseline finished only three points, so a second pass measured the values between them:

```sh
julia --startup-file=no --project=. experiments/run.jl experiments/configs/pilot-accidents.toml \
  --out results/raw/pilot-accidents-20261029 --java .tools/jdk-25.0.4.1+1-jre/bin/java.exe
julia --startup-file=no --project=. experiments/run.jl experiments/configs/pilot-accidents-fill.toml \
  --out results/raw/pilot-accidents-fill-20261029 --java .tools/jdk-25.0.4.1+1-jre/bin/java.exe
```

The 60 rows and every attempt's command, stdout, stderr, and output are in the two run folders, attached to DAT-42.

## Results

Times are whole-process wall time in seconds, and memory is peak RSS in MiB.

| minsup | Count | Itemsets | Baseline s | Baseline `mine` s | SPMF s | Baseline MiB | SPMF MiB |
|---|---|---|---|---|---|---|---|
| 0.95 | 323,174 | 15 | 11.0 | 2.1 | 5.1 | 996 | 1,486 |
| 0.9 | 306,165 | 31 | 15.8 | 7.0 | 6.1 | 1,104 | 1,476 |
| 0.85 | 289,156 | 71 | 27.6 | 18.1 | 7.3 | 920 | 1,933 |
| 0.8 | 272,147 | 149 | 36.3 | 29.0 | 10.9 | 1,064 | 2,458 |
| 0.75 | 255,138 | 313 | 88.0 | 78.7 | 16.8 | 990 | 3,482 |
| 0.7 | 238,129 | 529 | 109.2 | 99.4 | 28.0 | 926 | 3,953 |
| 0.65 | 221,119 | 1,093 | 138.7 | 130.0 | 21.5 | 944 | 3,983 |
| 0.6 | 204,110 | 2,074 | timeout | | 46.9 | | 4,160 |
| 0.5 | 170,092 | 8,057 | skipped | | 114.3 | | 4,170 |
| 0.45 | 153,083 | | skipped | | timeout | | |

The harness skipped the remaining points, 0.4 to 0.2, for both programs after their first timeout. The baseline and SPMF maps were equal at all seven points where both finished, checked with `tools/spmf/compare.jl`: no missing, extra, duplicated, or mismatched itemsets.

Accidents is slow for a different reason than the other benchmarks. At 0.65 the baseline spends 130 s in `mine` for 1,093 itemsets, because every frequent item's tidset holds more than 221,000 transaction IDs, so each intersection scans hundreds of thousands of integers. SPMF's Eclat also uses tidsets and also times out, at 0.45, so the limit comes from the representation, not only from the baseline's code. Peak RSS stays near 1 GiB for the baseline, while SPMF grows from 1.5 to 4.2 GiB as minsup falls.

## Proposed thresholds

| Dataset | minsup values | Middle point for memory | Slowest baseline point |
|---|---|---|---|
| accidents | 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65 | 0.8 | 139 s |

Every value finishes for the baseline with about twice the measured time in hand before the 300 s timeout, and SPMF rounds each to the same count as `support_threshold`. The output stays below 1,100 itemsets, so the Accidents series shows the cost of long tidsets rather than output growth; the Chess and Mushroom series cover output growth. Lower values such as 0.6 and 0.5 belong in a stress series for the optimized variant.
