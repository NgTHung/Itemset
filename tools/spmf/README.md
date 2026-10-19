# SPMF reference runs

Hand-derived fixtures can share the same mistake as the miner they test. An independent run of the SPMF Java library gives a second implementation to compare against, so a support error shows up as a disagreement between two programs written by different people.

## Run SPMF

1. Download the executable JAR from [SPMF](https://www.philippe-fournier-viger.com/spmf/download.php) into this folder. Git ignores `*.jar` files here.
2. Record the SPMF version, the JAR's SHA-256, and the output of `java -version`.
3. Read the Eclat entry in the [SPMF documentation](https://www.philippe-fournier-viger.com/spmf/documentation.php) for that release, and check how its command line interprets the support threshold before you convert one of ours.
4. Record every command and threshold exactly as run.

Use SPMF only as an executable. Never copy its Java source into the miner.

## Compare outputs

The comparator canonicalizes both outputs and then reports:

- itemsets missing from either side,
- itemsets that appear more than once,
- support mismatches.

Test the comparator on deliberately corrupted outputs, one per failure kind, so a silent comparator cannot pass a broken miner. Keep the complete reference maps for the five toy databases and the four benchmarks in [results/raw](../../results/raw/README.md).
