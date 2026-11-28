# Demo Notebook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-cell Colab demo with step-by-step cells that each show their own output, on the toy baskets and on Mushroom with an SPMF comparison.

**Architecture:** Each notebook cell calls an existing repository command (`demo.jl`, `tools/spmf/compare.jl`, `experiments/prepare_benchmarks.jl`, `experiments/run.jl`). One new run config drives the SPMF comparison and the minsup sweep. The Colab notebook follows `market_basket_colab.ipynb`; the hidden runner `scripts/run_colab_notebook.py` is removed.

**Tech Stack:** Julia 1.13.2 (standard libraries only), Python 3.12 `unittest` for notebook checks, pandas and matplotlib on Colab only.

**Spec:** `docs/superpowers/specs/2026-11-28-demo-notebook-design.md`

## Global Constraints

- Work in the worktree `D:\HCMUS\DataMining\Itemset-demo-colab` on branch `demo-colab-notebook`.
- Julia tests: `julia --startup-file=no --project=. test/runtests.jl`. Python tests: `uv run --no-project --python 3.12 --with matplotlib==3.10.7 python -m unittest discover -s tests -p "test_*.py"`.
- Only Julia standard libraries. The local notebook draws no chart.
- Every cell `id` equals its `metadata.id`. Colab kernel is `python3`; local kernel is `julia`.
- Every Julia call in the Colab notebook goes through the `julia()` helper of the shared setup cell, never `!julia`.
- Mushroom thresholds: sweep `[0.5, 0.4, 0.3, 0.2, 0.1]`; single mining run at `0.3`. Toy run at `0.5` on `data/toy/baskets.txt`.
- Run outputs go under `results/raw/` (ignored by Git): `results/raw/demo-toy/`, `results/raw/demo-mushroom-mine/`, `results/raw/demo-mushroom/`.
- Markdown follows `docs/WRITING_GUIDE.md`: present tense, no em dashes, no bold in prose.
- Conventional Commits, one concern each.
- `tests/test_notebook_split.py` forbids `semeion`, `visual_words.svg` and the phrase `market basket` anywhere in `demo_colab.ipynb`, and application dataset names in `demo_local.ipynb`. Link the application notebooks by file name only.

## Review Focus

- Colab's preinstalled Java is older than 25: the Java cell must install the pinned Temurin 25 and put it first on `PATH`, or SPMF fails. Pinned in Task 2's `test_java_is_pinned_and_checked`.
- Rerunning a cell in the same Colab session: output folders already exist. `run.jl --out` into an existing folder must not silently mix runs; the sweep cell deletes `results/raw/demo-mushroom` before running. Pinned in Task 2's `test_the_sweep_starts_from_a_fresh_folder`.
- SPMF writes two rows per attempt (`process` and `spmf_total`): the table and chart must keep only `timing_scope == "process"`, or SPMF points double. Pinned in Task 2's `test_the_table_keeps_process_rows_only`.
- A local run without Java or the JAR: the local sweep cell prints how to set them up and does not throw. Pinned in Task 3's `test_the_local_sweep_skips_without_java`.
- A sweep threshold where SPMF and `support_threshold` round differently would make the harness reject the run. Pinned in Task 1 by planning the attempts.

---

### Task 1: Mushroom demo run config

**Files:**
- Create: `experiments/configs/demo-mushroom.toml`
- Create: `tests/demo_config.jl`
- Modify: `tests/runtests.jl` (add `include("demo_config.jl")` next to the other harness includes)

**Interfaces:**
- Produces: config `name = "demo-mushroom"`, read by the sweep cells of Tasks 2 and 3 through `experiments/run.jl experiments/configs/demo-mushroom.toml --out results/raw/demo-mushroom`.

- [ ] **Step 1: Write the failing test** in `tests/demo_config.jl`

```julia
@testset "The demo config sweeps Mushroom against SPMF" begin
    root = dirname(@__DIR__)
    config = Experiments.load_run_config(joinpath(root, "experiments", "configs", "demo-mushroom.toml"))
    manifest = Experiments.load_manifest(joinpath(root, "data", "benchmark", "manifest.toml"))
    @test config.name == "demo-mushroom"
    @test config.variants == [:baseline, :optimized, :spmf]
    @test config.mode == :cli
    @test config.repeats == 1
    @test config.verify_outputs
    @test [(s.dataset, s.minsup) for s in config.series] == [("mushroom", [0.5, 0.4, 0.3, 0.2, 0.1])]
    # Planning rejects any threshold where SPMF and support_threshold disagree.
    @test length(Experiments.plan_attempts(config, manifest)) == 15
end
```

Check the field names of `Series` in `experiments/harness.jl` and match them if they differ.

