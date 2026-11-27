# Colab notebooks

The Eclat demo and each application have their own notebook, so a failure in one does not hide the others and each file has one purpose. The notebooks call Julia code that lives in `applications/` and `scripts/`, so a notebook holds only the steps that run it.

## Eclat demo

Open [demo_colab.ipynb on Colab](https://colab.research.google.com/github/NgTHung/Itemset/blob/main/notebooks/demo_colab.ipynb) on a Python CPU runtime and run all cells. It resolves the repository's default branch to an exact commit, checks the downloaded Julia, Java and SPMF files against pinned SHA-256 hashes, and runs every code cell from `demo_local.ipynb` in one Julia process. These cells show the engine: toy mining, benchmarks, runtime against minsup, transaction width, the stage profile, and the exact comparison with SPMF.

To replay a run, replace the empty `ITEMSET_REVISION = ""` in the first code cell with the full 40-character lowercase commit SHA. Choose a commit that contains this notebook, its companion runner and `tools/spmf/release.toml`. For earlier commits, use the runner and setup in the [dated verification record](../docs/phat-application2-colab-2026-11-13.md). To run a GitHub fork, set the `ITEMSET_REPOSITORY` environment variable to its HTTPS clone URL, such as `https://github.com/owner/repo`.

The first code cell prints the evidence ZIP path as `EVIDENCE_ARCHIVE`. Download it through the Colab Files sidebar. `result.json` records the repository, revision, versions, SPMF source, completed cell IDs and artifact hashes. `commands.log` holds the execution log. The ZIP also contains the two exact-map comparisons and memory measurements on Chess at 90% minsup. The [report guide](../docs/report/README.md) gives the commands for the full experimental series.

## Run an application

[market_basket_colab.ipynb](https://colab.research.google.com/github/NgTHung/Itemset/blob/main/notebooks/market_basket_colab.ipynb) and [image_patterns_colab.ipynb](https://colab.research.google.com/github/NgTHung/Itemset/blob/main/notebooks/image_patterns_colab.ipynb) each run one application on a Python CPU runtime and need no Java. Both share one setup cell, which installs Julia 1.13.2 with the same pinned SHA-256 as the runner and checks out an exact commit. `tests/test_notebook_split.py` keeps the two copies identical. Both then run the package tests and one application script. Set `ITEMSET_REVISION` in the first code cell to replay a commit.

- `market_basket_colab.ipynb` cleans Online Retail II, mines the baskets, and shows the top-10 rules by lift. It takes about ten minutes. The evidence ZIP `/content/itemset-market-basket-evidence.zip` holds the result tables, `cleaning.tsv`, and `result.json` with the revision, the Julia version, and the SHA-256 of every file.
- `image_patterns_colab.ipynb` encodes Semeion, mines three thresholds, and shows tables and images that illustrate the patterns. Julia uses the [shared data loader](../applications/image_patterns/README.md#encoding). Each run writes a separate results directory and an evidence ZIP under `/content`. The final cells read the last completed run on disk. The ZIP records the verified input hash and the download URL if the run fetched the data.

`tests/test_notebook_market_basket.py` and `tests/test_notebook_image_patterns.py` check the pins, the step order, and the repository paths and outputs of each notebook without a Colab runtime.

## Run locally

`demo_local.ipynb`, `market_basket_local.ipynb` and `image_patterns_local.ipynb` run the same analyses on a Julia kernel in an IDE. The first cell finds an existing checkout from the repository root, from `notebooks/`, or from `ITEMSET_ROOT` when you set it. The second cell activates the project and installs its dependencies.

Use Julia 1.13.2, the version of the pins and of every recorded result. The setup accepts any 1.x from 1.12. The SPMF comparison in `demo_local.ipynb` needs Java 25 and the JAR from the [reference protocol](../tools/spmf/README.md).

## Run through the Colab CLI

The CLI runs the same Python script on a hosted CPU runtime. For a local copy of the JAR, upload it and pass its path with `--spmf-jar`. The script checks that copy against the same SHA-256.

After authenticating the installed `google-colab-cli`, enable UTF-8 in Windows PowerShell. For the Microsoft Store Python installation:

```powershell
$colabCli = Join-Path $env:LOCALAPPDATA 'Packages/PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0/LocalCache/local-packages/Python313/Scripts/colab.exe'
Set-Alias colab $colabCli
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
```

Create a local Python launcher with an exact pushed commit:

```python
import os, runpy
os.environ["ITEMSET_REVISION"] = "REPLACE_WITH_EXACT_40_CHARACTER_COMMIT_SHA"
runner = runpy.run_path("/content/run_colab_notebook.py")
args = ["--repository", "https://github.com/NgTHung/Itemset"]
# For an uploaded JAR, add ["--spmf-jar", "/content/itemset-spmf.jar"] to args.
if runner["main"](args) != 0:
    raise RuntimeError("Notebook execution failed; inspect the evidence ZIP")
```

Run these commands from the repository root, replacing `launcher.py` with that file:

```sh
colab new --session itemset-cleanrun
colab upload --session itemset-cleanrun scripts/run_colab_notebook.py /content/run_colab_notebook.py
colab exec --session itemset-cleanrun --timeout 3600 --file launcher.py
colab download --session itemset-cleanrun /content/itemset-cleanrun-evidence.zip results/raw/colab-cleanrun.zip
colab stop --session itemset-cleanrun
```

The notebook writes an artifact manifest for the runner. The evidence ZIP contains
that manifest, cell sources, logs, application outputs, comparisons, measurements
and `result.json` with versions, revision and artifact hashes. Require
`status=success`, every cell completion marker and both SPMF comparisons before
accepting a run. Once the runner starts a run, failures retain their logs and create an evidence ZIP.
Bootstrap errors such as an invalid URL or SHA appear in the first cell's output. If the CLI
disconnects, inspect the remote log and session state before retrying. Download
evidence before stopping the session. Use fresh root and evidence paths for another attempt.
