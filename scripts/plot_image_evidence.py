"""Draw two source digits and the accepted patches from a Semeion mining run."""

import argparse
import csv
import hashlib
import tomllib
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle


def read_evidence(path, ids, minsup, words):
    with path.open(newline="", encoding="utf-8") as stream:
        return [r for r in csv.DictReader(stream, delimiter="\t")
                if int(r["image_id"]) in ids and float(r["minsup"]) == minsup and r["items"] == words]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("run", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--minsup", type=float, default=0.05)
    parser.add_argument("--words", default="4,8,13")
    parser.add_argument("--ids", nargs=2, type=int, default=[44, 41])
    args = parser.parse_args()
    data = args.source.read_bytes()
    manifest = tomllib.loads((args.run / "mining_manifest.toml").read_text(encoding="utf-8"))
    if hashlib.sha256(data).hexdigest() != manifest["source_sha256"]:
        raise ValueError("Semeion source does not match the run")
    examples = read_evidence(args.run / "examples.tsv", args.ids, args.minsup, args.words)
    patches = read_evidence(args.run / "example_patches.tsv", args.ids, args.minsup, args.words)
    images = data.splitlines()
    by_id = {int(row["image_id"]): row for row in examples}
    if len(examples) != 2 or set(by_id) != set(args.ids):
        raise ValueError("each requested image must appear once in the pattern examples")
    palette = ("#0050aa", "#ad4400", "#007050", "#772d8b")
    colors = {word: palette[i % len(palette)] for i, word in enumerate(args.words.split(","))}
    fig, axes = plt.subplots(1, 2, figsize=(5, 2.7), layout="constrained")
    for ax, image_id in zip(axes, args.ids, strict=True):
        row = by_id[image_id]
        fields = images[image_id - 1].split()
        pixels = [list(map(float, fields[i:i + 16])) for i in range(0, 256, 16)]
        if fields[256:].index(b"1") != int(row["label"]):
            raise ValueError(f"source label differs for image {image_id}")
        ax.imshow(pixels, cmap="binary", vmin=0, vmax=1, interpolation="nearest")
        image_patches = [p for p in patches if int(p["image_id"]) == image_id]
        if {p["word"] for p in image_patches} != set(filter(None, row["present_words"].split(","))):
            raise ValueError(f"incomplete source patches for image {image_id}")
        for patch in image_patches:
            r, c = int(patch["row"]) - 1, int(patch["col"]) - 1
            bitstring = "".join(str(int(value)) for line in pixels[r:r + 4] for value in line[c:c + 4])
            if bitstring != patch["patch_row_major"]:
                raise ValueError(f"source patch differs for image {image_id}")
            color = colors[patch["word"]]
            ax.add_patch(Rectangle((c - 0.5, r - 0.5), 4, 4, fill=False, edgecolor=color, linewidth=2))
            ax.text(c, r, patch["word"], color="white", fontsize=10, ha="left", va="top",
                    bbox={"facecolor": color, "edgecolor": "none", "pad": 1})
        status = f"Missing {row['missing_words']}" if row["missing_words"] else "All target words present"
        ax.set_title(f"Image {image_id} · digit {row['label']}\n{status}", fontsize=11)
        ax.set_axis_off()
    fig.savefig(args.output, dpi=220)
    plt.close(fig)


if __name__ == "__main__":
    main()
