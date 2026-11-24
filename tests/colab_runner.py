import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("colab_runner", ROOT / "scripts/run_colab_notebook.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def test_explicit_arguments_ignore_jupyter_kernel_flags(self):
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

    def test_public_spmf_download_requires_the_pinned_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "spmf.jar"
            with patch.object(runner.urllib.request, "urlopen", return_value=io.BytesIO(b"replacement")):
                with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                    runner.prepare_spmf(None, destination)

    def test_prepares_the_verified_spmf_jar_from_either_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            local_jar = root / "uploaded.jar"
            local_jar.write_bytes(b"abc")
            sha = runner.file_sha(local_jar)
            with patch.object(runner, "SPMF_SHA", sha), patch.object(
                runner.urllib.request, "urlopen", return_value=io.BytesIO(b"abc")
            ) as download:
                public_destination = root / "downloaded.jar"
                self.assertEqual(runner.prepare_spmf(None, public_destination), runner.SPMF_URL)
                self.assertEqual(public_destination.read_bytes(), b"abc")
                download.assert_called_once_with(runner.SPMF_URL, timeout=60)
                download.reset_mock()

                local_destination = root / "copied.jar"
                self.assertEqual(runner.prepare_spmf(local_jar, local_destination), "local copy")
                self.assertEqual(local_destination.read_bytes(), b"abc")
                download.assert_not_called()

    def test_public_notebook_uses_runner_cli_and_one_repository(self):
        notebook = json.loads((ROOT / "notebooks/colab.ipynb").read_text(encoding="utf-8"))
        cell = next(cell for cell in notebook["cells"] if cell["id"] == "itemset-colab-run")
        source = "".join(cell["source"])
        repository = "https://github.com/example/Itemset.git"
        sha = "a" * 40
        for supplied_revision in ("", sha):
            with self.subTest(supplied_revision=supplied_revision), tempfile.TemporaryDirectory() as directory:
                workspace = Path(directory)
                configured = source.replace('ITEMSET_REVISION = ""', f'ITEMSET_REVISION = "{supplied_revision}"')
                with (
                    patch.dict("os.environ", {"ITEMSET_REPOSITORY": repository}, clear=True),
                    patch("tempfile.mkdtemp", return_value=directory),
                    patch("subprocess.check_output", return_value=f"{sha}\trefs/heads/main\n") as remote,
                    patch("urllib.request.urlopen", return_value=io.BytesIO(b"runner")) as download,
                    patch("runpy.run_path", return_value={"main": runner.main}),
                    patch.object(runner, "execute", return_value=0) as execute,
                ):
                    exec(compile(configured, "notebooks/colab.ipynb", "exec"), {})
                if supplied_revision:
                    remote.assert_not_called()
                else:
                    remote.assert_called_once_with(
                        ["git", "ls-remote", "--exit-code", repository, "refs/heads/main"],
                        text=True, timeout=60,
                    )
                download.assert_called_once_with(
                    f"https://raw.githubusercontent.com/example/Itemset/{sha}/scripts/run_colab_notebook.py",
                    timeout=60,
                )
                args = execute.call_args.args[0]
                self.assertEqual((args.repository, args.revision), (repository, sha))
                self.assertEqual(Path(args.root), workspace / "repo")
                self.assertEqual(Path(args.evidence), workspace / "evidence")

    def test_download_timeout_writes_failure_evidence(self):
        from zipfile import ZipFile

        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory).resolve()
            root, evidence = workspace / "repo", workspace / "evidence"
            repository = "https://github.com/example/Itemset"
            sha = "a" * 40

            def git(command, _, **kwargs):
                if command[:2] == ["git", "clone"]:
                    self.assertEqual(command[2:], ["--", repository, str(root)])
                    root.mkdir()
                    (root / ".julia-version").write_text("1.13.2\n", encoding="utf-8")

            with patch.object(runner, "run", side_effect=git), patch.object(
                runner.urllib.request, "urlopen", side_effect=TimeoutError("download stalled")
            ):
                self.assertEqual(runner.main([
                    "--repository", repository, "--revision", sha,
                    "--root", str(root), "--evidence", str(evidence),
                ]), 1)
            with ZipFile(evidence.with_suffix(".zip")) as archive:
                record = json.loads(archive.read("result.json"))
            self.assertEqual(record["status"], "failed")
            self.assertEqual(record["error"], "download stalled")
            self.assertEqual(record["repository"], repository)

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

    def test_collects_manifest_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "run"
            source.mkdir()
            (source / "proof.txt").write_text("proof", encoding="utf-8")
            evidence = root / "evidence"
            evidence.mkdir()
            manifest = evidence / "notebook-artifacts.toml"
            names = ("semeion", "encoding", "spmf-smoke", "market_basket")
            entries = [f"{name} = {json.dumps(str(source))}\n" for name in names]
            manifest.write_text("".join(entries[:2]), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "spmf-smoke"):
                runner.collect_artifacts(manifest, evidence)
            manifest.write_text("".join(entries), encoding="utf-8")
            runner.collect_artifacts(manifest, evidence)
            for name in names:
                self.assertEqual((evidence / name / "proof.txt").read_text(), "proof")


if __name__ == "__main__":
    unittest.main()
