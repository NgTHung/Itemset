# Correctness database

The toy fixtures in [data/toy](../toy/README.md) are small enough to check by hand, but their largest map has 7 itemsets and none is longer than 3 items, so a bug that appears only deep in the recursion or only across many equivalence classes passes them. The benchmarks are large enough to expose such bugs, but they stay out of Git and take minutes, so the test suite cannot run them. This folder holds one mid-size database and its complete SPMF map, and `tests/eclat.jl` compares every Eclat variant with that map on each run.

## Database

`t25i10d10k.txt` is a synthetic database from the IBM Quest generator, downloaded unmodified from the [SPMF dataset catalog](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php) on 2026-10-29. The name gives the generator's parameters: mean transaction width 25, mean planted pattern size 10, and 10,000 transactions; the SPMF copy has 9,976.

| SHA-256 | Transactions | Items | Mean width | Max width | Item IDs |
|---|---|---|---|---|---|
| `bada34032cae267782302bcc2225e8813ef4a8329d659453cb732b036b170f2e` | 9,976 | 929 | 24.77 | 63 | 1 to 1,000 |

At minsup 0.008, a count of 80 transactions, its map tests what the toys cannot:

- 14,782 itemsets, with every length from 1 to 13. The planted patterns make long itemsets frequent in sparse data, a case that the dense Chess and Mushroom benchmarks do not cover.
- 711 frequent items, so the first level builds 252,405 candidate pairs, as the sparse benchmarks do.
- 383 itemsets whose support equals the count exactly, so an off-by-one threshold error changes the map.
- 71 unused IDs in 1 to 1,000 and 319 repeated transactions, so item compaction and transaction counting must be exact.

The input satisfies SPMF's format without rewriting: positive IDs, items sorted within each transaction, no repeated item. Other candidates were rejected. SPMF's Eclat runs out of its default heap on BMS-WebView-1 because it sizes a triangular matrix by the largest item ID, 60,977. Foodmart and Liquor have unsorted or repeated items, which SPMF's input format does not allow.

## Reference output

`spmf/runs.toml` pins the input's SHA-256, the minsup, and the count. `spmf/t25i10d10k-0.008.txt` is SPMF v2.66's raw Eclat output, unmodified apart from Git's line-ending normalization. It was produced with `tools/spmf/reference_outputs.jl`, which [tools/spmf](../../tools/spmf/README.md#reference-outputs) describes, on Temurin Java 25.0.4.1.

The baseline matched it with no missing, extra, or mismatched itemsets. On an Intel Core i7-12700H with Julia 1.13.2, the baseline's warmed `mine` call takes 11.9 s and allocates 4.9 GiB at this threshold, which is the main cost this database adds to the test suite.

The map is one independent program's answer, not a proof. A bug shared by SPMF and the miner would pass it, so the toy fixtures, the brute-force oracle tests, and the benchmark comparisons stay in place.
