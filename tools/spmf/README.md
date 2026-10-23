# SPMF reference runs

Hand-derived fixtures can share the same mistake as the miner they test. An independent run of the SPMF Java library gives a second implementation to compare against, so a support error shows up as a disagreement between two programs written by different people.

## Run SPMF

1. Download the executable JAR from [SPMF](https://www.philippe-fournier-viger.com/spmf/download.php) into this folder. Git ignores `*.jar` files here.
2. Record the SPMF version, the JAR's SHA-256, and the output of `java -version`.
3. Read the Eclat entry in the [SPMF documentation](https://www.philippe-fournier-viger.com/spmf/documentation.php) for that release, and check how its command line interprets the support threshold before you convert one of ours.
4. Record every command and threshold exactly as run.

Use SPMF only as an executable. Never copy its Java source into the miner.

Use a Java runtime compatible with the downloaded JAR. The executable fetched
on 24 October 2026 requires Java 25. Input files with `@ITEM` labels make SPMF
write label strings. For an integer-map comparison, write the same transactions
without labels first:

```powershell
julia --startup-file=no --project=. -e 'using ItemsetMining; write_transactions(ARGS[2], read_transactions(ARGS[1]))' data/toy/groceries.txt results/raw/groceries-numeric.txt
```

SPMF accepts a relative minimum support percentage. Convert a fixture's count
threshold to a percentage whose ceiling over the transaction count is the same
count, and record both values. For `baskets.txt`, two of four transactions is
50%:

```powershell
New-Item -ItemType Directory -Force results/raw | Out-Null
Get-FileHash tools/spmf/spmf.jar -Algorithm SHA256
Get-FileHash data/toy/baskets.txt -Algorithm SHA256
java -version
java -jar tools/spmf/spmf.jar run Eclat data/toy/baskets.txt results/raw/baskets-spmf.txt 50%
```

Save each command and its stdout/stderr beside the raw reference output. Record
the SPMF version, JAR checksum, Java and Julia versions, Git revision, input
checksum, and both threshold forms.

## Compare outputs

The comparator canonicalizes both outputs and then reports:

- itemsets missing from either side,
- itemsets that appear more than once,
- support mismatches.

Run it with the reference file first and the candidate file second:

```powershell
julia --startup-file=no --project=. demo.jl --min-count 2 --variant baseline --output results/raw/baskets-julia.txt data/toy/baskets.txt
julia --startup-file=no --project=. tools/spmf/compare.jl results/raw/baskets-spmf.txt results/raw/baskets-julia.txt
```

The exact-map match rate is equal-support itemsets divided by the distinct keys
in the union of both maps. Two empty maps have a 100% rate. A duplicate key
makes the comparison fail even when its first occurrence agrees. A perfect
comparison exits with code 0; any difference exits with code 1; malformed
output exits with code 2.

Test the comparator on deliberately corrupted outputs, one per failure kind,
so a silent comparator cannot pass a broken miner. Generate reference outputs
for at least five distinct small databases and boundary thresholds, then
retain their complete maps and comparison evidence in
[results/raw](../../results/raw/README.md). The boundary fixture uses both
50% (count 2 of 4) and 25% (count 1 of 4). Hand-derived files in `data/toy/`
are test fixtures, not independent SPMF evidence. The dated
[toy validation record](../../docs/spmf-toy-validation-2026-10-24.md) reports
one run with complete-map results.
