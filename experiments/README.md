# Measurement protocol

Benchmark charts in the report compare runs made by different people, on different days, against a Java reference. This protocol fixes how each run is made and recorded, so every chart compares like with like and any point can be rerun. Every experiment owner runs through the same harness instead of a private script.

## Run an experiment

```sh
julia --startup-file=no --project=. experiments/prepare_benchmarks.jl
julia --startup-file=no --project=. experiments/run.jl experiments/configs/pilot.toml
```

A config names the variants (`baseline`, `optimized`, `spmf` for Eclat, `prepost` for PrePost+), mode, stage, thresholds, repeat count, and timeout. `--project PATH` measures another checkout. `--java PATH` selects Java. The run writes to `results/raw/<name>-<UTC time>/`.

Use `configs/development.toml` for three repeats at two thresholds on each of the five datasets. Use `configs/runtime.toml` for five repeats over the 33 required points. Each cumulative stage and each micro-optimization gets its own stage label, hypothesis in the config, and run directory. Run the same grid before and after a change, including datasets that the change does not target.

## Datasets and thresholds

Use the five benchmarks in [data/benchmark](../data/benchmark/README.md). Every series on a dataset uses the same 5 to 7 decreasing relative minsup values, chosen from a pilot run.

The harness rejects a threshold before any run when `support_threshold` and SPMF turn it into different counts, because the two maps would then differ for a reason unrelated to correctness. [tools/spmf](../tools/spmf/README.md#thresholds) records how SPMF rounds.

## What each attempt records

Each attempt runs in a fresh process and adds rows to `runs.csv` with the header in [result-fields.txt](result-fields.txt). The run folder also keeps `config.toml`, `environment.toml` with the Git revisions, CPU, memory, and Java version, and one folder per attempt with its command, stdout, stderr, and reports.

A failed attempt keeps its row with status `error` and the first error line. A timed-out attempt has status `timeout` and wall time until the kill. Every required point and repeat is attempted. Pilot configs can set `skip_after_timeout = true` to skip subsequent attempts of a timed-out variant and dataset. Rows never substitute zero for a missing measurement.

After a host interruption, preserve the partial run and record an attempt without a completion report as `interrupted`, with no elapsed time. Restart the entire interrupted point in a separate run, then cover the remaining points. Link both sessions and retain their samples and failures when combining evidence.

Output counts must match the program's report, and transaction counts must match the manifest. With `verify_outputs = true` (the default), every successful output is compared with a separate SPMF Eclat execution after timing ends. PrePost+'s reported absolute threshold must also agree. A mismatch, duplicate, or malformed output invalidates the timing row. The reference runs and per-attempt `comparison.toml` files preserve the checksums and comparison diagnostics. `keep_outputs = true` retains successful outputs; failures retain their output for diagnosis.

## Timing

Julia compiles a method on its first call, and Java pays JVM startup on every process, so each row names its `timing_scope`:

| Scope | Variants | Measures | Warmup |
|---|---|---|---|
| `process`, cold mode | all | Spawn to exit, including startup, compilation, input, and output, with no benchmark warmup | `cold-process` or `cold-jvm` |
| `read`, `mine`, `write`, cold mode | Julia | First calls; process timing also captures compilation outside these calls | `cold-call` |
| `process`, warm mode | Julia | Entire worker, including untimed warmup, for diagnosis | `warm-worker` |
| `process`, CLI mode | all | Spawn to exit of the measured checkout's `demo.jl`, with no measurement code in the process | `cold-process` or `cold-jvm` |
| `read`, `mine`, `write`, warm mode | Julia | Calls after toy compilation and one full run of the same input to devnull, followed by GC | `dataset-warmup` |
| `spmf_total` | SPMF references | SPMF's own "Total time" line | `cold-jvm` |

Compare CLI `process` rows for end-to-end cost. The worker's own reporting code compiles in every cold process, about 0.4 s that no user run pays, so cold mode serves the phase breakdown. Cold refers to a fresh process, not a flushed filesystem cache. Warm `mine` measures application latency, including the complete `SupportMap`; it is separate from SPMF's internal time. Every Julia phase records allocations and GC time. Process RSS is repeated on phase rows and is not a phase-specific peak.

Repeats run in separate processes, interleaved across variants. `runs.csv` preserves each sample and repeat identity. `summary.csv` reports medians, linearly interpolated IQRs, sorted samples, maximum process RSS, median allocations and GC time, and failure counts. It excludes failed or unverified samples from statistics without removing their counts. `gate_eligible` requires five exact samples and no failures; it does not establish the speed or memory targets. Development screens with three repeats cannot pass the scored gate.

## Memory

Peak memory is the OS-measured peak resident set size of the measured process in bytes, not Julia's allocation count, because only RSS is comparable with the Java process. `experiments/measure.jl` reads `PeakWorkingSetSize` on Windows and `getrusage(RUSAGE_CHILDREN)` on Linux and macOS, and each row names the tool. Measure the baseline and optimized variants at the same medium minsup.

## Correctness

Compare complete itemset and support maps, not only itemset counts, because two outputs with equal counts can disagree on every support. The comparison procedure is in [tools/spmf](../tools/spmf/README.md).

## Scalability and width

Scalability runs use seeded nested subsets of 10, 25, 50, 75, and 100 percent of each database at a fixed relative minsup, and plot the actual transaction counts. Width runs hold N, the item universe, and the sampling model fixed while varying transaction width. Output-size plots reuse the counts from the timing runs instead of rerunning.

Store figures in [results/figures](../results/figures/README.md), and copy the ones the report uses into the report with their provenance.
