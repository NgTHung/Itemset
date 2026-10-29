# Itemset

`ItemsetMining` is a Julia package that finds every frequent itemset in a transaction database with Eclat (Zaki, 2000). It serves the HCMUS Data Mining course project, where two applications, market basket analysis and image-pattern mining, call one shared `mine` function. Both applications therefore mine with the same validated code, and the benchmark results describe the code they use.

## Install and verify

Install [Julia](https://julialang.org/downloads/) 1.13.2, the version pinned in `.julia-version` and used to generate `Manifest.toml`, for example with `juliaup add 1.13.2`. The package accepts any Julia 1.x from 1.12 so that it runs on Colab's native Julia runtime. CI tests 1.12.6 and 1.13.2 on Ubuntu and Windows.

From the repository root:

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=. scripts/check_setup.jl
julia --startup-file=no --project=. test/runtests.jl
```

`test/runtests.jl` includes `tests/runtests.jl`, so the brief's command `julia --project test/runtests.jl` and `Pkg.test()` run the same suite.

Latest local test run, 2026-10-19, Windows x86_64, Julia 1.13.2. [docs/setup-validation.md](docs/setup-validation.md) records the environment validation.

```text
Test Summary: | Pass  Total
Itemset setup |  490    490
Testing ItemsetMining tests passed
```

## Use the API

```julia
using ItemsetMining
transactions = read_transactions("data/toy/baskets.txt")
support_threshold(0.5, length(transactions))  # 2 of 4 transactions
patterns = mine(transactions; minsup=0.5, variant=:baseline)
write_itemsets("results/patterns.txt", patterns)
```

An integer `minsup` is an absolute count and a floating-point `minsup` is a fraction, so `minsup=1` means one transaction and `minsup=1.0` means all of them.

Applications that start from labels, such as product names, map them to IDs and back with `encode_transactions` and `decode_itemset`, and save SPMF input with `write_transactions`. [docs/interface.md](docs/interface.md) defines the full input, label, threshold, and output contract that both applications rely on, with a worked example.

`variant=:baseline` runs Eclat as the paper describes it. [docs/eclat.md](docs/eclat.md) states its invariants, why it outputs each frequent itemset once with its exact support, and its cost.

## Use the CLI

```sh
julia --project=. demo.jl --check-input data/toy/baskets.txt
julia --project=. demo.jl --minsup 0.5 --output results/patterns.txt data/toy/baskets.txt
julia --project=. demo.jl --min-count 2 --variant baseline --output results/patterns.txt data/toy/baskets.txt
```

`--check-input` prints the transaction and distinct-item counts. `--minsup` and `--min-count` are mutually exclusive. Run `demo.jl --help` for every option.

## Run on Colab

`notebooks/demo.ipynb` runs on Colab's native Julia kernel, so it calls the package directly without a Python wrapper.

1. Export the committed tree with `git archive --format=zip --output=../Itemset-colab.zip HEAD`.
2. Open the notebook in [Google Colab](https://colab.research.google.com/) and select Runtime, Change runtime type, Julia.
3. Upload the ZIP through the Files sidebar to `/content/Itemset-colab.zip` and run all cells.

If the runtime ships Julia older than 1.12, select runtime version 2026.07 (Julia 1.12.6) or newer. See [Colab runtime versions](https://research.google.com/colaboratory/runtime-version-faq.html). [notebooks/README.md](notebooks/README.md) covers the other source options.

## Layout

- `src/`: the package. `structures.jl` holds the types and thresholds, `utils.jl` the SPMF reader and writer, `algorithm/` the Eclat variants, which [docs/eclat.md](docs/eclat.md) explains.
- `demo.jl`: the CLI.
- `tests/`: the test suite and fixture maps. `test/` holds only the entry-point shim.
- `data/toy/`: hand-derived fixture databases.
- `data/correctness/`: a mid-size database whose complete SPMF map the tests compare with every variant.
- `data/benchmark/` and `data/raw/` hold downloads that stay out of Git.
- `applications/`: the market basket and image-pattern workstreams.
- `experiments/`: the benchmark measurement protocol and result fields.
- `tools/spmf/`: the procedure for independent SPMF reference runs.
- `results/`: raw runs and figures, kept out of Git.
- `notebooks/demo.ipynb`: the Colab demo.
- `docs/report/`: the Vietnamese IEEE-format report, exported as `docs/Report.pdf`.

## Reproducibility

Every stochastic step takes an RNG seeded with `DEFAULT_SEED` from `src/structures.jl`. Each result records the input checksum, item mapping, parameters, environment, and Git revision listed in [experiments/README.md](experiments/README.md). The package uses only Julia standard libraries and never a frequent-itemset-mining library, because the brief requires the team to implement Eclat from the paper.

## References

- M. J. Zaki, "Scalable Algorithms for Association Mining", IEEE TKDE 12(3), 372-390, 2000. [PDF hosted by SPMF](https://www.philippe-fournier-viger.com/spmf/zaki2000.pdf).
- [SPMF documentation](https://www.philippe-fournier-viger.com/spmf/documentation.php) and [dataset catalog](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php).
- [Julia release versions and checksums](https://julialang-s3.julialang.org/bin/versions.json).
