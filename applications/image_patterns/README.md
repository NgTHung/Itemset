# Image-pattern mining

Images that share a visual pattern often share a set of local features, such as textures or edges. This workstream encodes each image as the set of visual words it contains, mines those sets with `ItemsetMining.mine`, and shows which word combinations recur across images. The [Semeion pilot record](../../docs/semeion-pilot-2026-10-24.md) gives the dataset checksum, settings, and measured output.
## Encoding

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
julia --startup-file=no --project=. scripts/image_pilot.jl data/raw/semeion/semeion.data results/raw/semeion-pilot
```

The output directory must not exist. The runner writes transactions, word frequencies, codebook centers, accepted representative patches, and baseline Eclat results at three support thresholds. `patterns-<minsup>.txt` holds complete itemset/support maps. `supporting_images.tsv` lists every supporting image ID and label for each itemset; `supporting-<minsup>.svg` shows up to ten source images for the longest pattern, breaking ties by support and then item IDs. The [Julia notebook](../../notebooks/demo.ipynb) runs the same verified acquisition and pilot.

## Deliverables

- Frequent visual-word sets with representative patches and supporting images.
- Sensitivity of the patterns to the support threshold and vocabulary size.
- Interpretation and limitations.
- A runnable notebook module and the Vietnamese report section.

Develop the encoding and visualization against `IMAGE_CASE` in `tests/fixtures.jl`, described in [data/toy](../../data/toy/README.md). Find an itemset's supporting images by scanning the application's own transactions, never from miner internals. Fixtures support development. Final patterns come only from the team's validated miner. A downstream classifier is optional.
