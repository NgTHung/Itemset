# Semeion visual-word patterns, 31 October 2026

Frequent visual-word sets need traceable source images before their stroke patterns can be interpreted. This run mines the [frozen Semeion encoding](semeion-encoding-2026-10-31.md), saves every itemset and integer support, and compares accepted source patches with nonmatching images. It supplies the implementation and evidence for [DAT-16](https://linear.app/nguyen-tuan-hung/issue/DAT-16/phat-mine-visual-word-patterns-using-the-validated-eclat-baseline). Linear owns completion status and its dependency on Hung's DAT-13 baseline release.

## Pinned run

Application revision `1566aad` runs `variant=:baseline` through the public `mine` API. Both clean runs retain 1,593 images, including 11 empty transactions, and the source hash and settings recorded by the encoding manifest. `mining_manifest.toml` records the application revision, dirty flag, exact command, all miner source-file hashes, CPU, threads, timing boundary, output bytes and artifact hashes. No process timeout, pattern-length cap, or output truncation was applied to these runs.

The local machine used Windows, AMD Ryzen 5 6600H, Julia 1.13.2, and one Julia thread. Timing measures the `mine` call after one untimed warm-up at the first threshold; it excludes encoding, support scans, plotting and disk output. These are single-run observations, not a performance benchmark or an optimized-variant comparison.

| Relative minsup | Minimum image count | Complete itemsets | Pattern-file bytes | Mine seconds |
| ---: | ---: | ---: | ---: | ---: |
| 0.20 | 319 | 6 | 78 | 0.0007026 |
| 0.10 | 160 | 18 | 238 | 0.0100172 |
| 0.05 | 80 | 46 | 639 | 0.0095360 |

All maps are retained as `patterns-<minsup>.txt`. `supporting_images.tsv` lists every supporting source ID and digit label for every pattern, rather than only plotted examples. Every listed support was independently counted from the application's transactions.

## Selected patterns and contrasts

Selection is deterministic: the highest-support singleton, highest-support multiword set, then the longest set, with support and numeric IDs resolving ties. Duplicate selections collapse. Up to three matching images are shown in source-ID order. Nonmatching examples prefer the first match's digit label, then the greatest number of target words present, then source ID.

| Pattern | Support | Matching example IDs | Nonmatching example IDs |
| --- | ---: | --- | --- |
| {13} | 863 | 2, 3, 4 | 1, 5, 7 |
| {8,13} | 330 | 3, 11, 41 | 2, 4, 6 |
| {4,8,13} | 90 | 44, 46, 61 | 41, 42, 43 |

Word 13's accepted patches resemble a short horizontal stroke. Word 8's accepted patches contain a local filled band in the lower rows of the 4×4 patch. Their combination occurs in 69/159 digit-3 images and 9/161 digit-4 images. These frequencies describe this dataset and fitted codebook, without estimating classification or generalization accuracy.

The digit-0 image 3 contains both words 8 and 13; digit-0 image 2 contains word 13 but misses word 8 under the same cutoff. Digit-2 image 44 contains {4,8,13}, while digit-2 image 41 misses word 4. A missing word means a failed encoding assignment, not the proven absence of a semantic stroke. The displayed blue boxes locate accepted patches after mining; the itemset imposes no spatial or multiplicity relationship among them.

`selected_patterns.tsv` records counts for every digit label. `examples.tsv` records each displayed image, present target words and missing words. `example_patches.tsv` supplies the actual source coordinates, pixels and distance for each displayed present word. `examples-<minsup>-<index>.svg` shows each selected pattern; `supporting-<minsup>.svg` repeats the last, longest selection. The final triple montage was visually inspected, including its same-label nonmatching examples.

## Independent validation

Fresh SPMF Eclat runs validate the unchanged miner source on seven distinct toy databases and the mid-size correctness database, covering nine runs. Exact itemset/support pairs are baskets 6, duplicates 3, disjoint 0, dense 7, boundary 2 and 4 at its two counts, nested 3, groceries 5, and T25I10D10K 14,782. Every complete-map comparison reports zero missing, extra, duplicate or support-mismatched records. The baseline evidence records revision `5e88d3e`; its miner source hashes equal this application run's source hashes. The independent check and release evidence are supplied to DAT-13; its owner controls the baseline release.

The Semeion maps also match fresh SPMF output exactly: 6/6, 18/18 and 46/46 pairs. SPMF receives 1,582 nonempty transactions. Fractions `(count - 0.5) / 1582` give the same integer minimum counts 319, 160 and 80; dropping empty records changes no nonempty itemset's support. The reference uses the SPMF v2.66 JAR hash recorded in [the SPMF protocol](../tools/spmf/README.md) and Temurin Java 25.0.4.1.

The repository suite passed 914/914 on the pinned Julia version, including an inferred return-type check on the mining wrapper and exact `IMAGE_CASE` maps. Two clean runs have 25 matching deterministic artifact hashes; manifests and elapsed-time fields are excluded from equality because they record run arguments and timings. An independent saved-output check verifies all 70 support rows across thresholds, 42 displayed image examples and 51 displayed source patches. The exact notebook preprocessing and mining cells executed locally and reproduced the evidence. The report compiled with the editor's compiler. Hosted Colab execution is not claimed.

## Reproduce

Run from the repository root with a fresh output directory:

```sh
julia --startup-file=no --project=. scripts/check_setup.jl
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. scripts/mine_image_patterns.jl data/raw/semeion/semeion.data results/raw/semeion-patterns
```

The source loader verifies or stages the pinned raw file. The output includes the frozen encoding bundle plus complete maps, support mappings, contrasts, timings, output bytes and hashes. Mining and evidence construction finish in staging before the result directory is published. An error propagates without publishing a partial bundle.

Ignored evidence directories are `results/raw/dat-16-2026-10-31-a/`, `results/raw/dat-16-2026-10-31-b/`, and `results/raw/dat-16-baseline-check-2026-10-31/`. The attached ZIP includes all outputs, SPMF raw outputs/logs/diffs, exact reference commands, the independent validator, test log and extracted notebook cells. The validator also checks that application and independently validated baseline source hashes agree. Further threshold/vocabulary sensitivity and final image interpretation belong to DAT-18.
