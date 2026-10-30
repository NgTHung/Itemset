# Semeion image pilot, 24 October 2026

Handwritten digits provide a small real image set for checking whether local stroke fragments form interpretable frequent visual-word sets. The pilot asks which 4×4 stroke patterns recur across digits and within each digit label. It uses the original [UCI Semeion Handwritten Digit dataset](https://archive.ics.uci.edu/dataset/178/semeion+handwritten+digit), 1,593 binary 16×16 images from about 80 people under CC BY 4.0. The raw file stays outside Git.

## Reproduce

The official `semeion.data` file is 2,889,702 bytes. Its SHA-256 is `f43228ae3da5ea6a3c95069d53450b86166770e3b719dcc333182128fe08d4b1`. The accompanying `semeion.names` SHA-256 is `d7b5e6469a897fbe16a10a57ecfa6b4fcbf32ba45c539c61877be1626d564d78`. The [dataset source](https://archive.ics.uci.edu/ml/machine-learning-databases/semeion/semeion.data) is the input to these commands, run from the repository root:

```sh
curl -fL --create-dirs https://archive.ics.uci.edu/ml/machine-learning-databases/semeion/semeion.data -o data/raw/semeion/semeion.data
sha256sum data/raw/semeion/semeion.data
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. scripts/image_pilot.jl data/raw/semeion/semeion.data results/raw/semeion-pilot-2026-10-24
```

The recorded run used Julia 1.13.2 on Windows with `DEFAULT_SEED=42`. The raw TSVs and SVGs are in ignored `results/raw/semeion-pilot-2026-10-24/`. `summary.txt` records the source hash and settings. `transactions.tsv` preserves the image ID, label, and exact word set; `representatives.tsv` maps each word to an observed source patch. `digits.svg` shows the first source image for each label, and `visual_words.svg` shows one observed patch for every codebook word.

## Encoding decision

Each image contributes 16 nonoverlapping 4×4 binary patches. A patch with fewer than two foreground pixels is omitted. A seeded 25-iteration k-means fit produces 24 centers from the 18,386 retained patches. The nearest center is present in a transaction when squared Euclidean distance is at most 1.0. Repeated assignments to one word count once; an image with no accepted assignment remains an empty transaction. Word IDs are the 1-based codebook columns.

Trial settings on the same file motivated the distance cutoff: with 24 words and minimum ink 2, cutoff 4.0 gave median width 9 and no empty images; cutoff 2.0 gave median width 8 and no empty images; cutoff 1.0 gave median width 4 and 11 empty images. The last setting leaves a smaller transaction while retaining all 24 words. These trials are encoding choices, not evidence of classification accuracy.

## Observed result

The 1,593 transactions have width 0 to 8, median 4, and 11 are empty. All 24 words occur. The counts of digit labels 0 through 9 are 161, 162, 159, 159, 161, 159, 161, 158, 155, and 158. Baseline Eclat returned the following complete itemset counts:

| Relative support | Minimum image count | Itemsets |
|---:|---:|---:|
| 0.20 | 319 | 6 |
| 0.10 | 160 | 18 |
| 0.05 | 80 | 46 |

The most common word is 13, appearing in 863 images. Its nearest observed patch, image 2 at row 1, column 9, is a short horizontal stroke. The word set {8, 13} occurs in 330 images. The transaction table permits an exact scan of its supporting image IDs and labels; the SVGs help inspect the original pixels and patches. A visual word is a quantized local shape, not a semantic digit part. The transaction discards patch position and repeat count, so co-occurrence alone does not establish a digit-specific feature or predictive performance.

The pilot records itemset counts at these three thresholds. It does not establish a runtime benchmark, an independent SPMF correctness comparison, or a hosted Colab run. The [30 October validation record](semeion-validation-2026-10-30.md) gives later reruns and independent comparisons.
