# Independent reference — Phat / DAT-9

Download the executable JAR from [SPMF](https://www.philippe-fournier-viger.com/spmf/download.php),
record its version and SHA-256 plus `java -version`, and use the Eclat entry in the
[official documentation](https://www.philippe-fournier-viger.com/spmf/documentation.php).
JAR files are ignored. Inspect the selected release's CLI support semantics before
running; record exact commands and thresholds. Do not copy Java source into the miner.

The comparator must detect missing/extra itemsets, duplicate output, and support
mismatches after canonicalization. Test deliberately corrupted outputs. Save complete
maps for five toy databases before DAT-13 and four benchmarks for DAT-32. A hand-made
expected fixture is not proof that the reference executable was run.
