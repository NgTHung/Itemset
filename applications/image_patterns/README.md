# Image-pattern mining

Images that share a visual pattern often share a set of local features, such as textures or edges. This workstream encodes each image as the set of visual words it contains, mines those sets with `ItemsetMining.mine`, and shows which word combinations recur across images. The [Semeion pilot record](../../docs/semeion-pilot-2026-10-24.md) gives the dataset checksum, settings, and measured output.
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

The Semeion runner uses the shared dataset loader and seeded Julia patch encoder. It verifies `semeion.data` against [the raw-data manifest](../../data/raw/manifest.toml), downloads missing data into a staging file, and replaces a corrupt cache only after the replacement verifies. Run from the repository root:

```sh
julia --startup-file=no --project=. scripts/mine_image_patterns.jl data/raw/semeion/semeion.data results/raw/semeion-patterns
```

The output directory must not exist. `patterns-<minsup>.txt` holds complete baseline maps at three thresholds; `supporting_images.tsv` lists every supporting source ID and label. `mining_manifest.toml` records revision, miner source hashes, timing boundaries, CPU, threads, output bytes and artifact hashes. Timing covers each `mine` call after one untimed warm-up, excluding encoding and file output. No pattern cap is imposed. `scripts/image_pilot.jl` calls the same runner.

The runner selects the most supported singleton, most supported combination, and longest pattern, resolving ties by support then item IDs. `selected_patterns.tsv` records support and per-digit counts. `examples.tsv` and `example_patches.tsv` trace displayed source images and their actual accepted patches. The SVGs show up to three matches and three nonmatches; comparisons prefer the first match's digit label, then word overlap and source ID. Blue rectangles locate accepted patches in the original image. Missing words are labeled explicitly. The [Julia notebook](../../notebooks/demo.ipynb) displays these comparisons.

## Deliverables

- Frequent visual-word sets with representative patches and supporting images.
- Sensitivity of the patterns to the support threshold and vocabulary size.
- Interpretation and limitations.
- A runnable notebook module and the Vietnamese report section.

Develop the encoding and visualization against `IMAGE_CASE` in `tests/fixtures.jl`, described in [data/toy](../../data/toy/README.md). Find an itemset's supporting images by scanning the application's own transactions, never from miner internals. Fixtures support development. Final patterns come only from the team's validated miner. A downstream classifier is optional.
