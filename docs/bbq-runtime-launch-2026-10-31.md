# BBQ runtime cohort, 2026-10-31

A single benchmark cohort keeps the baseline and reference measurements on the same machine and within one continuous collection period. This record captures the launch of the full runtime grid on BBQ. Earlier Windows, interrupted, recovery, and Retail recheck samples stay outside this cohort.

## Frozen experiment

- Run ID: `bbq-b0-runtime-20261031T064846Z`. The ID was allocated during setup; the controller starts the timed series at `2026-10-31T07:29:18.310833Z`.
- Source revision: `2c6ff0ddd42c4adf1dc0a3e9ffb5d56ffa812490`, with a clean isolated checkout on BBQ. The mining implementation is unchanged.
- Grid: all 33 thresholds in [runtime.toml](../experiments/configs/runtime.toml), five repeats each of baseline, SPMF Eclat, and SPMF PrePost+. The grid contains 495 process attempts, 165 per contender.
- Julia 1.13.2, one Julia thread, cold mode, seed 42. Temurin 25.0.4.1+1 runs both Java references with `-Xms256m -Xmx4g` throughout the cohort.
- SPMF 2.66 JAR SHA-256: `4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a`.
- Every attempt has a 300-second timeout. Subsequent points and repeats remain scheduled after a timeout. Successful outputs retain their files and undergo complete-map comparison after timing.

BBQ reports Linux `6.12.107+deb13-amd64`, Intel Core i7-11800H, 16 logical CPUs, and 7,944,155,136 bytes of physical RAM. Runtimes and the isolated Julia depot live under `/home/bbq/.local/share/itemset-benchmark/`; the system Java installation and other services are unchanged. Source and input bytes were transferred separately, and every input matches the [dataset manifest](../data/benchmark/manifest.toml).

## Preflight evidence

The pinned Linux environment passes all 811 tests, setup validation, and CLI input validation. A separate Chess/0.9 smoke run executes all three contenders through the real runner. Its three outputs match the independent SPMF Eclat map exactly, Linux RSS readings are positive, and an independent audit verifies its eight timing-summary groups. These smoke samples are excluded from the 495-attempt cohort.

Julia and Temurin archives are checked against SHA-256 values from their official release metadata before extraction. The complete runtime configuration, release URLs, archive checksums, preflight logs, and source snapshot accompany the cohort evidence.

## Collection and completion

The controller runs in tmux session `itemset-20261031T064846Z`. A laptop or SSH disconnect does not terminate the benchmark. A process lock prevents a second benchmark controller from using the same benchmark environment concurrently.

The isolated checkout is `/home/bbq/.local/share/itemset-benchmark/checkouts/bbq-b0-runtime-20261031T064846Z`. Its live rows are under `results/raw/bbq-b0-runtime-20261031T064846Z/`; `.tools/fullrun-status.json` records controller state and `.tools/fullrun.log` retains console output. The CSV is flushed after each attempt, so progress checks use it even when console output is buffered.

After the runner exits, the controller verifies the planned attempt identities, complete-output and reference hashes, every summary group, source checksums, unchanged runtime/config hashes, and the host boot ID. It preserves unsuccessful attempts and creates a checksum-addressed evidence ledger and compressed archive. A completed attempted grid with failures is reported separately from an entirely exact grid.

Automatic checks in the same conversation run every 15 minutes and stop after the results are retrieved, verified, documented, and attached to [DAT-17](https://linear.app/nguyen-tuan-hung/issue/DAT-17). Human peer review and later optimization stages remain separate from this measurement job.