- [ ] **Step 2: Run it and see it fail** with a missing-file error for `demo-mushroom.toml`.

- [ ] **Step 3: Write `experiments/configs/demo-mushroom.toml`** in the style of `correctness.toml`: `name = "demo-mushroom"`, `variants = ["baseline", "optimized", "spmf"]`, `mode = "cli"`, `repeats = 1`, `timeout_seconds = 300`, `keep_outputs = true`, `verify_outputs = true`, `skip_after_timeout = false`, one `[[series]]` with `dataset = "mushroom"` and the five thresholds. One comment line says it backs the demo notebooks.

- [ ] **Step 4: Run the Julia tests.** Expected: all pass.

- [ ] **Step 5: Commit** `feat: add the Mushroom demo run config`.

---

### Task 2: Step-by-step Colab demo

**Files:**
- Rewrite: `notebooks/demo_colab.ipynb`
- Create: `tests/test_notebook_demo_colab.py`
- Modify: `notebooks/market_basket_colab.ipynb`, `notebooks/image_patterns_colab.ipynb` (root path rename only)

**Interfaces:**
- Consumes: Task 1's config; the shared setup cell (`id` `itemset-setup`) of `market_basket_colab.ipynb`, which defines `root`, `revision`, `REPOSITORY`, `JULIA_SHA256` and `julia(*args)`.
- Produces: code cell IDs, in order: `itemset-setup`, `itemset-demo-java`, `itemset-demo-instantiate`, `itemset-demo-tests`, `itemset-demo-toy`, `itemset-demo-prepare`, `itemset-demo-mine`, `itemset-demo-sweep`, `itemset-demo-chart`, `itemset-demo-evidence`.

- [ ] **Step 1: Write the failing tests** in `tests/test_notebook_demo_colab.py`, modelled on `tests/test_notebook_market_basket.py` (same `cells()`, `source()`, `code()` helpers):

  - `test_the_kernel_is_python`: kernelspec name `python3`.
  - `test_cell_ids_are_unique_and_match_their_metadata`.
  - `test_the_steps_run_in_order`: code cell IDs equal the list above.
  - `test_the_setup_cell_is_the_one_the_applications_share`: `itemset-setup` source equals the one in `market_basket_colab.ipynb` and `image_patterns_colab.ipynb`.
  - `test_the_setup_works_in_one_neutral_folder`: `Path("/content/Itemset")` in `itemset-setup` of all three Colab notebooks, and `Itemset-market-basket` in none of their sources.
  - `test_java_is_pinned_and_checked`: `itemset-demo-java` contains `JAVA_URL = "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jre_x64_linux_hotspot_25.0.5_8.tar.gz"`, `JAVA_SHA256 = "6fac98f0c8202efc3135a9e9e42aa61963ec42d1c5cbb40caf231e7b14a24ef6"`, `hashlib`, `tools/spmf/release.toml`, and `os.environ["PATH"]`.
  - `test_every_julia_call_goes_through_the_helper`: each of `itemset-demo-instantiate` through `itemset-demo-sweep` contains `julia(` and not `!julia`.
  - `test_the_cells_name_repository_paths_that_exist`: (`itemset-demo-tests`, `test/runtests.jl`), (`itemset-demo-toy`, `data/toy/baskets.txt`), (`itemset-demo-toy`, `data/toy/baskets.expected.txt`), (`itemset-demo-toy`, `tools/spmf/compare.jl`), (`itemset-demo-prepare`, `experiments/prepare_benchmarks.jl`), (`itemset-demo-mine`, `demo.jl`), (`itemset-demo-sweep`, `experiments/configs/demo-mushroom.toml`), (`itemset-demo-sweep`, `experiments/run.jl`); each named in its cell and present on disk.
  - `test_the_thresholds_match_the_config`: `"0.3"` in `itemset-demo-mine`; `"0.5"` in `itemset-demo-toy`; `--variant` with both `baseline` and `optimized` in `itemset-demo-mine`.
  - `test_the_sweep_starts_from_a_fresh_folder`: `shutil.rmtree` and `results/raw/demo-mushroom` in `itemset-demo-sweep`, and the `rmtree` appears before `julia(`.
  - `test_the_table_keeps_process_rows_only`: `timing_scope` and `"process"` in both `itemset-demo-sweep` and `itemset-demo-chart`.
  - `test_the_chart_draws_inline`: `matplotlib` and `plt.show()` in `itemset-demo-chart`.
  - `test_the_evidence_archive_records_hashes_and_the_revision`: `sha256`, `revision`, `results/raw/demo-mushroom`, `zipfile` in `itemset-demo-evidence`.
  - `test_the_intro_names_the_local_sibling`: first markdown cell names `demo_local.ipynb`.

