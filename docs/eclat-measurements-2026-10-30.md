# Comparable Eclat measurements, 2026-10-30

Optimization needs controls whose timing boundaries and correctness checks agree. This record establishes the cold development controls for baseline Eclat, SPMF Eclat, and SPMF PrePost+ on all five datasets, using the [measurement protocol](../experiments/README.md).

## Method and provenance

- Timing revision: `3dbed000725af32b0b5c1824c13c269930b2ef8f`, Julia 1.13.2 with one thread, SPMF 2.66, Temurin 25.0.4.1.
- Windows 11 NT 10.0.26100, Intel Core i7-12700H, 15.7 GiB RAM. Each session records its environment and source checksums.
- Inputs and absolute thresholds follow the [manifest](../data/benchmark/manifest.toml) and [development config](../experiments/configs/development.toml). Every timed output is checked against a separate SPMF Eclat execution after timing ends.
- Cold process time includes startup, compilation, reading, mining, writing, and worker report creation. Phase rows describe first calls; compilation outside a call belongs to process time. Allocated bytes measure allocation traffic, while RSS measures resident memory.
- The `-dirty` revision marker includes workspace documentation edits. Source checksums confirm equal measured package and harness files across both sessions and an unchanged mining package and worker after validation hardening.

The host restarted during `retail-m0.001-r2-baseline`. Its partial directory has no completion report, so the combined evidence records `interrupted` with no time. The recovery session repeats the entire Retail/0.001 point and covers the remaining datasets. All earlier samples stay in the evidence. Retail/0.001 therefore has four successful samples per contender, plus one interrupted baseline attempt; every other point has three successful samples per contender.

The audit verifies 93 exact outputs, one retained interruption, 10 development points, 11 reference files, 249 timing rows, and all 80 summary groups. No completed attempt has a mismatch or timeout. Maximum process RSS is 4.06 GiB. The source and environment checks, file hashes, and independent statistics checks are recorded in [audit.json](../results/raw/stage1-b0-combined-20261030/audit.json).

## Cold process results

Times are median seconds, with IQR in parentheses. Every sample, failure, allocation count, and GC time is in [runs.csv](../results/raw/stage1-b0-combined-20261030/runs.csv); [summary.csv](../results/raw/stage1-b0-combined-20261030/summary.csv) keeps the unrounded summaries.

| Dataset / minsup | Count | Itemsets | Baseline s (IQR) | SPMF Eclat s (IQR) | PrePost+ s (IQR) |
|---|---:|---:|---:|---:|---:|
| chess / 0.75 | 2397 | 20993 | 12.86 (0.02) | 3.29 (0.16) | 1.39 (0.42) |
| chess / 0.6 | 1918 | 254944 | 86.83 (8.51) | 14.38 (0.40) | 0.89 (0.05) |
| mushroom / 0.25 | 2031 | 5545 | 8.56 (0.16) | 1.39 (0.01) | 0.88 (0.06) |
| mushroom / 0.1 | 813 | 574431 | 144.28 (4.01) | 10.14 (0.97) | 1.22 (0.38) |
| retail / 0.0025 | 221 | 1882 | 43.93 (0.60) | 1.71 (0.37) | 2.27 (0.21) |
| retail / 0.001 | 89 | 7589 | 154.98 (27.79) | 2.30 (0.63) | 4.39 (2.13) |
| T10I4D100K / 0.001 | 100 | 27532 | 56.90 (8.10) | 4.05 (0.78) | 3.44 (0.57) |
| T10I4D100K / 0.00025 | 25 | 96959 | 99.19 (8.79) | 11.41 (0.42) | 6.66 (0.48) |
| accidents / 0.8 | 272147 | 149 | 33.90 (6.48) | 8.86 (0.62) | 3.07 (1.38) |
| accidents / 0.65 | 221119 | 1093 | 147.56 (2.61) | 32.83 (0.55) | 2.53 (0.05) |

The [timing figure](../results/figures/stage1-b0-development-20261030/timings.png) uses a logarithmic time axis and displays median and IQR. [SVG](../results/figures/stage1-b0-development-20261030/timings.svg) and [HTML](../results/figures/stage1-b0-development-20261030/timings.html) versions accompany it. The Retail interruption remains marked on the figure.

