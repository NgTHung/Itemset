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

## Labeled inputs

Input files with `@ITEM` labels make SPMF write label strings. For an integer-map comparison, write the same transactions without labels first:

```powershell
julia --startup-file=no --project=. -e 'using ItemsetMining; write_transactions(ARGS[2], read_transactions(ARGS[1]))' data/toy/groceries.txt results/raw/groceries-numeric.txt
```

## Thresholds

SPMF turns a fraction into a count as `ceil(minsup * N)` in `Float64`. On a database of 100 transactions where an item occurs 7 times, `0.07` and `7%` both drop that item, while `0.069` keeps it, so SPMF requires 8 transactions where `support_threshold(0.07, 100)` requires 7. Compare only thresholds where both counts agree; the harness checks this before it runs anything.

## Compare outputs

SPMF writes two `@` metadata lines and then the itemsets in mining order, so a comparator parses both files into maps instead of comparing bytes. The comparator canonicalizes both outputs and then reports:

- itemsets missing from either side,
- itemsets that appear more than once,
- support mismatches.

Run it with the reference file first and the candidate file second:

```powershell
julia --startup-file=no --project=. demo.jl --min-count 2 --variant baseline --output results/raw/baskets-julia.txt data/toy/baskets.txt
julia --startup-file=no --project=. tools/spmf/compare.jl results/raw/baskets-spmf.txt results/raw/baskets-julia.txt
```

The exact-map match rate is the number of itemsets that occur once in each map with equal support, divided by the distinct keys in the union of both maps. Two empty maps have a 100% rate. A duplicated itemset never counts as matching and makes the comparison fail, because its supports are ambiguous; the report lists each duplicate with its own support and line.

The exit code separates a wrong miner from a broken run:

- 0: the maps are equal.
- 1: any missing, extra, duplicated, or support-mismatched itemset.
- 2: a file is malformed. The message names the file and line.
- 3: a setup error, such as a wrong argument count or an unreadable file.

`tests/spmf_compare.jl` feeds the comparator one corrupted output per failure kind, so a silent comparator cannot pass a broken miner. Hand-derived files in `data/toy/` are test fixtures, not independent SPMF evidence.

## Toy reference outputs

SPMF's raw output for the toy databases lives in [data/toy/spmf](../../data/toy/README.md#spmf-reference-outputs), and the test suite compares every Eclat variant with it on each run. `data/toy/spmf/runs.toml` lists each run; a test checks that every fraction gives SPMF the same count as `support_threshold`. The boundary fixture runs at 0.5 (count 2 of 4) and 0.25 (count 1 of 4). To regenerate the outputs after a JAR or fixture change, run:

```sh
julia --startup-file=no --project=. tools/spmf/toy_reference.jl path/to/java
```

The script rewrites each input without `@ITEM` labels first, so SPMF writes item IDs. Review the resulting diff before committing it, because a changed output means SPMF and the fixture disagree.
