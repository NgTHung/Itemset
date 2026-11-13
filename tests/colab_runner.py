import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("colab_runner", Path(__file__).parents[1] / "scripts/run_colab_notebook.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def test_explicit_arguments_ignore_jupyter_kernel_flags(self):
        from unittest.mock import patch
        with patch("sys.argv", ["ipykernel", "-f", "kernel.json"]), patch.object(runner, "execute", return_value=0) as execute:
            self.assertEqual(runner.main(["--revision", "a" * 40]), 0)
            self.assertEqual(execute.call_args.args[0].revision, "a" * 40)

    def test_hash_rejects_modified_input(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "file"
            path.write_bytes(b"abc")
            runner.verify_file(path, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            path.write_bytes(b"altered")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                runner.verify_file(path, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

    def test_exact_cells_in_source_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "notebook.ipynb"
            path.write_text(json.dumps({"cells": [
                {"id": "intro", "cell_type": "markdown", "source": ["ignore"]},
                {"id": "first", "cell_type": "code", "source": ["x = 1\n", "println(x)\n"]},
                {"id": "second", "cell_type": "code", "source": ["x += 2\n"]}]}))
            script, ids = runner.notebook_script(path, root)
            self.assertEqual(ids, ["first", "second"])
            self.assertEqual((root / "cell-0.jl").read_text(), "x = 1\nprintln(x)\n")
            text = script.read_text()
            self.assertLess(text.index("ITEMSET_CELL_OK first"), text.index("ITEMSET_CELL_START second"))

    def test_subprocess_failure_is_not_success(self):
        import sys
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "exit 7"):
                runner.run([sys.executable, "-c", "print('before failure'); raise SystemExit(7)"], root)
            self.assertIn("before failure", (root / "commands.log").read_text())


if __name__ == "__main__":
    unittest.main()
