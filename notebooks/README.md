# Colab notebook

Graders run the project through one public Colab notebook, and a section that fails at runtime earns no marks. `demo.ipynb` therefore runs top to bottom from a clean runtime, on Colab's native Julia kernel, and calls the package directly.

## Provide the source

The first cell takes the repository from one of two sources:

- a public Git URL with an explicit commit, so the run is pinned to a revision,
- a ZIP of the committed tree uploaded to `/content/Itemset-colab.zip`, made with `git archive --format=zip --output=../Itemset-colab.zip HEAD`.

The notebook then activates and instantiates the repository environment, which needs network access. Select runtime version 2026.07 (Julia 1.12.6) or a newer compatible runtime; see [Colab runtime versions](https://research.google.com/colaboratory/runtime-version-faq.html). The steps to open the notebook are in the [root README](../README.md#run-on-colab).

## Record the run

The notebook prints its Julia version, thread count, project path, and seed. Record those values with every result it produces, because Colab runtimes change between sessions.