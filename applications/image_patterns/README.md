# Image-pattern mining

Images that share a visual pattern often share a set of local features, such as textures or edges. This workstream encodes each image as the set of visual words it contains, mines those sets with `ItemsetMining.mine`, and shows which word combinations recur across images. [data/raw/manifest.toml](../../data/raw/manifest.toml) pins the dataset bytes.
## Encoding

Run the frozen encoding without mining from the repository root:

```sh
julia --startup-file=no --project=. scripts/encode_images.jl data/raw/semeion/semeion.data results/raw/semeion-encoding
```

`SemeionPilot.prepare_encoding` fits the codebook with a private seed-42 RNG and returns image IDs, labels, codebook columns, word sets, and accepted source patches together. `write_encoding` validates their alignment and publishes a staged output directory. `manifest.toml` records source and artifact SHA-256 hashes, Julia and Git versions, command arguments, settings, image frequencies and width/density statistics. `widths.tsv` gives the exact width distribution; empty word fields in `transactions.tsv` retain empty images. Existing output paths are rejected. The notebook uses the same functions.

Select one real, publicly accessible image dataset and keep the raw files in [data/raw](../../data/raw/README.md). Explain and record:

- the local descriptor and how it is extracted,
- how the codebook is fitted, with its vocabulary size and `DEFAULT_SEED`,
- the presence threshold that turns a descriptor match into a visual word,
- whether images with no visual words are kept as empty transactions,
- the reversible mapping between visual words and integer IDs, and the codebook settings.

A transaction keeps only which words are present, so it loses each word's location and count. The report states that loss.

Image and plotting packages need team approval before they enter `Project.toml`.

The Semeion runner uses the shared dataset loader and seeded Julia patch encoder. It checks the cached `semeion.data` against [the raw-data manifest](../../data/raw/manifest.toml). If it needs a download, it tries the public Kaggle mirror, then UCI. It records the URL that supplied verified bytes and leaves the URL empty when it uses the verified cache. Run from the repository root:

```sh
julia --startup-file=no --project=. scripts/mine_image_patterns.jl data/raw/semeion/semeion.data results/raw/semeion-patterns
```

The output directory must not exist. `patterns-<minsup>.txt` holds complete baseline maps at three thresholds; `supporting_images.tsv` lists every supporting source ID and label. `mining_manifest.toml` records revision, miner source hashes, timing boundaries, CPU, threads, output bytes and artifact hashes. Timing covers each `mine` call after one untimed warm-up, excluding encoding and file output. No pattern cap is imposed. `scripts/image_pilot.jl` calls the same runner.

The runner selects the most supported singleton, most supported combination, and longest pattern, resolving ties by support then item IDs. `selected_patterns.tsv` records support and per-digit counts. `examples.tsv` and `example_patches.tsv` trace displayed source images and their actual accepted patches. The SVGs show up to three matches and three nonmatches; comparisons prefer the first match's digit label, then word overlap and source ID. Blue rectangles locate accepted patches in the original image. Missing words are labeled explicitly. The [image pattern notebooks](../../notebooks/README.md) displays these comparisons and writes `image_features.tsv`, one row per image and one column per pattern at the lowest threshold, through `scripts/image_features.jl`.

## Reproduce the sensitivity study

Run the miner for each vocabulary size. Every run records the itemset count and
integer support threshold in `thresholds.tsv`. The encoding command also accepts
`--vocabulary-size` for inspecting a codebook without mining.

```sh
for k in 16 24 32; do
  julia --startup-file=no --project=. scripts/mine_image_patterns.jl data/raw/semeion/semeion.data "results/raw/semeion-k$k" --vocabulary-size "$k" --minsup '0.20,0.10,0.06,0.055,0.05'
done
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_image_evidence.py data/raw/semeion/semeion.data results/raw/semeion-k24 results/figures/semeion-source-contrast.png
```

`manifest.toml` records each vocabulary's empty-transaction count. The figure
verifies the original pixels, digit labels, and accepted patches before drawing
images 44 and 41 from the run with a vocabulary of 24 words.

`label_frequencies.tsv` gives each pattern's support, full denominator, fraction and all supporting source IDs per digit, including empty images in the denominator. `pattern_label_summary(images, transactions, itemset)` produces those rows. `itemset_features(transactions, patterns)` returns a binary image-by-pattern matrix in the supplied column order. A feature is true only when every word in the pattern occurs. Fit the codebook and mine the pattern list on training images before transforming held-out images. The all-data mining run is descriptive.

## Deliverables

- Frequent visual-word sets with representative patches and supporting images.
- Sensitivity of the patterns to the support threshold and vocabulary size.
- Interpretation and limitations.
- A runnable notebook module and the report section.

Develop the encoding and visualization against `IMAGE_CASE` in `tests/fixtures.jl`, described in [data/toy](../../data/toy/README.md). Find an itemset's supporting images by scanning the application's own transactions, never from miner internals. Fixtures support development. Final patterns come only from the team's validated miner. A downstream classifier is optional.
