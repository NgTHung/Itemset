# Measurement protocol

Benchmark charts in the report compare runs made by different people, on different days, against a Java reference. This protocol fixes how each run is made and recorded, so every chart compares like with like and any point can be rerun. Every experiment owner runs through the same harness instead of a private script.

## Run an experiment

```sh
julia --startup-file=no --project=. experiments/prepare_benchmarks.jl
julia --startup-file=no --project=. experiments/run.jl experiments/configs/pilot.toml
```

A config in `experiments/configs/` names the variants (`baseline`, `optimized`, `spmf`), the datasets with their minsup fractions, the repeat count, and the per-attempt timeout. `--project PATH` measures the `ItemsetMining` of another checkout, such as a teammate's branch in a Git worktree. `--java PATH` selects the Java that runs SPMF. The run writes to `results/raw/<name>-<UTC time>/`.

## Datasets and thresholds

Use the four benchmarks in [data/benchmark](../data/benchmark/README.md). Every series on a dataset uses the same 5 to 7 decreasing relative minsup values, chosen from a pilot run.

The harness rejects a threshold before any run when `support_threshold` and SPMF turn it into different counts, because the two maps would then differ for a reason unrelated to correctness. [tools/spmf](../tools/spmf/README.md#thresholds) records how SPMF rounds.

## What each attempt records

Each attempt runs in a fresh process and adds rows to `runs.csv` with the header in [result-fields.txt](result-fields.txt). The run folder also keeps `config.toml`, `environment.toml` with the Git revisions, CPU, memory, and Java version, and one folder per attempt with its command, stdout, stderr, and reports.

A failed attempt keeps its row with status `error` and the first error line. A timed-out attempt has status `timeout` and its wall time until the kill. After a timeout, the remaining attempts of that dataset and variant get status `skipped`, because a lower threshold only adds itemsets. Rows never carry a zero in place of a missing measurement.

The harness checks each output before it records it. The written itemset count must equal the count the run reported, and the transaction count each program read must equal the manifest's. Set `keep_outputs = true` to keep the output files for the SPMF comparison in [tools/spmf](../tools/spmf/README.md).

## Timing

Julia compiles a method on its first call, and Java pays JVM startup on every process, so each row names its `timing_scope`:

| Scope | Variants | Measures | Warmup |
|---|---|---|---|
| `process` | all | Wall time from spawn to exit, including startup, compilation, input, and output | `cold-process` or `cold-jvm` |
| `read`, `mine`, `write` | Julia | One call each, after the same calls ran on a toy database | `toy-warmup` |
| `spmf_total` | SPMF | SPMF's own "Total time" line | `cold-jvm` |

Compare `process` with `process` for end-to-end cost. `mine` and `spmf_total` are the closest algorithm-only pair, but SPMF defines its own boundary. The `mine` row also records allocated bytes and GC time, which optimization work reports before and after a change.

Repeats run as separate processes, interleaved across variants, so machine drift affects every variant alike. Report the spread across repeats with every median.

## Memory

Peak memory is the OS-measured peak resident set size of the measured process in bytes, not Julia's allocation count, because only RSS is comparable with the Java process. `experiments/measure.jl` reads `PeakWorkingSetSize` on Windows and `getrusage(RUSAGE_CHILDREN)` on Linux and macOS, and each row names the tool. Measure the baseline and optimized variants at the same medium minsup.

## Correctness

Compare complete itemset and support maps, not only itemset counts, because two outputs with equal counts can disagree on every support. The comparison procedure is in [tools/spmf](../tools/spmf/README.md).

## Scalability and width

Scalability runs use seeded nested subsets of 10, 25, 50, 75, and 100 percent of each database at a fixed relative minsup, and plot the actual transaction counts. Width runs hold N, the item universe, and the sampling model fixed while varying transaction width. Output-size plots reuse the counts from the timing runs instead of rerunning.

Store figures in [results/figures](../results/figures/README.md), and copy the ones the report uses into the report with their provenance.
