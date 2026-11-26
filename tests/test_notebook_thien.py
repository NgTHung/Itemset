"""Checks the benchmark, runtime, width, and stage profile cells of notebooks/demo_local.ipynb without running Julia.

The cells themselves run in a Julia kernel, and the runner in scripts/run_colab_notebook.py executes them
by ID. These checks cover what that runner relies on and what the cells name in the repository.
"""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOK = ROOT / "notebooks" / "demo_local.ipynb"
THIEN = ["itemset-7a", "itemset-7-figure", "itemset-7d", "itemset-7e", "itemset-7f"]


def load():
    return json.loads(NOTEBOOK.read_text(encoding="utf-8"))["cells"]


def source(cell):
    return "".join(cell["source"])


class NotebookTest(unittest.TestCase):
    def test_cell_ids_are_unique_and_match_their_metadata(self):
        cells = load()
        ids = [cell["id"] for cell in cells]
        self.assertEqual(len(ids), len(set(ids)))
        for cell in cells:
            if "id" in cell["metadata"]:
                self.assertEqual(cell["id"], cell["metadata"]["id"])
        for cell in cells:
            if cell["id"] in THIEN:
                self.assertEqual(cell["id"], cell["metadata"]["id"])

    def test_thien_cells_run_in_order(self):
        ids = [cell["id"] for cell in load()]
        positions = [ids.index(cell_id) for cell_id in THIEN]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(positions[-1] - positions[0], len(THIEN) - 1, "no other cell sits between them")
        by_id = {cell["id"]: cell for cell in load()}
        for cell_id in THIEN:
            self.assertEqual(by_id[cell_id]["cell_type"], "code")

    def test_figure_helper_is_defined_before_its_first_use(self):
        cells = {cell["id"]: source(cell) for cell in load()}
        order = [cell["id"] for cell in load()]
        defined = [i for i, cell_id in enumerate(order) if "function show_figure" in cells[cell_id]]
        used = [i for i, cell_id in enumerate(order) if "show_figure(" in cells[cell_id]
                and "function show_figure" not in cells[cell_id]]
        self.assertEqual(len(defined), 1)
        self.assertTrue(used)
        self.assertLess(defined[0], min(used))

    def test_paths_named_by_the_cells_exist(self):
        for relative in ("scripts/runtime_curves.jl", "scripts/width_experiment.jl", "scripts/stage_profile.jl",
                         "experiments/configs/stage-profile.toml", "docs/report/figures/runtime-curves.png",
                         "docs/report/figures/width-curves.png"):
            with self.subTest(path=relative):
                self.assertTrue((ROOT / relative).is_file())
        text = "\n".join(source(cell) for cell in load() if cell["id"] in THIEN)
        for name in ("runtime_curves.jl", "width_experiment.jl", "stage_profile.jl", "stage-profile.toml",
                     "runtime-curves.png", "width-curves.png"):
            with self.subTest(named=name):
                self.assertIn(name, text)

    def test_the_runtime_cell_asks_for_the_ratios_of_the_record(self):
        text = {cell["id"]: source(cell) for cell in load()}["itemset-7d"]
        record = (ROOT / "docs" / "runtime-curves-2026-11-17.md").read_text(encoding="utf-8")
        for ratio in ("Baseline/Optimized", "SPMF/Optimized", "PrePost/Optimized", "Baseline/PrePost"):
            with self.subTest(ratio=ratio):
                self.assertIn(f'"--ratio", "{ratio}"', text)
                self.assertIn(f"--ratio {ratio}", record)
        for label in ("Baseline=", "Optimized=", "SPMF=", "PrePost="):
            self.assertIn(f'"{label}$run_dir', text)

    def test_an_empty_runtime_variable_counts_as_unset(self):
        text = {cell["id"]: source(cell) for cell in load()}["itemset-7d"]
        self.assertIn('configured = get(ENV, "ITEMSET_RUNTIME_RUN", "")', text)
        self.assertIn("isempty(configured)", text)

    def test_the_stage_profile_writes_where_the_documented_command_does(self):
        text = {cell["id"]: source(cell) for cell in load()}["itemset-7f"]
        self.assertIn('"results", "raw", "stage-profile"', text)
        self.assertNotIn("results\", \"figures\", \"stage-profile", text)
        self.assertIn("results/raw/stage-profile", (ROOT / "experiments" / "README.md").read_text(encoding="utf-8"))

    def test_the_runtime_cell_defaults_to_the_committed_cohort(self):
        by_id = {cell["id"]: source(cell) for cell in load()}
        self.assertIn("bbq-all-variants-cli-5repeat-20261117T041922Z", by_id["itemset-7d"])
        self.assertIn("ITEMSET_RUNTIME_RUN", by_id["itemset-7d"])
        self.assertIn("DEFAULT_SEED", by_id["itemset-7"])


if __name__ == "__main__":
    unittest.main()
