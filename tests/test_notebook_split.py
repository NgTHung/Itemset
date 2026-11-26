"""Checks that the demo and the two applications are three notebooks of one purpose each.

The demo shows the Eclat engine. The market basket and image pattern notebooks each run one application.
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOKS = ROOT / "notebooks"
APPLICATION_CELLS = {"itemset-7b", "itemset-7c", "itemset-7c-check", "itemset-semeion", "itemset-semeion-mining",
                     "itemset-image-analysis-text", "itemset-image-analysis"}


def load(name):
    return json.loads((NOTEBOOKS / name).read_text(encoding="utf-8"))["cells"]


def source(cell):
    return "".join(cell["source"])


class NotebookSplitTest(unittest.TestCase):
    def test_the_demo_holds_no_application_cell(self):
        ids = {cell["id"] for cell in load("demo.ipynb")}
        self.assertEqual(ids & APPLICATION_CELLS, set())

    def test_the_demo_does_not_mention_either_application_dataset(self):
        text = "\n".join(source(cell) for cell in load("demo.ipynb")).lower()
        for word in ("semeion", "online retail", "market basket", "visual word"):
            with self.subTest(word=word):
                self.assertNotIn(word, text)

    def test_the_runner_collects_exactly_the_artifacts_the_demo_registers(self):
        registered = set(re.findall(r'notebook_artifacts\["([^"]+)"\]\s*=', "\n".join(
            source(cell) for cell in load("demo.ipynb") if cell["cell_type"] == "code")))
        runner = (ROOT / "scripts" / "run_colab_notebook.py").read_text(encoding="utf-8")
        required = re.search(r"required = \{([^}]*)\}", runner)
        self.assertIsNotNone(required)
        self.assertEqual(set(re.findall(r'"([^"]+)"', required[1])), registered)

    def test_the_entry_notebook_shows_no_application_output(self):
        text = "\n".join(source(cell) for cell in load("colab.ipynb")).lower()
        for word in ("semeion", "visual_words.svg", "market basket"):
            with self.subTest(word=word):
                self.assertNotIn(word, text)

    def test_each_application_has_its_own_notebook_in_the_notebooks_folder(self):
        for name in ("market_basket.ipynb", "image_patterns.ipynb"):
            with self.subTest(notebook=name):
                self.assertTrue((NOTEBOOKS / name).is_file())

    def test_the_application_notebooks_share_one_setup_cell(self):
        setups = {name: source(next(c for c in load(name) if c["id"] == "itemset-setup"))
                  for name in ("market_basket.ipynb", "image_patterns.ipynb")}
        self.assertEqual(len(set(setups.values())), 1, "one bootstrap, so a fix reaches both notebooks")

    def test_the_applications_keep_to_their_own_data(self):
        market = "\n".join(source(cell) for cell in load("market_basket.ipynb")).lower()
        image = "\n".join(source(cell) for cell in load("image_patterns.ipynb")).lower()
        self.assertNotIn("semeion", market)
        self.assertNotIn("online retail", image)
        self.assertNotIn("market_basket", image)


if __name__ == "__main__":
    unittest.main()
