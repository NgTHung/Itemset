"""Checks notebooks/demo_colab.ipynb without a Colab runtime.

The demo runs on Colab's Python kernel. Each command step is a `%%shell` cell that holds the exact commands a user
would type from the repository root, and Python cells only check and display what those commands wrote. These checks cover the pins, the order of the steps, and the repository paths the cells name.
"""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOKS = ROOT / "notebooks"
NOTEBOOK = NOTEBOOKS / "demo_colab.ipynb"
STEPS = ["itemset-setup", "itemset-demo-java", "itemset-demo-instantiate", "itemset-demo-tests", "itemset-demo-toy",
         "itemset-demo-prepare", "itemset-demo-mine", "itemset-demo-longest", "itemset-demo-sweep",
         "itemset-demo-sweep-table", "itemset-demo-chart", "itemset-demo-evidence"]
COMMANDS = ["itemset-demo-instantiate", "itemset-demo-tests", "itemset-demo-toy", "itemset-demo-prepare",
            "itemset-demo-mine", "itemset-demo-sweep"]
COLAB = ("demo_colab.ipynb", "market_basket_colab.ipynb", "image_patterns_colab.ipynb")


def cells(name="demo_colab.ipynb"):
    return json.loads((NOTEBOOKS / name).read_text(encoding="utf-8"))["cells"]


def source(cell):
    return "".join(cell["source"])


def code(name="demo_colab.ipynb"):
    return {cell["id"]: source(cell) for cell in cells(name) if cell["cell_type"] == "code"}


class DemoColabNotebookTest(unittest.TestCase):
    def test_the_kernel_is_python(self):
        metadata = json.loads(NOTEBOOK.read_text(encoding="utf-8"))["metadata"]
        self.assertEqual(metadata["kernelspec"]["name"], "python3")

    def test_cell_ids_are_unique_and_match_their_metadata(self):
        ids = [cell["id"] for cell in cells()]
        self.assertEqual(len(ids), len(set(ids)))
        for cell in cells():
            self.assertEqual(cell["id"], cell["metadata"]["id"])

    def test_the_steps_run_in_order(self):
        self.assertEqual(list(code()), STEPS)

    def test_the_setup_cell_is_the_one_the_applications_share(self):
        setups = {name: code(name)["itemset-setup"] for name in COLAB}
        self.assertEqual(len(set(setups.values())), 1, "one bootstrap, so a fix reaches every notebook")

    def test_the_setup_works_in_one_neutral_folder(self):
        for name in COLAB:
            with self.subTest(notebook=name):
                self.assertIn('Path("/content/Itemset")', code(name)["itemset-setup"])
                self.assertNotIn("Itemset-market-basket", (NOTEBOOKS / name).read_text(encoding="utf-8"))

    def test_java_is_pinned_and_checked(self):
        text = code()["itemset-demo-java"]
        for expected in (
                'JAVA_URL = "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/'
                'OpenJDK25U-jre_x64_linux_hotspot_25.0.5_8.tar.gz"',
                'JAVA_SHA256 = "6fac98f0c8202efc3135a9e9e42aa61963ec42d1c5cbb40caf231e7b14a24ef6"',
                "hashlib", "tools/spmf/release.toml", 'os.environ["PATH"]'):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)

    def test_command_cells_are_shell_cells_that_stop_at_the_first_failure(self):
        # Colab's %%shell raises on a nonzero exit, and set -e makes any failing line, not only the last, count.
        by_id = code()
        for cell_id in COMMANDS:
            with self.subTest(cell=cell_id):
                self.assertTrue(by_id[cell_id].startswith("%%shell\nset -euo pipefail\n"))
                self.assertIn("julia --startup-file=no --project=. ", by_id[cell_id])
                self.assertNotIn("--ignore-errors", by_id[cell_id])

    def test_no_cell_calls_julia_through_python(self):
        for cell_id, text in code().items():
            if cell_id != "itemset-setup":
                with self.subTest(cell=cell_id):
                    self.assertNotIn("julia(", text)
                    self.assertNotIn("!julia", text, "a shell escape would not stop the notebook on failure")

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

    def test_the_thresholds_match_the_config(self):
        by_id = code()
        self.assertIn("--minsup 0.5", by_id["itemset-demo-toy"])
        self.assertIn("--minsup 0.3", by_id["itemset-demo-mine"])
        for expected in ("--variant", "baseline", "optimized"):
            with self.subTest(expected=expected):
                self.assertIn(expected, by_id["itemset-demo-mine"])

    def test_the_sweep_starts_from_a_fresh_folder(self):
        text = code()["itemset-demo-sweep"]
        self.assertIn("rm -rf results/raw/demo-mushroom\n", text)
        self.assertLess(text.index("rm -rf"), text.index("julia "))
        self.assertIn('--java "$(command -v java)"', text)

    def test_the_table_keeps_process_rows_only(self):
        for cell_id in ("itemset-demo-sweep-table", "itemset-demo-chart"):
            with self.subTest(cell=cell_id):
                self.assertIn("timing_scope", code()[cell_id])
                self.assertIn('"process"', code()[cell_id])

    def test_a_failed_or_inexact_sweep_row_stops_the_notebook(self):
        # run.jl records a failed attempt as a row and still exits 0, so the cell itself must raise.
        text = code()["itemset-demo-sweep-table"]
        for expected in ('runs["status"] != "ok"', 'runs["correctness_status"] != "exact"', "raise RuntimeError",
                         '"status"', '"error"'):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)
        self.assertLess(text.index("raise RuntimeError"), text.index("display("))

    def test_variants_that_disagree_stop_the_notebook(self):
        text = code()["itemset-demo-longest"]
        self.assertIn("if not same:", text)
        self.assertIn("raise RuntimeError", text)

    def test_the_chart_draws_inline(self):
        text = code()["itemset-demo-chart"]
        self.assertIn("matplotlib", text)
        self.assertIn("plt.show()", text)

    def test_the_evidence_archive_records_hashes_and_the_revision(self):
        text = code()["itemset-demo-evidence"]
        for expected in ("sha256", "revision", "results/raw/demo-mushroom", "zipfile"):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)

    def test_the_intro_names_the_local_sibling(self):
        intro = next(cell for cell in cells() if cell["cell_type"] == "markdown")
        self.assertIn("demo_local.ipynb", source(intro))


if __name__ == "__main__":
    unittest.main()
