# Semeion output validation, 30 October 2026

Visual-word interpretation requires patches that actually contribute to the encoded transactions, and correctness comparisons require complete itemset/support outputs. This record checks the Semeion pilot after reviewing acquisition, representative selection, output retention, and script tests. The [pilot record](semeion-pilot-2026-10-24.md) gives the dataset and encoding rationale; [the manifest](../data/raw/manifest.toml) pins the source bytes.

## Review findings

| Concern | Verification and correction |
| --- | --- |
| Input hash only recorded | Confirmed in the CLI. It uses the shared `prepare_dataset` path to verify cached data and stage a verified replacement for a missing or corrupt file. Tests reject an HTML response without creating run output and exercise recovery. |
| Notebook downloads into the cache directly | Confirmed. Its Semeion cell calls the same verified runner as the CLI. |
| Representative belongs to another word or misses the cutoff | Confirmed with synthetic centers: the old method supplied a representative for an unused word. Selection uses nearest-word assignment and the encoder's cutoff, returning representatives only for used words. |
| Mining maps and supporting images discarded | Confirmed. Each threshold writes a complete `patterns-<minsup>.txt`, every itemset's supporting IDs and labels in `supporting_images.tsv`, and a selected source-image montage. |
| Fresh-directory curl command | Confirmed. The recorded manual command includes `-fL --create-dirs`; the runner also creates its input directory and prepares missing data. |
| Even-size median | Confirmed. The helper averages the two middle widths and has an even-size regression test. |
| Script untested | Confirmed. End-to-end tests cover argument count, input filename, output guard, all TSVs, full maps, support montages, verified cache reuse, rejected downloads, and corrupt-cache recovery. |
| Repeated item counting | Confirmed in the pilot and basket writer. `dataset_stats` used a distinct-ID set rather than frequencies. All three callers share `item_frequencies`, which counts an item once per transaction and preserves invalid-input checks. |
| Unsupported runtime characterization | Removed the pilot's claim that the thresholds are manageable. Raw elapsed times remain exploratory observations, rather than a benchmark conclusion. |
| Notebook heading punctuation | Replaced the Semeion heading's em dash with a colon. |

## Local checks

The implementation revision is `9794cf5`. The run used Windows, AMD Ryzen 5 6600H, Julia 1.13.2, and seed 42. The repository test suite passed 835/835. The editor compiled `docs/report/main.tex` successfully. This run does not establish that the earlier intermittent Windows peak-RSS assertion failure is fixed.

The verified-cache run is in ignored `results/raw/semeion-review-2026-10-30/`. A second run downloaded into a fresh input directory through the shared loader and wrote `results/raw/semeion-review-fresh-2026-10-30/`. Fourteen deterministic files have equal SHA-256 hashes across these runs: the summary, four encoding TSVs, two encoding SVGs, supporting-image TSV, three complete pattern files, and three supporting-image SVGs. Timing fields are excluded.

A separate check read the saved codebook, representatives, source pixels, transactions, and support mappings. All 24 representatives are assigned to their displayed word, have squared distance at most 1.0, and contribute that word to the source image's transaction. All 70 itemset rows across the three thresholds have exactly the recorded supporting image IDs, labels, and integer supports. Word 13 retains image 2, row 1, column 9, with pixels `1111000000000000`, so its short horizontal-stroke description remains supported. The saved maps give support 863 for word 13 and 330 for {8, 13}.

## Independent SPMF check

SPMF v2.66 JAR SHA-256 is `4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a`. The executable run used Temurin Java 25.0.4.1. SPMF receives 1,582 nonempty transactions; the Julia run retains all 1,593 images. Removing the 11 empty records preserves every nonempty itemset's support, but requires adjusting the reference fraction to produce the same integer count.

| Julia minsup | Required count | SPMF fraction on 1,582 rows | Exact itemset/support pairs |
| ---: | ---: | ---: | ---: |
| 0.20 | 319 | 0.2013274336283186 | 6/6 |
| 0.10 | 160 | 0.10082174462705436 | 18/18 |
| 0.05 | 80 | 0.05025284450063211 | 46/46 |

Each SPMF fraction is `(required_count - 0.5) / 1582`, safely inside the interval whose ceiling is the required count. All three complete-map comparisons have zero missing, extra, duplicate, or support-mismatched itemsets and a 100% exact-map match rate.

## Reproduce

Run from the repository root with the pinned Julia environment. The runner prepares the source file if needed:

```powershell
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. scripts/image_pilot.jl data/raw/semeion/semeion.data results/raw/semeion-review-run
julia --startup-file=no --project=. -e 'using ItemsetMining; rows=split.(readlines(ARGS[1])[2:end], Char(9)); tx=[parse.(Int, split(row[3], Char(44))) for row in rows if !isempty(row[3])]; write_transactions(ARGS[2], tx)' results/raw/semeion-review-run/transactions.tsv results/raw/semeion-review-run/transactions-numeric.txt
```

Use the JAR and Java described in [the SPMF protocol](../tools/spmf/README.md). In PowerShell, the following checks each integer threshold and compares complete outputs:

```powershell
$runDir = 'results/raw/semeion-review-run'
foreach ($pair in @(@('0.2',319), @('0.1',160), @('0.05',80))) {
    $fraction = ($pair[1] - 0.5) / 1582
    if ([Math]::Ceiling($fraction * 1582) -ne $pair[1]) { throw 'Threshold mismatch' }
    $argument = $fraction.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    java -jar tools/spmf/spmf.jar run Eclat "$runDir/transactions-numeric.txt" "$runDir/spmf-$($pair[0]).txt" $argument
    julia --startup-file=no --project=. tools/spmf/compare.jl "$runDir/spmf-$($pair[0]).txt" "$runDir/patterns-$($pair[0]).txt"
    if ($LASTEXITCODE -ne 0) { throw 'Reference comparison failed' }
}
```

Keep raw outputs, commands, logs, and the validation script with the run evidence. The notebook uses the same verified pipeline; a hosted Colab run is not claimed here.
