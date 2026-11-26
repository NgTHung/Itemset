"""Checks the notebooks that run on a Julia kernel on the contributor's own machine.

Each local notebook has a Colab sibling that names its place in the file name. The two differ in setup only:
the local notebook finds the checkout it sits in, and the Colab notebook clones one and installs Julia.
"""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTEBOOKS = ROOT / "notebooks"
LOCAL = ("demo_local.ipynb", "market_basket_local.ipynb", "image_patterns_local.ipynb")
SETUP = ("itemset-2", "itemset-3")


def load(name):
    return json.loads((NOTEBOOKS / name).read_text(encoding="utf-8"))


def by_id(name):
    return {cell["id"]: "".join(cell["source"]) for cell in load(name)["cells"]}


class LocalNotebookTest(unittest.TestCase):
    def test_every_notebook_names_the_place_it_runs(self):
        names = sorted(path.name for path in NOTEBOOKS.glob("*.ipynb"))
        self.assertEqual(names, sorted(LOCAL + ("demo_colab.ipynb", "market_basket_colab.ipynb",
                                                "image_patterns_colab.ipynb")))

    def test_the_local_notebooks_run_on_a_julia_kernel(self):
        for name in LOCAL:
            with self.subTest(notebook=name):
                self.assertEqual(load(name)["metadata"]["kernelspec"]["name"], "julia")

    def test_cell_ids_are_unique_and_match_their_metadata(self):
        for name in LOCAL:
            with self.subTest(notebook=name):
                cells = load(name)["cells"]
                ids = [cell["id"] for cell in cells]
                self.assertEqual(len(ids), len(set(ids)))
                for cell in cells:
                    if "id" in cell["metadata"]:
                        self.assertEqual(cell["id"], cell["metadata"]["id"])

    def test_the_local_notebooks_share_their_setup_cells(self):
        for cell_id in SETUP:
            with self.subTest(cell=cell_id):
                sources = {name: by_id(name)[cell_id] for name in LOCAL}
                self.assertEqual(len(set(sources.values())), 1, "one setup, so a fix reaches all three notebooks")

    def test_the_setup_finds_the_checkout_from_the_repository_or_the_notebooks_folder(self):
        setup = by_id("demo_local.ipynb")["itemset-2"]
        for expected in ("ITEMSET_ROOT", "dirname(pwd())", "Project.toml"):
            with self.subTest(expected=expected):
                self.assertIn(expected, setup)

    def test_no_local_code_cell_clones_unpacks_or_assumes_colab(self):
        for name in LOCAL:
            for cell in load(name)["cells"]:
                if cell["cell_type"] != "code":
                    continue
                text = "".join(cell["source"])
                for forbidden in ("git clone", "/content", "REPO_URL", "unzip", "Colab"):
                    with self.subTest(notebook=name, cell=cell["id"], forbidden=forbidden):
                        self.assertNotIn(forbidden, text)

    def test_the_application_notebooks_run_their_application_and_nothing_of_the_other(self):
        market = "\n".join(by_id("market_basket_local.ipynb").values())
        image = "\n".join(by_id("image_patterns_local.ipynb").values())
        for expected in ("prepare.jl", "analyze.jl"):
            self.assertIn(expected, market)
        self.assertIn("itemset-7c-check", by_id("market_basket_local.ipynb"))
        self.assertIn("image_pilot.jl", image)
        self.assertNotIn("Semeion", market)
        self.assertNotIn("Online Retail", image)

    def test_the_scripts_the_local_notebooks_include_exist(self):
        for relative in ("applications/market_basket/prepare.jl", "applications/market_basket/analyze.jl",
                         "applications/market_basket/MarketBasket.jl", "scripts/image_pilot.jl"):
            with self.subTest(path=relative):
                self.assertTrue((ROOT / relative).is_file())

    def test_a_local_notebook_points_to_its_colab_sibling_and_back(self):
        for local, colab in (("demo_local.ipynb", "demo_colab.ipynb"),
                             ("market_basket_local.ipynb", "market_basket_colab.ipynb"),
                             ("image_patterns_local.ipynb", "image_patterns_colab.ipynb")):
            with self.subTest(local=local):
                self.assertIn(colab, by_id(local)["itemset-1"])
                self.assertIn(local, by_id(colab)[next(cell["id"] for cell in load(colab)["cells"]
                                                       if cell["cell_type"] == "markdown")])


if __name__ == "__main__":
    unittest.main()