- [ ] **Step 2: Run them and see them fail** (`python -m unittest tests.test_notebook_demo_colab`): the old notebook has one code cell.

- [ ] **Step 3: Rename the setup folder** from `/content/Itemset-market-basket` to `/content/Itemset` in the setup cell of both application notebooks and in the two fallback `root = globals().get(...)` lines of `image_patterns_colab.ipynb`.

- [ ] **Step 4: Write `notebooks/demo_colab.ipynb`.** Python kernel metadata copied from `market_basket_colab.ipynb`. Cells:

  1. Markdown intro: Eclat in two sentences, the steps below, about ten minutes on a CPU runtime, links to the two application notebooks, and that `demo_local.ipynb` runs the same steps on a Julia kernel.
  2. `itemset-setup`: copied byte for byte from `market_basket_colab.ipynb` after Step 3.
  3. `itemset-demo-java`: download the Temurin archive with the pins above, check SHA-256, extract under `/content/java-25`, prepend its `bin` to `PATH`; read `url` and `sha256` from `tools/spmf/release.toml` with `tomllib`, download to `tools/spmf/spmf.jar`, check SHA-256; print `java -version` and the SPMF version.
  4. `itemset-demo-instantiate`: `julia("-e", "using Pkg; Pkg.instantiate()")`.
  5. `itemset-demo-tests`: `julia("test/runtests.jl")`.
  6. Markdown: the SPMF input format and what the next cell shows.
  7. `itemset-demo-toy`: print `data/toy/baskets.txt`; `julia("demo.jl", "--minsup", "0.5", "--output", "results/raw/demo-toy/baskets.txt", "data/toy/baskets.txt")` after creating the folder; print the output and `baskets.expected.txt` side by side; `julia("tools/spmf/compare.jl", "data/toy/baskets.expected.txt", "results/raw/demo-toy/baskets.txt")`.
  8. `itemset-demo-prepare`: `julia("experiments/prepare_benchmarks.jl", "mushroom")`.
  9. `itemset-demo-mine`: `julia("demo.jl", "--check-input", "data/benchmark/mushroom.txt")`; then for each variant `julia("demo.jl", "--minsup", "0.3", "--variant", v, "--output", f"results/raw/demo-mushroom-mine/{v}.txt", "data/benchmark/mushroom.txt")`; print each itemset count and `display` a pandas table of the ten longest itemsets of the optimized output (columns `items`, `length`, `support`, parsed from `items #SUP: n`).
  10. Markdown: what the sweep measures (cold process time from spawn to exit, full-map comparison with SPMF Eclat after timing).
  11. `itemset-demo-sweep`: `shutil.rmtree(root / "results/raw/demo-mushroom", ignore_errors=True)`; `julia("experiments/run.jl", "experiments/configs/demo-mushroom.toml", "--out", "results/raw/demo-mushroom", "--java", shutil.which("java"))`; read `runs.csv` with pandas, keep `timing_scope == "process"`, display `minsup_relative`, `variant`, `output_count`, `correctness_status`, `match_rate`, `elapsed_seconds`.
  12. `itemset-demo-chart`: matplotlib, two panels side by side: itemset count against minsup (log y) and process time against minsup, one line per variant, x axis decreasing, axis labels with units; `plt.show()`.
  13. `itemset-demo-evidence`: ZIP `/content/itemset-demo-evidence.zip` with `results/raw/demo-mushroom/{runs.csv,config.toml,environment.toml}`, every `attempts/*/comparison.toml`, `results/raw/demo-toy/baskets.txt`, and `result.json` holding repository, revision, Julia and Java versions, and the SHA-256 of each file; print its path.

- [ ] **Step 5: Run the Python tests.** Expected: the new file passes, and `test_notebook_market_basket.py`, `test_notebook_image_patterns.py`, `test_notebook_split.py` still pass.

- [ ] **Step 6: Commit** in two commits: `refactor: share one neutral Colab setup folder` (Step 3) and `feat: show each demo step in its own Colab cell` (the rest).

---

### Task 3: Local demo and runner removal

**Files:**
- Rewrite: `notebooks/demo_local.ipynb`
- Create: `tests/test_notebook_demo_local.py`
- Delete: `tests/test_notebook_thien.py`, `tests/colab_runner.py`, `scripts/run_colab_notebook.py`
- Modify: `tests/test_notebook_split.py` (drop `test_the_runner_collects_exactly_the_artifacts_the_demo_registers`), `tests/test_notebook_market_basket.py` (drop `test_the_julia_pin_equals_the_one_of_the_colab_runner`), `.github/workflows/ci.yml` (drop the "Test Colab runner" step), `notebooks/README.md`, `README.md:67`, `README.md:85`

