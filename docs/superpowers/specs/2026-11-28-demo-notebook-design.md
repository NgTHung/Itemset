# Demo notebook redesign

## Why

A grader opens the Colab demo from the README to see the miner run. Today `demo_colab.ipynb` has one cell that downloads `scripts/run_colab_notebook.py`, which runs every cell of `demo_local.ipynb` in one hidden Julia process. The viewer sees one long log, no figure renders, and the committed notebook holds no output. The demo looks unverifiable even when it passes.

The demo also carries report experiments (the BBQ runtime cohort, transaction width, stage profile) that skip or degrade on Colab because their inputs live in ignored folders.

## Goals

- Each step is its own cell with its own visible output, so a viewer follows the run top to bottom.
- Show the brief's Chapter 1 items on one small toy file and one real benchmark: SPMF file format, the `demo.jl` command line, both variants, and an exact comparison with SPMF.
- Show one chart inline on Colab.
- Commit the Colab notebook with the outputs of one clean run.

## Non-goals

- The full experimental series. The report and `experiments/` own those.
- The two applications. They keep their own notebooks.

## Anti-goals

- A cell that hides another process's work behind one log.
- Notebook code that duplicates logic already in `experiments/run.jl`, `tools/spmf/compare.jl` or the CLI.

## Approaches

- A, chosen: each cell calls an existing repository command. The notebook holds only commands and display code; tested tools do the work.
- B: a new `scripts/demo_mushroom.jl` with one subcommand per step. Rejected because it repeats `run.jl` and `compare.jl`.
- C: keep the runner and save each cell's output back into the notebook. Rejected because the work still runs in one hidden process.

## Design

Dataset: `data/toy/baskets.txt` for the walkthrough and Mushroom (8,124 transactions) for the real run, chosen by the team.

Colab cells, Python kernel:

1. Intro: what Eclat does, what the notebook shows, expected run time.
2. Setup: the shared setup cell of the application notebooks, unchanged, so `tests/test_notebook_split.py` keeps the copies identical. It installs pinned Julia, checks out an exact commit, and defines `julia()`.
3. Java and SPMF: install Temurin 25 and the SPMF JAR, each checked against its pinned SHA-256 (the pins move from the runner; the JAR pin stays in `tools/spmf/release.toml`).
4. Instantiate the project and run the package tests.
5. Toy walkthrough: print `baskets.txt`, run `demo.jl --minsup 0.5` on it, and print the output beside `baskets.expected.txt` with the comparison result.
6. Prepare Mushroom: `experiments/prepare_benchmarks.jl mushroom`, which downloads it, checks its hash, and prints its statistics.
7. Mine Mushroom: `demo.jl --check-input`, then `demo.jl --minsup 0.3` for both variants with `--output`. Show the itemset count and a pandas table of the longest itemsets.
8. SPMF comparison and sweep: `experiments/run.jl experiments/configs/demo-mushroom.toml`, a new config with both variants, SPMF, and minsup 0.5, 0.4, 0.3, 0.2, 0.1. Show a pandas table from `runs.csv`: minsup, variant, itemset count, exact match, time.
9. Chart: matplotlib, itemset count and runtime against minsup for baseline, optimized and SPMF, inline.
10. Evidence ZIP: revision, versions, hashes of the outputs, as the application notebooks do.

`demo_local.ipynb` runs the same steps on a Julia kernel with `run` on the same commands. It prints the tables but draws no chart, because only standard libraries are approved.

Removed: `scripts/run_colab_notebook.py`, `tests/colab_runner.py` and its CI step, the runtime cohort, width and stage-profile cells, and the CLI section of `notebooks/README.md`. Tests that read the Julia pin from the runner read it from the shared setup cell instead. The dated record `docs/phat-application2-colab-2026-11-13.md` stays as history.

## Left to the builder

- Python checks for the new cell order and pins, in the style of `tests/test_notebook_market_basket.py`.
- How the longest-itemset table reads the output file.
- The README and `notebooks/README.md` wording.
