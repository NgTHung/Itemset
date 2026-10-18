# Notebook integration

`demo.ipynb` uses Colab's native **Julia** kernel. Open it and select
**Runtime → Change runtime type → Julia**. It accepts either a future public Git
URL + explicit commit or a local tracked-repository ZIP. For local work, export
`git archive --format=zip --output=../Itemset-colab.zip HEAD`, then upload the ZIP
through Colab's Files sidebar to `/content/Itemset-colab.zip` before running cells.
No Python bootstrap or separate Julia installation is needed.

Starter cells run setup, tests, and input inspection. There are no saved mining
results. `Pkg.activate`/`Pkg.instantiate` selects the repository environment, then
the notebook calls Julia code directly. Package setup/data access requires network
access. The supported runtime is Julia 1.12+ within 1.x; local default stays 1.13.2.
For a documented Colab option, select runtime version 2026.07 (Julia 1.12.6) or a
newer compatible runtime; [runtime details](https://research.google.com/colaboratory/runtime-version-faq.html).
Record the exact runtime, thread count, and seed printed by the notebook with final
results. Local execution is not a live clean Colab run (DAT-7/DAT-25).

Hung supplies Eclat/scalability/counts, Thien baskets/runtime/width, Phat images/
correctness/memory. Each author installs approved dependencies and fixes their own
module before Phat assembles it. Final notebooks must run top-to-bottom without
hidden state and expose exact data/parameters/revision.
