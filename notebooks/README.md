# Notebook integration

`demo.ipynb` uses Colab's Python kernel to install pinned official Julia and call
Julia subprocesses. It accepts either a future public Git URL + explicit commit
or a local tracked-repository ZIP. No public URL is invented for this local setup.

Starter cells run setup, tests, and input inspection. There are no saved mining
results. Runtime installation requires network access. Local tests exercise the
same Julia entry points; a real clean Colab run is still required for DAT-7/DAT-25.

Hung supplies Eclat/scalability/counts, Thien baskets/runtime/width, Phat images/
correctness/memory. Each author installs approved dependencies and fixes their own
module before Phat assembles it. Final notebooks must run top-to-bottom without
hidden state and expose exact data/parameters/revision.
