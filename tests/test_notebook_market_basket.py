"""Checks notebooks/market_basket_colab.ipynb without a Colab runtime.

The notebook runs on Colab's Python kernel and calls Julia through the shell, so these checks cover what a
hosted run needs: the pins, the order of the steps, and the repository paths the cells name.
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOK = ROOT / "notebooks" / "market_basket_colab.ipynb"
STEPS = ["itemset-setup", "itemset-mb-instantiate", "itemset-mb-tests", "itemset-mb-prepare",
         "itemset-mb-rules", "itemset-mb-show", "itemset-mb-evidence"]


def cells():
    return json.loads(NOTEBOOK.read_text(encoding="utf-8"))["cells"]


def source(cell):
    return "".join(cell["source"])


def code():
    return {cell["id"]: source(cell) for cell in cells() if cell["cell_type"] == "code"}


class MarketBasketNotebookTest(unittest.TestCase):
    def test_the_kernel_is_python_because_colab_has_no_julia_kernel(self):
        metadata = json.loads(NOTEBOOK.read_text(encoding="utf-8"))["metadata"]
        self.assertEqual(metadata["kernelspec"]["name"], "python3")

    def test_cell_ids_are_unique_and_match_their_metadata(self):
        ids = [cell["id"] for cell in cells()]
        self.assertEqual(len(ids), len(set(ids)))
        for cell in cells():
            self.assertEqual(cell["id"], cell["metadata"]["id"])

    def test_the_steps_run_in_order_without_other_code_between_them(self):
        ids = [cell["id"] for cell in cells() if cell["cell_type"] == "code"]
        self.assertEqual(ids, STEPS)

    def test_julia_is_the_pinned_version_and_checked_against_its_hash(self):
        text = code()["itemset-setup"]
        pinned = (ROOT / ".julia-version").read_text(encoding="utf-8").strip()
        self.assertIn(f"julia-{pinned}-linux-x86_64.tar.gz", text)
        self.assertIn(f"/{'.'.join(pinned.split('.')[:2])}/julia-{pinned}", text)
        digest = re.search(r'JULIA_SHA256 = "([0-9a-f]{64})"', text)
        self.assertIsNotNone(digest, "the Julia archive needs a pinned SHA-256")
        self.assertIn("hashlib", text)
        self.assertIn("JULIA_SHA256", text.split("JULIA_SHA256", 1)[1])

    def test_the_revision_is_resolved_to_a_full_commit_before_anything_runs(self):
        text = code()["itemset-setup"]
        self.assertIn("ITEMSET_REVISION", text)
        self.assertIn("[0-9a-f]{40}", text)
        self.assertIn("git", text)
        self.assertIn("checkout", text)

    def test_the_cells_run_the_repository_scripts_that_exist(self):
        by_id = code()
        for cell_id, relative in (("itemset-mb-prepare", "applications/market_basket/prepare.jl"),
                                  ("itemset-mb-rules", "applications/market_basket/analyze.jl"),
                                  ("itemset-mb-tests", "test/runtests.jl")):
            with self.subTest(cell=cell_id):
                self.assertIn(relative, by_id[cell_id])
                self.assertTrue((ROOT / relative).is_file())

    def test_every_julia_call_goes_through_one_helper_that_fails_the_cell(self):
        by_id = code()
        helper = by_id["itemset-setup"]
        for expected in ('"--startup-file=no"', '"--project=."', "raise RuntimeError"):
            with self.subTest(expected=expected):
                self.assertIn(expected, helper)
        for cell_id in STEPS[1:5]:
            with self.subTest(cell=cell_id):
                self.assertIn("julia(", by_id[cell_id])
                self.assertNotIn("!julia", by_id[cell_id], "a shell escape would not stop the notebook on failure")

    def test_the_tables_shown_are_the_ones_analyze_writes(self):
        shown = code()["itemset-mb-show"]
        analyze = (ROOT / "applications" / "market_basket" / "analyze.jl").read_text(encoding="utf-8")
        for name in ("top_rules.tsv", "top_groups.tsv", "summary.toml"):
            with self.subTest(table=name):
                self.assertIn(name, shown)
                self.assertIn(name, analyze)

    def test_the_evidence_archive_records_hashes_and_the_revision(self):
        text = code()["itemset-mb-evidence"]
        for expected in ("sha256", "revision", "results/raw/market_basket", "zipfile"):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)

    def test_the_hand_checked_case_is_a_julia_test_and_the_notebook_runs_the_suite(self):
        rules_test = (ROOT / "tests" / "market_basket_rules.jl").read_text(encoding="utf-8")
        self.assertIn('@testset "A seven-basket case worked out by hand"', rules_test)
        for expected in ("21 // 16", "3 // 4", "(9, 3)"):
            with self.subTest(in_rules_test=expected):
                self.assertIn(expected, rules_test)
        self.assertIn('include("market_basket_rules.jl")', (ROOT / "test" / "runtests.jl").read_text(encoding="utf-8")
                      + (ROOT / "tests" / "runtests.jl").read_text(encoding="utf-8"))
        self.assertIn("test/runtests.jl", code()["itemset-mb-tests"])

    def test_the_data_stays_out_of_the_notebook_and_out_of_git(self):
        text = NOTEBOOK.read_text(encoding="utf-8")
        self.assertNotIn("online_retail_II.csv", text)
        ignored = (ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("data/raw/", ignored)
        self.assertIn("results/raw/", ignored)


if __name__ == "__main__":
    unittest.main()
