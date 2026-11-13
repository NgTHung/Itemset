# Colab notebook

Graders run the project through one public Colab notebook, and a section that fails at runtime earns no marks. `demo.ipynb` therefore runs top to bottom from a clean runtime, on Colab's native Julia kernel, and calls the package directly.

## Provide the source

The first cell takes the repository from one of two sources:

- a public Git URL with an explicit commit, so the run is pinned to a revision,
- a ZIP of the committed tree uploaded to `/content/Itemset-colab.zip`, made with `git archive --format=zip --output=../Itemset-colab.zip HEAD`.

The notebook then activates and instantiates the repository environment, which needs network access. Select runtime version 2026.07 (Julia 1.12.6) or a newer compatible runtime; see [Colab runtime versions](https://research.google.com/colaboratory/runtime-version-faq.html). The steps to open the notebook are in the [root README](../README.md#run-on-colab).

## Record the run

The notebook prints its Julia version, thread count, project path, and seed. Record those values with every result it produces, because Colab runtimes change between sessions.

## Run through the Colab CLI

The CLI executes Python. `scripts/run_colab_notebook.py` installs hash-verified Julia 1.13.2 and Java 25 on a Linux CPU runtime, clones an exact commit and executes every code cell from `demo.ipynb` in source order in one fresh Julia subprocess. This checks hosted computation; interactive rendering in the native Julia frontend is separate. The SPMF JAR must match the hash in [the reference protocol](../tools/spmf/README.md).

After authenticating the installed `google-colab-cli`, set `PYTHONUTF8=1` and `PYTHONIOENCODING=utf-8` in Windows PowerShell. Create a local Python launcher with an exact pushed commit:

```python
import os, runpy
os.environ["ITEMSET_REVISION"] = "REPLACE_WITH_EXACT_40_CHARACTER_COMMIT_SHA"
runpy.run_path("/content/run_colab_notebook.py", run_name="__main__")
```

Run these commands from the repository root, replacing `launcher.py` with that file:

```sh
colab new --session itemset-cleanrun
colab upload --session itemset-cleanrun scripts/run_colab_notebook.py /content/run_colab_notebook.py
colab upload --session itemset-cleanrun tools/spmf/spmf.jar /content/itemset-spmf.jar
colab exec --session itemset-cleanrun --timeout 3600 --file launcher.py
colab download --session itemset-cleanrun /content/itemset-cleanrun-evidence.zip results/raw/colab-cleanrun.zip
colab stop --session itemset-cleanrun
```

The ZIP contains exact cell sources, logs, application outputs, comparisons, measurements and `result.json` with versions, revision and artifact hashes. Require `status=success`, every cell completion marker and both SPMF comparisons before accepting a run. A failure retains its log and creates an evidence ZIP. If the CLI disconnects, inspect the remote log and session state before retrying. Download evidence before stopping the session; use fresh root and evidence paths for another attempt.
