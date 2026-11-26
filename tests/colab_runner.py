import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("colab_runner", ROOT / "scripts/run_colab_notebook.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
COLAB_CELL = "".join(next(
    cell["source"] for cell in json.loads((ROOT / "notebooks/demo_colab.ipynb").read_text(encoding="utf-8"))["cells"]
    if cell["id"] == "itemset-colab-run"
))
RELEASE = (ROOT / "tools/spmf/release.toml").read_text(encoding="utf-8")


class RunnerTests(unittest.TestCase):
    def test_explicit_arguments_ignore_jupyter_kernel_flags(self):
        with patch("sys.argv", ["ipykernel", "-f", "kernel.json"]), patch.object(runner, "execute", return_value=0) as execute:
            self.assertEqual(runner.main(["--repository", "https://github.com/example/Itemset", "--revision", "a" * 40]), 0)
            self.assertEqual(execute.call_args.args[0].revision, "a" * 40)

    def test_invalid_local_jar_leaves_the_previous_file_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "uploaded.jar"
            source.write_bytes(b"altered")
            destination = Path(directory) / "spmf.jar"
            destination.write_bytes(b"abc")
            release = {"sha256": runner.file_sha(destination)}
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                runner.prepare_spmf(release, source, destination)
            self.assertEqual(destination.read_bytes(), b"abc")

    def test_public_spmf_download_requires_the_pinned_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "spmf.jar"
            release = {"url": "https://example.com/spmf.jar", "sha256": "0" * 64}
            with patch.object(runner.urllib.request, "urlopen", return_value=io.BytesIO(b"replacement")):
                with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                    runner.prepare_spmf(release, None, destination)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_prepares_the_verified_spmf_jar_from_either_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            local_jar = root / "uploaded.jar"
            local_jar.write_bytes(b"abc")
            release = {"url": "https://example.com/spmf.jar", "sha256": runner.file_sha(local_jar)}
            with patch.object(runner.urllib.request, "urlopen", return_value=io.BytesIO(b"abc")) as download:
                public_destination = root / "downloaded.jar"
                self.assertEqual(runner.prepare_spmf(release, None, public_destination), release["url"])
                self.assertEqual(public_destination.read_bytes(), b"abc")
                download.assert_called_once_with(release["url"], timeout=60)
                download.reset_mock()

                local_destination = root / "copied.jar"
                self.assertEqual(runner.prepare_spmf(release, local_jar, local_destination), str(local_jar.resolve()))
                self.assertEqual(local_destination.read_bytes(), b"abc")
                download.assert_not_called()

    def test_public_notebook_uses_runner_cli_and_one_repository(self):
        repository = "https://github.com/example/Itemset.git"
        sha = "a" * 40
        for supplied_revision in ("", sha):
            with self.subTest(supplied_revision=supplied_revision), tempfile.TemporaryDirectory() as directory:
                workspace = Path(directory)
                configured = COLAB_CELL.replace('ITEMSET_REVISION = ""', f'ITEMSET_REVISION = "{supplied_revision}"')
                with (
                    patch.dict("os.environ", {"ITEMSET_REPOSITORY": repository}, clear=True),
                    patch("tempfile.mkdtemp", return_value=directory),
                    patch("subprocess.check_output", return_value=f"{sha}\tHEAD\n") as remote,
                    patch("urllib.request.urlopen", return_value=io.BytesIO(b"runner")) as download,
                    patch("runpy.run_path", return_value={"main": runner.main}),
                    patch.object(runner, "execute", return_value=0) as execute,
                ):
                    exec(compile(configured, "notebooks/demo_colab.ipynb", "exec"), {})
                if supplied_revision:
                    remote.assert_not_called()
                else:
                    remote.assert_called_once_with(
                        ["git", "ls-remote", "--exit-code", repository, "HEAD"],
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

    def test_public_notebook_rejects_bad_inputs_before_network_access(self):
        repository = "https://github.com/example/Itemset"
        for url, revision, message in (
            (repository + "/tree/main", "a" * 40, "GitHub HTTPS clone URL"),
            (repository + "?tab=readme", "a" * 40, "GitHub HTTPS clone URL"),
            (repository, "main", "40-character commit SHA"),
        ):
            with (
                self.subTest(url=url, revision=revision),
                patch.dict("os.environ", {"ITEMSET_REPOSITORY": url, "ITEMSET_REVISION": revision}, clear=True),
                patch("subprocess.check_output") as remote,
                patch("urllib.request.urlopen") as download,
                self.assertRaisesRegex(ValueError, message),
            ):
                exec(compile(COLAB_CELL, "notebooks/demo_colab.ipynb", "exec"), {})
            remote.assert_not_called()
            download.assert_not_called()

    def test_julia_process_uses_a_fresh_depot_and_bundled_caches(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory).resolve()
            root = workspace / "repo"

            def checkout(command, _, **kwargs):
                if command[:2] == ["git", "clone"]:
                    (root / "tools/spmf").mkdir(parents=True)
                    (root / ".julia-version").write_text("1.13.2\n", encoding="utf-8")
                    (root / "tools/spmf/release.toml").write_text(RELEASE, encoding="utf-8")
                if command[0] != "git":
                    self.assertEqual(kwargs["env"]["JULIA_DEPOT_PATH"], str(workspace / "repo-depot") + os.pathsep)

            with (
                patch.dict("os.environ", {"JULIA_DEPOT_PATH": "existing-user-depot"}),
                patch.object(runner, "run", side_effect=checkout) as run,
                patch.object(runner, "install_archive", return_value=workspace),
                patch.object(runner, "prepare_spmf", return_value="example.jar"),
                patch.object(runner, "notebook_script", return_value=("demo.jl", ["one"])),
                patch.object(runner, "collect_artifacts"),
                patch.object(runner, "file_sha", return_value="hash"),
                patch("subprocess.check_output", return_value="1.13.2"),
                patch("subprocess.run", return_value=SimpleNamespace(stderr="java 25")),
            ):
                self.assertEqual(runner.main([
                    "--repository", "https://github.com/example/Itemset", "--revision", "a" * 40,
                    "--root", str(root), "--evidence", str(workspace / "evidence"),
                ]), 0)
            self.assertEqual(run.call_count, 3)

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
                    (root / "tools/spmf").mkdir(parents=True)
                    (root / ".julia-version").write_text("1.13.2\n", encoding="utf-8")
                    (root / "tools/spmf/release.toml").write_text(RELEASE, encoding="utf-8")

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
            names = ("spmf-smoke",)
            entries = [f"{name} = {json.dumps(str(source))}\n" for name in names]
            manifest.write_text("", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "spmf-smoke"):
                runner.collect_artifacts(manifest, evidence)
            manifest.write_text("".join(entries), encoding="utf-8")
            runner.collect_artifacts(manifest, evidence)
            for name in names:
                self.assertEqual((evidence / name / "proof.txt").read_text(), "proof")


if __name__ == "__main__":
    unittest.main()
