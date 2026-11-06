# Deterministic Semeion encoding, 31 October 2026

Image-pattern mining needs a fixed image-to-word map so a support count refers to the same visual feature in every run. The encoder fits one descriptive codebook to the complete Semeion dataset, retains empty images, and preserves source IDs and representative patch coordinates. This record supplies the encoding evidence for [DAT-15](https://linear.app/nguyen-tuan-hung/issue/DAT-15/phat-finalize-deterministic-image-to-transaction-encoding); [the pilot record](semeion-pilot-2026-10-24.md) owns the dataset rationale and earlier tuning.

## Frozen pipeline

Implementation revision `2061916` extends the reviewed DAT-11 pilot at `a8bca9b`. `SemeionPilot.EncodingSettings` records seed 42, vocabulary size 24, minimum ink 2, 25 k-means iterations, and squared-distance cutoff 1.0. Patches are nonoverlapping 4×4 binary pixel vectors extracted in image/row/column order. The nearest center receives a patch, with equal distances choosing the smaller word ID. Every fit constructs a private Xoshiro RNG from the recorded seed. Reproduction targets Julia 1.13.2 because seeded streams need not match across Julia minor versions.

`prepare_encoding` returns images, codebook, word sets and observed representative patches together. `write_encoding` checks image-to-word assignments, source references and representative eligibility before publishing a staged output directory. Word IDs are codebook column numbers; repeated words within an image collapse. Source IDs and digit labels stay aligned with transaction rows, including empty word fields. The preprocessing command and mining pilot share this preparation and artifact-writing path. No dependency was added to the project environment.

The whole dataset fits the codebook for descriptive co-occurrence analysis. No classification or generalization accuracy is claimed. An evaluation on unseen images would require a training-only codebook fit and a separate evaluation set. Transactions discard patch position and multiplicity; representative source coordinates remain in the evidence for interpretation.

## Measured encoding

Both full-data runs use the source hash pinned in [data/raw/manifest.toml](../data/raw/manifest.toml). The outputs agree with the reviewed pilot's transaction, codebook, frequency, representative and SVG files.

| Measurement | Value |
| --- | ---: |
| Images, including empty transactions | 1,593 |
| Retained patches / distinct patches | 18,386 / 2,251 |
| Vocabulary / used words | 24 / 24 |
| Total image-word presences | 5,767 |
| Width minimum / median / maximum | 0 / 4 / 8 |
| Mean width | 3.6202134338 |
| Empty transactions | 11 |
| Density, presences divided by images × vocabulary size | 0.1508422264 |

The exact width distribution is 11, 100, 256, 401, 404, 252, 115, 46 and 8 images at widths 0 through 8 respectively. `word_frequencies.tsv` contains one image count for each word, including zero for any unused word.

## Artifact contract

| Artifact | Evidence |
| --- | --- |
| `manifest.toml` | Source URL and SHA-256, Julia version, Git revision and dirty flag, exact command arguments, frozen settings, statistics and eight artifact hashes |
| `transactions.tsv` | Source image ID, digit label and sorted distinct word IDs; empty fields preserve empty images |
| `codebook.tsv` | Sixteen center coordinates for each 1-based word ID |
| `word_frequencies.tsv`, `widths.tsv` | Per-word image frequency and exact transaction-width distribution |
| `representatives.tsv` | Word ID, source image ID, row, column, squared distance and observed row-major patch pixels |
| `digits.svg`, `visual_words.svg` | Source digits and accepted observed representative patches |
| `summary.txt` | Settings and aggregate statistics for terminal inspection |

The manifest hashes the eight encoding artifacts, excluding itself. Manifests differ between output locations because they retain exact command arguments; artifact hashes and frozen statistics match. Extra mining files written by `image_pilot.jl` are outside this encoding manifest.

## Verification and reproduction

New tests first failed on missing encoding and preprocessing entry points, then passed after implementation. The final repository suite passed 873/873 on Windows with Julia 1.13.2. Tests cover duplicate IDs, invalid settings, exact cutoff boundaries, empty images, all-rejected assignments, validation before publishing, median/density on an even-size fixture, manifest contents and artifact hashes. The report compiled with the editor's built-in compiler.

Two clean runs at `2061916` wrote ignored `results/raw/dat-15-2026-10-31-a/` and `results/raw/dat-15-2026-10-31-b/`, with `git_dirty=false`. All eight encoding artifact hashes match. Six files match the prior independent SPMF-validated pilot byte for byte. A separate saved-output check validates all 24 representative source pixels, nearest-word assignments and distance cutoffs. The notebook's exact preprocessing cell executed locally and produced the same encoding artifact hashes; hosted Colab execution is not claimed.

Run from the repository root with the pinned environment and fresh output directories:

```sh
julia --startup-file=no --project=. scripts/check_setup.jl
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. scripts/encode_images.jl data/raw/semeion/semeion.data results/raw/semeion-encoding-a
julia --startup-file=no --project=. scripts/encode_images.jl data/raw/semeion/semeion.data results/raw/semeion-encoding-b
```

The command uses the shared manifest loader to stage and verify missing or corrupt input. Compare the two manifests' `artifact_sha256` tables and verify each listed file against its hash. The evidence archive contains both runs, the final test log, the independent validator, and the extracted notebook cell and its execution log. Mining, further pattern interpretation, and the validated-baseline release gate remain tracked in DAT-16 and DAT-13.
