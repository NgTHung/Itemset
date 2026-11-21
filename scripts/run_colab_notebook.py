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
import traceback
import urllib.request


JULIA_URL = "https://julialang-s3.julialang.org/bin/linux/x64/1.13/julia-1.13.2-linux-x86_64.tar.gz"
JULIA_SHA = "2ecdfc9890ab0a565fdd92404c915ba2a04a933dbd5d292cc224d13819d17d07"
JAVA_URL = "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jre_x64_linux_hotspot_25.0.5_8.tar.gz"
JAVA_SHA = "6fac98f0c8202efc3135a9e9e42aa61963ec42d1c5cbb40caf231e7b14a24ef6"
SPMF_SHA = "4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a"


def file_sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_file(path, expected):
    actual = file_sha(path)
    if actual != expected:
        raise ValueError(f"SHA-256 mismatch for {path}: {actual}, expected {expected}")


def install_archive(url, expected, parent, name):
    archive = parent / (name + ".tar.gz")
    urllib.request.urlretrieve(url, archive)
    verify_file(archive, expected)
    destination = parent / name
    destination.mkdir()
    with tarfile.open(archive) as package:
        roots = {Path(member.name).parts[0] for member in package.getmembers()}
        if len(roots) != 1:
            raise ValueError(f"archive has multiple roots: {archive}")
        package.extractall(destination, filter="data")
    return destination / roots.pop()


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
    lines.append('for (source, name) in ((pilot_output, "semeion"), '
                 '(encoding_output, "encoding"), (output, "spmf-smoke"))\n'
                 '    cp(source, joinpath(@__DIR__, name))\nend\n')
    script = evidence / "notebook-cells.jl"
    script.write_text("\n".join(lines), encoding="utf-8")
    return script, identifiers


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
    record = {"revision": args.revision, "status": "started", "execution":
              "hosted Colab CLI; exact notebook cells in one Julia subprocess"}
    try:
        run(["git", "clone", "https://github.com/NgTHung/Itemset", str(root)], evidence)
        run(["git", "checkout", "--detach", args.revision], evidence, cwd=root)
        if (root / ".julia-version").read_text().strip() != "1.13.2":
            raise ValueError("runner archive pin differs from .julia-version")
        julia_root = install_archive(JULIA_URL, JULIA_SHA, evidence, "julia-runtime")
        java_root = install_archive(JAVA_URL, JAVA_SHA, evidence, "java-runtime")
        julia, java = julia_root / "bin/julia", java_root / "bin/java"
        verify_file(args.spmf_jar, SPMF_SHA)
        shutil.copy2(args.spmf_jar, root / "tools/spmf/spmf.jar")
        record.update(julia_archive_sha256=JULIA_SHA, java_archive_sha256=JAVA_SHA,
                      spmf_sha256=SPMF_SHA,
                      julia_version=subprocess.check_output([julia, "--version"], text=True).strip(),
                      java_version=subprocess.run([java, "-version"], capture_output=True, text=True).stderr.strip())
        notebook = root / "notebooks/demo.ipynb"
        record["notebook_sha256"] = file_sha(notebook)
        script, identifiers = notebook_script(notebook, evidence)
        env = dict(os.environ, ITEMSET_ROOT=str(root), ITEMSET_JAVA=str(java),
                   JULIA_NUM_THREADS="1", JULIA_DEPOT_PATH=str(root.parent / (root.name + "-depot")))
        env["PATH"] = str(java.parent) + os.pathsep + env.get("PATH", "")
        run([str(julia), "--startup-file=no", "--project=.", str(script)], evidence, cwd=root, env=env)
        shutil.copytree(root / "results/raw/market_basket", evidence / "market_basket")
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
        import zipfile
        with zipfile.ZipFile(str(evidence) + ".zip", "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files + [evidence / "result.json"]:
                archive.write(path, path.relative_to(evidence))
        print("EVIDENCE_ARCHIVE " + str(evidence) + ".zip", flush=True)
    return 0 if record["status"] == "success" else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default=os.environ.get("ITEMSET_REVISION"))
    parser.add_argument("--spmf-jar", default="/content/itemset-spmf.jar")
    parser.add_argument("--root", default="/content/Itemset-cleanrun")
    parser.add_argument("--evidence", default="/content/itemset-cleanrun-evidence")
    return execute(parser.parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