**Interfaces:**
- Consumes: Task 1's config; Task 2's cell IDs, so the local notebook uses the same step IDs where a step exists in both.
- Produces: local cell IDs: `itemset-1` (markdown), `itemset-2`, `itemset-3` (shared setup, unchanged), `itemset-demo-tests`, `itemset-demo-toy`, `itemset-demo-prepare`, `itemset-demo-mine`, `itemset-demo-sweep`.

- [ ] **Step 1: Write the failing tests** in `tests/test_notebook_demo_local.py`:

  - `test_the_steps_run_in_order`: code cell IDs equal `itemset-2`, `itemset-3`, then the five `itemset-demo-*` IDs above.
  - `test_the_steps_match_the_colab_steps`: each local `itemset-demo-*` ID also exists in `demo_colab.ipynb`.
  - `test_the_cells_name_repository_paths_that_exist`: the same pairs as Task 2 for the shared IDs.
  - `test_the_local_sweep_skips_without_java`: `itemset-demo-sweep` contains `ITEMSET_JAVA`, `spmf.jar`, `Sys.which` and a `println` branch that names `tools/spmf/README.md`.
  - `test_no_report_experiment_remains`: no cell names `runtime_curves.jl`, `width_experiment.jl`, `stage_profile.jl` or `bbq-all-variants`.

  The existing `tests/test_notebook_local.py` already forbids `Colab`, `/content` and `git clone` in local code cells, so the new cells must avoid those words.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Write `notebooks/demo_local.ipynb`.** Keep metadata, `itemset-2` and `itemset-3` unchanged. Julia commands run through one helper defined in `itemset-demo-tests`: `repo(args...) = run(\`$(Base.julia_cmd()) --startup-file=no --project=$ROOT $args\`)`. Cells mirror Task 2 cells 5 to 11:

  - `itemset-demo-tests`: the current setup-check and test-suite cell, then the `repo` helper.
  - `itemset-demo-toy`, `itemset-demo-prepare`, `itemset-demo-mine`: the same commands as Colab; the longest-itemset table prints as text with `read_itemset_records` or a split on ` #SUP: `.
  - `itemset-demo-sweep`: if `ITEMSET_JAVA` (default `java`) resolves and `tools/spmf/spmf.jar` exists, remove `results/raw/demo-mushroom`, run the config with `--java`, and print the process rows of `runs.csv` with `Experiments.read_csv_rows`; otherwise print that the step needs Java 25 and the JAR from `tools/spmf/README.md`.
  - Intro markdown names `demo_colab.ipynb` and the application notebooks by their real names.

- [ ] **Step 4: Delete the runner, its test, `tests/test_notebook_thien.py`, and the two runner-bound tests and the CI step named above.**

- [ ] **Step 5: Update the docs.** `notebooks/README.md`: the "Eclat demo" section describes the new steps and the evidence ZIP; delete the "Run through the Colab CLI" section. `README.md:67`: the demo runs the toy baskets and Mushroom with an SPMF comparison. `README.md:85`: drop the sentence about `scripts/run_colab_notebook.py`. Check with `grep -rn "run_colab_notebook\|colab_runner"` that only the dated record `docs/phat-application2-colab-2026-11-13.md` still names them.

- [ ] **Step 6: Run the Python tests and the Julia tests.** Expected: all pass.

- [ ] **Step 7: Run `demo_local.ipynb` top to bottom on a local Julia kernel** with Java 25 and the JAR present. Expected: the toy comparison reports equal maps, and every sweep row has `correctness_status = exact`.

- [ ] **Step 8: Commit** in three commits: `feat: run the demo steps on a local Julia kernel`, `chore: remove the hidden Colab runner`, `docs: describe the step-by-step demo`.

---

### Task 4: Clean Colab run with saved outputs

A person does this task; it needs a Google account.

- [ ] **Step 1:** Push the branch, open a PR, and merge it once reviewed.
- [ ] **Step 2:** Open `https://colab.research.google.com/github/NgTHung/Itemset/blob/main/notebooks/demo_colab.ipynb` on a CPU runtime, leave `ITEMSET_REVISION` empty, and run all cells. Expected: every cell finishes, the toy comparison and all fifteen sweep rows report exact maps, and the chart renders.
- [ ] **Step 3:** Download the notebook with its outputs (File, Download, `.ipynb`) and the evidence ZIP.
- [ ] **Step 4:** On a new branch from `main`, replace `notebooks/demo_colab.ipynb` with the downloaded file, run the Python tests, and commit `docs: save the outputs of a clean Colab demo run` with the revision from the setup cell output in the body.
