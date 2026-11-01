# BBQ baseline runtime, 2026-10-31

Every optimization stage needs a fixed control measured on one machine in one continuous session. This record measures the baseline at revision `583abe342ea3e840e51293744291850823e6a4ba` against SPMF Eclat and SPMF PrePost+ on the full runtime grid. The baseline joins tid-lists with a two-pointer merge, emits packed results, and reads and writes SPMF text as bytes.

## Method

- Run ID: `bbq-b2-runtime-20261031T150716Z`, collected from 2026-10-31T15:09:22Z to 15:54:15Z.
- All 33 points in [runtime.toml](../experiments/configs/runtime.toml), five cold repeats each of baseline, SPMF Eclat, and SPMF PrePost+: 495 attempts. Every attempt has a 300 s timeout.
- Julia 1.13.2 with one thread, seed 42. Temurin 25.0.4.1+1 runs both references with `-Xms256m -Xmx4g`. SPMF 2.66 JAR SHA-256: `4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a`.
- BBQ reports Linux `6.12.107+deb13-amd64`, Intel Core i7-11800H, 16 logical CPUs, and 7.4 GiB of RAM. Every input matches the [dataset manifest](../data/benchmark/manifest.toml).
- The worker times `mine_packed` and the packed writer.
- The controller runs a clean checkout of the revision in its own tmux session. It refuses to start, and fails the audit, unless `no_turbo` is 1 and every policy's maximum clock is 2.3 GHz at both ends. Both snapshots pass.
- Preflight on BBQ passes 3735 tests, setup validation, CLI validation, and a three-contender smoke run with exact outputs.

## Results

All 495 outputs match a separate SPMF Eclat run exactly. There are no failures, timeouts, or interruptions. The audit checks all 264 summary groups and 33 reference files, and all 3386 evidence files match their recorded SHA-256 after transfer. The archive SHA-256 is `9568ee455349121b8f85359b5fa78a947255acc8aefc4c5d7466a86cc90cff39`. The baseline's IQR stays within 3% of its median.

| Measure | Range over the 33 points |
|---|---|
| Baseline / PrePost+ time | 2.2 to 12.8 |
| Geometric mean baseline / PrePost+ | Accidents 2.6, Retail 3.4, T10I4D100K 4.1, Mushroom 7.3, Chess 7.7 |
| Process time outside read, mine, and write | 2.77 to 2.88 s |

The baseline beats SPMF Eclat at every Accidents point and at Chess 0.7 and below. Mining takes 51% to 81% of process time at each dataset's lowest point and allocates 3.3 to 5.7 GiB there. At high thresholds the fixed 2.8 s, nearly all compilation, dominates: Chess 0.9 takes 2.81 s against 0.40 s for PrePost+.

The [figure](../results/figures/bbq-b2-runtime-20261031/timings.png) shows every point with median and IQR. Raw rows are in `results/raw/bbq-b2-runtime-20261031T150716Z/`.
