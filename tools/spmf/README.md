# SPMF reference runs

Hand-derived fixtures can share the same mistake as the miner they test. An independent run of the SPMF Java library gives a second implementation to compare against, so a support error shows up as a disagreement between two programs written by different people.

## Run SPMF

1. Download the executable JAR from [SPMF](https://www.philippe-fournier-viger.com/spmf/download.php) into this folder. Git ignores `*.jar` files here. Use v2.66 (2026-06-15) or later, because its release notes fix an Eclat bug introduced in v2.65. The v2.66 JAR has SHA-256 `4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a` and needs Java 25 or later; Java 21 rejects its class files.
2. Install Java 25, or unpack a portable [Temurin](https://adoptium.net/) JRE into `.tools/`, which Git ignores.
3. Run SPMF through the harness, `experiments/run.jl` with the `spmf` variant, so each run records the JAR's SHA-256, `java -version`, and the exact command. The command it runs is:

```sh
java -jar tools/spmf/spmf.jar run Eclat INPUT OUTPUT MINSUP
```

`MINSUP` is a fraction such as `0.75`; `75%` gives the same result. SPMF requires positive item IDs, which is why [data/benchmark](../../data/benchmark/README.md#choice-of-copies) uses copies without item 0.

Use SPMF only as an executable. Never copy its Java source into the miner.

## Thresholds

SPMF turns a fraction into a count as `ceil(minsup * N)` in `Float64`. On a database of 100 transactions where an item occurs 7 times, `0.07` and `7%` both drop that item, while `0.069` keeps it, so SPMF requires 8 transactions where `support_threshold(0.07, 100)` requires 7. Compare only thresholds where both counts agree; the harness checks this before it runs anything.

## Compare outputs

SPMF writes two `@` metadata lines and then the itemsets in mining order, so a comparator parses both files into maps instead of comparing bytes. The comparator canonicalizes both outputs and then reports:

- itemsets missing from either side,
- itemsets that appear more than once,
- support mismatches.

Test the comparator on deliberately corrupted outputs, one per failure kind, so a silent comparator cannot pass a broken miner. Keep the complete reference maps for the toy databases and the four benchmarks in [results/raw](../../results/raw/README.md).
