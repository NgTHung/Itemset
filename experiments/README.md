# Measurement protocol

Benchmark charts in the report compare runs made by different people, on different days, against a Java reference. This protocol fixes how each run is made and recorded, so every chart compares like with like and any point can be rerun.

## Datasets and thresholds

Run Chess, Mushroom, Retail, and T10I4D100K, prepared as described in [data/benchmark](../data/benchmark/README.md). Use the same 5 to 7 decreasing relative minsup values for every series on a dataset, chosen from a pilot run. Compute transaction counts and widths from the files instead of copying catalog values, because some catalog figures are wrong.

## Record each attempt

Write one CSV row per attempt with the header in [result-fields.txt](result-fields.txt). Keep failed and timed-out attempts with their status, and never replace them with zeros. Save each command with its stdout and stderr in [results/raw](../results/raw/README.md).

Freeze these values for every series: input SHA-256, SPMF JAR version and SHA-256, Java version, Git revision, Julia version, OS, CPU, thread count, `DEFAULT_SEED`, and parameters. Record the repeat count and timeout chosen after the pilot, and report the variation across repeats.

## Timing

Julia compiles a method on its first call, and Java pays JVM startup on every process. Raw times from the two are therefore not comparable. For each series, record what the timer includes: warmup policy, compilation, file I/O, materialization of the output map, and serialization. Keep end-to-end process timing and mining-only timing as separate series.

## Memory

Peak memory is the OS-measured peak resident set size of the process in bytes, not Julia's allocation count, because only RSS is comparable with the Java process. Record the platform and the measuring tool. Measure the baseline and optimized variants at the same medium minsup.

## Correctness

Compare complete itemset and support maps, not only itemset counts, because two outputs with equal counts can disagree on every support. The comparison procedure is in [tools/spmf](../tools/spmf/README.md).

## Scalability and width

Scalability runs use seeded nested subsets of 10, 25, 50, 75, and 100 percent of each database at a fixed relative minsup, and plot the actual transaction counts. Width runs hold N, the item universe, and the sampling model fixed while varying transaction width. Output-size plots reuse the counts from the raw timing runs instead of rerunning.

Store figures in [results/figures](../results/figures/README.md), and copy the ones the report uses into the report with their provenance.