## Allocation and memory evidence

These are median baseline cold-call phases at the lower development threshold. The mining call includes canonicalization and complete `SupportMap` construction. Phase allocations and GC for reading and writing also appear in the raw CSV and summary.

| Dataset / minsup | Read s | Mine s | Write s | Mine allocated GiB | Mine GC s |
|---|---:|---:|---:|---:|---:|
| chess / 0.6 | 0.039 | 79.010 | 5.076 | 35.97 | 6.218 |
| mushroom / 0.1 | 0.047 | 128.103 | 13.231 | 43.14 | 13.523 |
| retail / 0.001 | 0.255 | 151.433 | 0.551 | 49.96 | 5.849 |
| T10I4D100K / 0.00025 | 0.296 | 92.753 | 3.344 | 33.31 | 4.944 |
| accidents / 0.65 | 3.718 | 139.662 | 1.450 | 33.61 | 11.891 |

Maximum process RSS across both development thresholds and all successful repeats, in MiB:

| Dataset | Baseline | SPMF Eclat | PrePost+ |
|---|---:|---:|---:|
| chess | 299.7 | 696.8 | 163.1 |
| mushroom | 374.0 | 741.5 | 196.2 |
| retail | 320.7 | 843.8 | 220.7 |
| T10I4D100K | 327.8 | 503.4 | 266.7 |
| accidents | 1093.5 | 4154.7 | 305.4 |

Mining dominates the baseline at the lower development points. These measurements establish the control for subsequent input, output, and kernel changes; they do not isolate the cost of an individual join. Join counters are absent from this control series.

## Reproduce and validate

The two source run directories preserve commands, configs, environments, source checksums, stdout, stderr, reports, outputs, and exact-map diagnostics. The combined directory links both sessions through `composition.json` and retains the assembly and audit scripts under `reproduce/`.

```sh
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. experiments/run.jl experiments/configs/development.toml --java .tools/jdk-25.0.4.1+1-jre/bin/java.exe
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/report_measurements.py results/raw/stage1-b0-combined-20261030 --out results/figures/stage1-b0-development-20261030
```

The plot generator independently checks process medians and IQRs against the runner. `plot-environment.json` records the isolated plotting environment. The audit independently checks all 80 summary groups and verifies each retained output's checksum.

The final suite passes 811 tests at validation revision `0f423fe`, including cold and warm workers, PrePost+ parsing, threshold disagreement, truncated statistics, duplicate patterns, malformed output, missing output, and required repeats after timeout. Setup validation passes. Failing and passing test logs accompany the archive.

These are development controls. The warm benchmark-dataset series and the five-repeat 33-point scored series are separate experiments. No optimized candidate is measured here. [DAT-17](https://linear.app/nguyen-tuan-hung/issue/DAT-17) tracks the remaining optimization work and human review.

## Evidence archive

The complete archive contains 694 files (30,496,662 compressed bytes). It is attached to [DAT-17](https://linear.app/nguyen-tuan-hung/issue/DAT-17) as four parts and `reassemble_stage1.py`, because Linear limits each free-plan upload to 10 MB. Download all five files into one directory and run `uv run --no-project --python 3.12 python reassemble_stage1.py`. The script verifies every part and the reconstructed ZIP. Local reassembly reproduces the original checksum.

Archive SHA-256: `f13c9d2bff36f76e76c75c45730dbe248c51ddc279239a8a97f84fc0313b2c39`.

The uploaded parts and script were downloaded from Linear, checked against the local hashes, and reassembled into the same archive SHA-256.

## Visualization label correction, 2026-10-30

The first figure used the label `invalid` for the interrupted Retail attempt. That label was a reporting error. The attempt has `status = interrupted`, `correctness_status = not_checked`, and no output file or completion report. All 31 completed baseline runs match SPMF exactly; the complete series has zero observed correctness failures.

The corrected figures and plot summary separate correctness failures, interruptions, other incomplete attempts, and unverified outputs. Timings and raw evidence are unchanged. The original evidence archive retains the first figure for provenance; a separate correction bundle accompanies it in [DAT-17](https://linear.app/nguyen-tuan-hung/issue/DAT-17).
