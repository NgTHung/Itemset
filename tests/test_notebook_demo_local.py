"""Checks notebooks/demo_local.ipynb, the demo on a local Julia kernel, without running Julia.

The local demo runs the same steps as demo_colab.ipynb under the same cell IDs, so a change to one step shows in
both notebooks. Only the setup differs: the local notebook finds its checkout instead of cloning one.
"""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOKS = ROOT / "notebooks"
STEPS = ["itemset-2", "itemset-3", "itemset-demo-tests", "itemset-demo-toy", "itemset-demo-prepare",
         "itemset-demo-mine", "itemset-demo-sweep"]


def cells(name="demo_local.ipynb"):
    return json.loads((NOTEBOOKS / name).read_text(encoding="utf-8"))["cells"]


def code(name="demo_local.ipynb"):
    return {cell["id"]: "".join(cell["source"]) for cell in cells(name) if cell["cell_type"] == "code"}


class DemoLocalNotebookTest(unittest.TestCase):
    def test_the_steps_run_in_order(self):
        self.assertEqual(list(code()), STEPS)

    def test_the_steps_match_the_colab_steps(self):
        colab = code("demo_colab.ipynb")
        for cell_id in STEPS[2:]:
            with self.subTest(cell=cell_id):
                self.assertIn(cell_id, colab)

    def test_the_cells_name_repository_paths_that_exist(self):
        by_id = code()
        for cell_id, relative in (("itemset-demo-tests", "test/runtests.jl"),
                                  ("itemset-demo-toy", "data/toy/baskets.txt"),
                                  ("itemset-demo-toy", "data/toy/baskets.expected.txt"),
                                  ("itemset-demo-toy", "tools/spmf/compare.jl"),
                                  ("itemset-demo-prepare", "experiments/prepare_benchmarks.jl"),
                                  ("itemset-demo-mine", "demo.jl"),
                                  ("itemset-demo-sweep", "experiments/configs/demo-mushroom.toml"),
                                  ("itemset-demo-sweep", "experiments/run.jl")):
            with self.subTest(cell=cell_id, path=relative):
                self.assertIn(relative, by_id[cell_id])
                self.assertTrue((ROOT / relative).is_file())

    def test_the_local_sweep_skips_without_java(self):
        text = code()["itemset-demo-sweep"]
        for expected in ("ITEMSET_JAVA", "spmf.jar", "Sys.which", "tools/spmf/README.md"):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)

    def test_the_helper_prints_the_command_and_its_output_in_the_cell(self):
        # A notebook kernel shows only what Julia itself prints; a child process writes past it.
        helper = code()["itemset-demo-tests"]
        for expected in ("IOBuffer()", "pipeline(", "stdout=output", "stderr=output", "finally", "take!(output)",
                         "shell_escape("):
            with self.subTest(expected=expected):
                self.assertIn(expected, helper)

    def test_a_failed_or_inexact_sweep_row_stops_the_notebook(self):
        # run.jl records a failed attempt as a row and still exits 0, so the cell itself must throw.
        text = code()["itemset-demo-sweep"]
        for expected in ('row["status"] != "ok"', 'row["correctness_status"] != "exact"', "error(", '"status"'):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)

    def test_variants_that_disagree_stop_the_notebook(self):
        text = code()["itemset-demo-mine"]
        self.assertIn("|| error(", text)

    def test_no_report_experiment_remains(self):
        text = "\n".join("".join(cell["source"]) for cell in cells())
        for name in ("runtime_curves.jl", "width_experiment.jl", "stage_profile.jl", "bbq-all-variants"):
            with self.subTest(name=name):
                self.assertNotIn(name, text)


if __name__ == "__main__":
    unittest.main()
