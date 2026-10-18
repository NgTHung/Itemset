# Itemset — Eclat mining project

Local Julia repository for the DataMining team's frequent-itemset assignment.
Scope: **Eclat**, **Market Basket Analysis**, and **image-pattern mining**.
[Linear project](https://linear.app/nguyen-tuan-hung/project/itemset-a5556236132d).
The original assignment is preserved in [docs/assignment.md](docs/assignment.md).

This is the project setup, not a completed miner. Package loading, SPMF transaction
I/O, support thresholds, fixture output, and input inspection run now. `mine` and
mining CLI commands deliberately fail until DAT-8 is implemented. No SPMF agreement,
benchmark performance, or completed application result is claimed by the setup tests.

## Install and verify

Use **Julia 1.13.2**, pinned in `.julia-version`, `Project.toml`, `Manifest.toml`,
CI, and the Colab bootstrap. Install from [official Julia downloads](https://julialang.org/downloads/)
or select it with `juliaup add 1.13.2`. Core setup has no third-party dependencies.

From the repository root:

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=. scripts/check_setup.jl
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. demo.jl --check-input data/toy/baskets.txt
```

`test/runtests.jl` delegates to `tests/runtests.jl` so the assignment command,
`julia --project test/runtests.jl`, works. `Pkg.test()` also uses that entry point.

On this Windows machine Julia is installed outside PATH. Use this PowerShell form
for each command above until Julia is on PATH:

```powershell
& "$env:LOCALAPPDATA\Programs\Julia-1.13.2\bin\julia.exe" --project=. scripts/check_setup.jl
```

Latest local setup-test evidence: [docs/setup-validation.md](docs/setup-validation.md).
Replace/add the final full miner/SPMF test output here before submission (DAT-28).

```text
2026-10-18 | Windows x86_64 | Julia 1.13.2
Test Summary: | Pass  Total
Itemset setup |   71     71
Testing ItemsetMining tests passed
```

This is setup-only evidence, not a completed algorithm-validation run.

## Shared API

```julia
using ItemsetMining
transactions = read_transactions("data/toy/baskets.txt")
count = support_threshold(0.5, length(transactions)) # 2
# Available after DAT-8:
# patterns = mine(transactions; minsup=0.5, variant=:baseline)
# write_itemsets("results/patterns.txt", patterns)
```

Integer `minsup=1` means count 1; floating `minsup=1.0` means 100%.
Output keys are sorted unique integer tuples, values are exact support counts.
See [docs/interface.md](docs/interface.md) before building either application.

Planned mining invocation, intentionally unavailable until the miner exists:

```sh
julia --project=. demo.jl --minsup 0.5 --variant baseline --output results/patterns.txt data/toy/baskets.txt
```

## Team handoffs

- **Hung:** Chapter 1, API/I/O/CLI, baseline and optimization, tests, scalability,
  output-size plots; review Thien's application; final repository integration.
- **Thien:** market baskets/rules, benchmark runner and protocol, runtime/width,
  future optimization proposals; review Phat; report assembly.
- **Phat:** image encoding/mining, independent SPMF comparison and memory,
  notebook assembly; review Hung.

Each author supplies their report sections and runnable notebook module. DAT-13
freezes the validated baseline; optimization does not gate application work.
[docs/project-plan.md](docs/project-plan.md) maps folders and next tasks.

## Layout and reproducibility

- `src/algorithm/`: paper-based Eclat implementations; shared types/I/O in `src/`.
- `tests/`, `test/`, `data/toy/`: setup tests, assignment entry point, five fixtures.
- `applications/market_basket/`, `applications/image_patterns/`: owner handoffs.
- `experiments/`: shared measurement protocol and result fields.
- `data/benchmark/`, `data/raw/`: local downloaded data, excluded from Git.
- `notebooks/demo.ipynb`: Python-kernel Colab bootstrap and Julia shell commands.
- `docs/report/`: Vietnamese IEEE report starter; final export is `docs/Report.pdf`.
- `tools/spmf/`: independent Java reference instructions; no SPMF source copied.
- `results/`: raw runs and generated figures, excluded from Git.

Fixed seed: **20261018**. Pass a seeded RNG to every stochastic preprocessing or
subset-selection step. Store data URL/license/SHA-256, reversible item mappings,
parameters, runtime/environment, and Git revision alongside each result.

Only Julia standard libraries are used initially. Image and plotting dependencies
remain subject to DAT-5 clarification; their owners must pin approved additions in
the environment and commit the regenerated Manifest. Never import a FIM library.

## Colab and submission links

No public repository or Colab URL exists yet: this setup is local only.
Run `git archive --format=zip --output=../Itemset-colab.zip HEAD` after a commit,
upload `notebooks/demo.ipynb` to [Google Colab](https://colab.research.google.com/),
then upload that ZIP when its first cell requests the repository. Use a Python
kernel with Julia invoked through subprocesses, as required by the assignment.
The notebook also accepts a future public GitHub URL and explicit commit.

Before submission, create the public GitHub repository, publish/clean-run the
notebook and add its public link here, add accessible Hugging Face/Kaggle data links
with checksums, and export `docs/Report.pdf`. The notebook is a setup demonstration;
each owner still supplies their actual application/experiment module.

## References

- Original paper: M. J. Zaki, *Scalable Algorithms for Association Mining*, IEEE
  TKDE 12(3), 372–390 (2000). [Paper hosted by SPMF](https://www.philippe-fournier-viger.com/spmf/zaki2000.pdf).
- [SPMF documentation](https://www.philippe-fournier-viger.com/spmf/documentation.php)
  and [dataset catalog](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php).
- [Julia release feed/checksums](https://julialang-s3.julialang.org/bin/versions.json).

Implement Eclat from the paper, retain authorship history, and be able to explain
all submitted code. Final application outputs must come from the team's miner.
