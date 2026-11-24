"""Execute the Julia notebook cells on a hosted Linux Colab runtime."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import tomllib
import traceback
import urllib.request
import zipfile


JULIA_URL = "https://julialang-s3.julialang.org/bin/linux/x64/1.13/julia-1.13.2-linux-x86_64.tar.gz"
JULIA_SHA = "2ecdfc9890ab0a565fdd92404c915ba2a04a933dbd5d292cc224d13819d17d07"
JAVA_URL = "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jre_x64_linux_hotspot_25.0.5_8.tar.gz"
JAVA_SHA = "6fac98f0c8202efc3135a9e9e42aa61963ec42d1c5cbb40caf231e7b14a24ef6"


def file_sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def copy_verified(source, destination, expected):
    digest = hashlib.sha256()
    with tempfile.TemporaryDirectory(dir=destination.parent) as directory:
        staged = Path(directory) / destination.name
        with staged.open("wb") as stream:
            while chunk := source.read(1024 * 1024):
                stream.write(chunk)
                digest.update(chunk)
        actual = digest.hexdigest()
        if actual != expected:
            raise ValueError(f"SHA-256 mismatch for {destination}: {actual}, expected {expected}")
        staged.replace(destination)


def download_verified(url, destination, expected):
    with urllib.request.urlopen(url, timeout=60) as source:
        copy_verified(source, destination, expected)


def install_archive(url, expected, parent, name):
    archive = parent / (name + ".tar.gz")
    print(f"Downloading {name}", flush=True)
    download_verified(url, archive, expected)
    destination = parent / name
    destination.mkdir()
    with tarfile.open(archive) as package:
        roots = {Path(member.name).parts[0] for member in package.getmembers()}
        if len(roots) != 1:
            raise ValueError(f"archive has multiple roots: {archive}")
        package.extractall(destination, filter="data")
    return destination / roots.pop()


def prepare_spmf(release, jar, destination):
    if jar is None:
        print("Downloading pinned SPMF JAR", flush=True)
        download_verified(release["url"], destination, release["sha256"])
        return release["url"]
    source = Path(jar).resolve()
    with source.open("rb") as stream:
        copy_verified(stream, destination, release["sha256"])
    return str(source)


def notebook_script(notebook, evidence):
    cells = [cell for cell in json.loads(notebook.read_text(encoding="utf-8"))["cells"]
             if cell["cell_type"] == "code"]
    identifiers = [cell["id"] for cell in cells]
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("duplicate notebook cell IDs")
    lines = []
    for index, cell in enumerate(cells):
        path = evidence / f"cell-{index}.jl"
        path.write_text("".join(cell["source"]), encoding="utf-8")
        ident = cell["id"]
        lines.append(f'println({json.dumps("ITEMSET_CELL_START " + ident)})\n'
                     f'include({json.dumps(str(path))})\n'
                     f'println({json.dumps("ITEMSET_CELL_OK " + ident)})\n')
    script = evidence / "notebook-cells.jl"
    script.write_text("\n".join(lines), encoding="utf-8")
    return script, identifiers


def collect_artifacts(manifest, evidence):
    with manifest.open("rb") as stream:
        folders = tomllib.load(stream)
    required = {"encoding", "semeion", "spmf-smoke", "market_basket"}
    missing = required.difference(folders)
    if missing:
        raise ValueError(f"Notebook artifacts missing: {', '.join(sorted(missing))}")
    for name in sorted(required):
        source = Path(folders[name])
        if not source.is_dir():
            raise ValueError(f"Notebook artifact {name} is not a directory: {source}")
        shutil.copytree(source, evidence / name)


def run(command, evidence, *, cwd=None, env=None):
    print("RUN", json.dumps([str(arg) for arg in command]), flush=True)
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    with (evidence / "commands.log").open("a", encoding="utf-8") as log:
        for line in process.stdout:
            log.write(line)
            log.flush()
            print(line.rstrip(), flush=True)
    process.stdout.close()
    if process.wait():
        raise RuntimeError(f"exit {process.returncode}: {command[0]}")


def execute(args):
    if not re.fullmatch(r"[0-9a-f]{40}", args.revision or ""):
        raise ValueError("revision must be an exact 40-character Git commit SHA")
    root, evidence = Path(args.root).resolve(), Path(args.evidence).resolve()
    if root.exists() or evidence.exists():
        raise ValueError("root and evidence directories must both be fresh")
    evidence.mkdir(parents=True)
    record = {"repository": args.repository, "revision": args.revision, "status": "started",
              "execution": "Colab CPU runtime running the exact notebook cells in one Julia subprocess"}
    try:
        run(["git", "clone", "--", args.repository, str(root)], evidence)
        run(["git", "checkout", "--detach", args.revision], evidence, cwd=root)
        if (root / ".julia-version").read_text().strip() != "1.13.2":
            raise ValueError("runner archive pin differs from .julia-version")
        with (root / "tools/spmf/release.toml").open("rb") as stream:
            release = tomllib.load(stream)
        julia_root = install_archive(JULIA_URL, JULIA_SHA, evidence, "julia-runtime")
        java_root = install_archive(JAVA_URL, JAVA_SHA, evidence, "java-runtime")
        julia, java = julia_root / "bin/julia", java_root / "bin/java"
        spmf_source = prepare_spmf(release, args.spmf_jar, root / "tools/spmf/spmf.jar")
        record.update(julia_archive_sha256=JULIA_SHA, java_archive_sha256=JAVA_SHA,
                      spmf_sha256=release["sha256"], spmf_version=release["version"], spmf_source=spmf_source,
                      julia_version=subprocess.check_output([julia, "--version"], text=True).strip(),
                      java_version=subprocess.run([java, "-version"], capture_output=True, text=True).stderr.strip())
        notebook = root / "notebooks/demo.ipynb"
        record["notebook_sha256"] = file_sha(notebook)
        script, identifiers = notebook_script(notebook, evidence)
        artifact_manifest = evidence / "notebook-artifacts.toml"
        # Keep the caches from the verified Julia archive and isolate the writable user depot.
        depot_path = str(root.parent / (root.name + "-depot")) + os.pathsep
        env = dict(os.environ, ITEMSET_ROOT=str(root), ITEMSET_JAVA=str(java),
                   ITEMSET_ARTIFACT_MANIFEST=str(artifact_manifest),
                   JULIA_NUM_THREADS="1", JULIA_DEPOT_PATH=depot_path)
        env["PATH"] = str(java.parent) + os.pathsep + env.get("PATH", "")
        run([str(julia), "--startup-file=no", "--project=.", str(script)], evidence, cwd=root, env=env)
        collect_artifacts(artifact_manifest, evidence)
        record.update(status="success", code_cells=len(identifiers), cell_ids=identifiers)
        print("ITEMSET_HOSTED_NOTEBOOK_OK", flush=True)
    except Exception as error:
        record.update(status="failed", error=str(error))
        traceback.print_exc()
    finally:
        # Runtime distributions are large; retain their verified hashes in the record.
        files = [p for p in evidence.rglob("*") if p.is_file()
                 and not any(part.startswith(("julia-runtime", "java-runtime"))
                             for part in p.relative_to(evidence).parts)]
        record["artifact_sha256"] = {p.relative_to(evidence).as_posix(): file_sha(p) for p in files}
        (evidence / "result.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
        with zipfile.ZipFile(str(evidence) + ".zip", "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files + [evidence / "result.json"]:
                archive.write(path, path.relative_to(evidence))
        print("EVIDENCE_ARCHIVE " + str(evidence) + ".zip", flush=True)
    return 0 if record["status"] == "success" else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, help="Git URL of the notebook checkout")
    parser.add_argument("--revision", default=os.environ.get("ITEMSET_REVISION"))
    parser.add_argument("--spmf-jar", help="Use a local copy of the pinned JAR instead of downloading it")
    parser.add_argument("--root", default="/content/Itemset-cleanrun")
    parser.add_argument("--evidence", default="/content/itemset-cleanrun-evidence")
    return execute(parser.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
