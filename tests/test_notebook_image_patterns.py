"""Checks notebooks/image_patterns.ipynb without a Colab runtime.

The notebook runs on Colab's Python kernel and calls Julia through the shell, so these checks cover the step
order, the pins shared with the market basket notebook, and the repository paths and outputs the cells name.
"""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOK = ROOT / "notebooks" / "image_patterns.ipynb"
STEPS = ["itemset-setup", "itemset-ip-instantiate", "itemset-ip-tests", "itemset-ip-mine", "itemset-ip-show",
         "itemset-ip-evidence"]


def cells():
    return json.loads(NOTEBOOK.read_text(encoding="utf-8"))["cells"]


def code():
    return {cell["id"]: "".join(cell["source"]) for cell in cells() if cell["cell_type"] == "code"}


class ImagePatternsNotebookTest(unittest.TestCase):
    def test_the_kernel_is_python_because_colab_has_no_julia_kernel(self):
        metadata = json.loads(NOTEBOOK.read_text(encoding="utf-8"))["metadata"]
        self.assertEqual(metadata["kernelspec"]["name"], "python3")

    def test_cell_ids_are_unique_and_match_their_metadata(self):
        ids = [cell["id"] for cell in cells()]
        self.assertEqual(len(ids), len(set(ids)))
        for cell in cells():
            self.assertEqual(cell["id"], cell["metadata"]["id"])

    def test_the_steps_run_in_order(self):
        self.assertEqual(list(code()), STEPS)

    def test_the_mining_cell_runs_the_script_and_the_tests_run_the_suite(self):
        by_id = code()
        for cell_id, relative in (("itemset-ip-mine", "scripts/image_features.jl"),
                                  ("itemset-ip-tests", "test/runtests.jl")):
            with self.subTest(cell=cell_id):
                self.assertIn(relative, by_id[cell_id])
                self.assertTrue((ROOT / relative).is_file())
        self.assertIn("julia(", by_id["itemset-ip-mine"])
        self.assertNotIn("!julia", by_id["itemset-ip-mine"], "a shell escape would not stop the notebook on failure")

    def test_the_shown_files_are_written_by_the_application(self):
        shown = code()["itemset-ip-show"]
        written = "\n".join((ROOT / "applications" / "image_patterns" / name).read_text(encoding="utf-8")
                            for name in ("encoding_artifacts.jl", "mining.jl"))
        for name in ("manifest.toml", "thresholds.tsv", "selected_patterns.tsv", "digits.svg", "visual_words.svg"):
            with self.subTest(name=name):
                self.assertIn(name, shown)
                self.assertIn(name, written)
        for threshold in ("0.2", "0.05"):
            with self.subTest(supporting=threshold):
                self.assertIn(f"supporting-{threshold}.svg", shown)
        self.assertIn('"supporting-$(run.minsup).svg"', written)
        self.assertIn("image_features.tsv", shown)
        self.assertIn("image_features.tsv", (ROOT / "scripts" / "image_features.jl").read_text(encoding="utf-8"))

    def test_the_thresholds_shown_are_among_the_default_mining_levels(self):
        mining = (ROOT / "applications" / "image_patterns" / "mining.jl").read_text(encoding="utf-8")
        self.assertIn("const MINING_LEVELS = (0.2, 0.1, 0.05)", mining)

    def test_the_evidence_archive_records_hashes_the_revision_and_the_data(self):
        text = code()["itemset-ip-evidence"]
        for expected in ("sha256", "revision", "results/raw/semeion-patterns", "semeion_sha256", "zipfile"):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)

    def test_the_output_folder_is_outside_git(self):
        self.assertIn("results/raw/", (ROOT / ".gitignore").read_text(encoding="utf-8"))
        self.assertIn("data/raw/", (ROOT / ".gitignore").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
