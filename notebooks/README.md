# Colab notebooks

The Eclat demo and each application have their own notebook, so a failure in one does not hide the others and each file has one purpose. The notebooks call Julia code that lives in `demo.jl`, `experiments/`, `applications/` and `scripts/`, so a notebook holds only the steps that run it.

## Eclat demo

Open [demo_colab.ipynb on Colab](https://colab.research.google.com/github/NgTHung/Itemset/blob/main/notebooks/demo_colab.ipynb) on a Python CPU runtime and run all cells. Each step is its own cell and prints its own output, so a viewer can follow the run from top to bottom. After the two install cells, each command step is a `%%shell` cell with the same commands you would type in a terminal from the repository root. `set -euo pipefail` makes the first failing command stop the notebook. Python cells only read, check and display what the commands wrote:

1. Install Julia 1.13.2 and check out the default branch at an exact commit, with the setup cell that the application notebooks share.
2. Install Java 25 and the SPMF JAR, each checked against its pinned SHA-256. The JAR pin lives in `tools/spmf/release.toml`.
3. Install the package and run its tests.
4. Mine `data/toy/baskets.txt` with `demo.jl` and compare the output with the hand-derived `baskets.expected.txt`.
5. Download Mushroom, check its SHA-256, mine it at minsup 0.3 with both variants, and show the ten longest itemsets.
6. Run `experiments/configs/demo-mushroom.toml`, which times baseline, optimized and SPMF at five thresholds and compares every output with SPMF as complete maps. A table and a chart show the output size and the runtime against minsup.
7. Write the evidence ZIP `/content/itemset-demo-evidence.zip` with `runs.csv`, the per-attempt `comparison.toml` files, and `result.json` with the revision, the Julia and Java versions, and the SHA-256 of every file.

To replay a run, replace the empty `ITEMSET_REVISION = ""` in the first code cell with the full 40-character lowercase commit SHA. The demo shows one cold run per point. The [report guide](../docs/report/README.md) gives the commands for the full experimental series.

## Run an application

[market_basket_colab.ipynb](https://colab.research.google.com/github/NgTHung/Itemset/blob/main/notebooks/market_basket_colab.ipynb) and [image_patterns_colab.ipynb](https://colab.research.google.com/github/NgTHung/Itemset/blob/main/notebooks/image_patterns_colab.ipynb) each run one application on a Python CPU runtime and need no Java. All three Colab notebooks share one setup cell, which installs Julia 1.13.2 with a pinned SHA-256 and checks out an exact commit. `tests/test_notebook_split.py` and `tests/test_notebook_demo_colab.py` keep the copies identical. Both application notebooks then run the package tests and one application script. Set `ITEMSET_REVISION` in the first code cell to replay a commit.

- `market_basket_colab.ipynb` cleans Online Retail II, mines the baskets, and shows the top-10 rules by lift. It takes about ten minutes. The evidence ZIP `/content/itemset-market-basket-evidence.zip` holds the result tables, `cleaning.tsv`, and `result.json` with the revision, the Julia version, and the SHA-256 of every file.
- `image_patterns_colab.ipynb` encodes Semeion, mines three thresholds, and shows tables and images that illustrate the patterns. Julia uses the [shared data loader](../applications/image_patterns/README.md#encoding). Each run writes a separate results directory and an evidence ZIP under `/content`. The final cells read the last completed run on disk. The ZIP records the verified input hash and the download URL if the run fetched the data.

`tests/test_notebook_demo_colab.py`, `tests/test_notebook_market_basket.py` and `tests/test_notebook_image_patterns.py` check the pins, the step order, and the repository paths and outputs of each notebook without a Colab runtime.

## Run locally

`demo_local.ipynb`, `market_basket_local.ipynb` and `image_patterns_local.ipynb` run the same analyses on a Julia kernel in an IDE. The first cell finds an existing checkout from the repository root, from `notebooks/`, or from `ITEMSET_ROOT` when you set it. The second cell activates the project and installs its dependencies. `demo_local.ipynb` uses the cell IDs of `demo_colab.ipynb` and prints the same tables, without the chart. Before each step's output it prints the terminal command that the step runs.

Use Julia 1.13.2, the version of the pins and of every recorded result. The setup accepts any 1.x from 1.12. The SPMF comparison in `demo_local.ipynb` needs Java 25 and the JAR from the [reference protocol](../tools/spmf/README.md); without them the cell says so and skips the comparison.
