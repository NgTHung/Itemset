"""Plot which thresholds of a verified runtime campaign match SPMF exactly, for the IEEE report.

The input is one run directory that times both Julia variants, and possibly the SPMF programs, at every
threshold. Every attempt must match its SPMF reference, and only the two Julia variants are plotted.
"""

import argparse
import csv
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path
import tomllib

import matplotlib

matplotlib.use("Agg")
from matplotlib import pyplot as plt


VARIANTS = ("baseline", "optimized")
DATASETS = {
    "chess": "Chess",
    "mushroom": "Mushroom",
    "retail": "Retail",
    "T10I4D100K": "T10I4D100K",
    "accidents": "Accidents",
}
# The Vietnamese report writes decimals with a comma, so its copy of each figure needs its own text.
LABELS = {
    "en": dict(decimal=".", grid="Threshold position in the grid"),
    "vi": dict(decimal=",", grid="Thứ tự ngưỡng trong lưới"),
}


def attempt_key(row):
    return (row["dataset"], Decimal(row["minsup_relative"]), row["variant"], int(row["repeat"]))


def exact(row):
    return (row["status"], row["correctness_status"], float(row["match_rate"] or 0)) == ("ok", "exact", 1)


def read_process_rows(run):
    with (run / "config.toml").open("rb") as stream:
        config = tomllib.load(stream)
    with (run / "runs.csv").open(encoding="utf-8-sig", newline="") as stream:
        rows = [row for row in csv.DictReader(stream) if row["timing_scope"] == "process"]
    expected = Counter(
        (series["dataset"], Decimal(str(minsup)), variant, repeat)
        for series in config["series"]
        for minsup in series["minsup"]
        for variant in config["variants"]
        for repeat in range(1, config["repeats"] + 1)
    )
    actual = Counter(map(attempt_key, rows))
    if actual != expected:
        raise ValueError(f"{run}: run does not contain exactly the planned attempts")
    return rows


def require_exact(rows):
    references = defaultdict(set)
    for row in rows:
        if not exact(row):
            raise ValueError(f"Nonmatching attempt: {row['attempt_id']}")
        references[row["dataset"], row["minsup_count"]].add(row["comparison_reference_sha256"])
    if any(len(digests) != 1 or "" in digests for digests in references.values()):
        raise ValueError("Expected one SPMF reference per dataset and count threshold")


def plot_coverage(rows, destination, language="en"):
    text = LABELS[language]
    thresholds = defaultdict(set)
    variants = defaultdict(set)
    for row in (row for row in rows if row["variant"] in VARIANTS):
        minsup = Decimal(row["minsup_relative"])
        thresholds[row["dataset"]].add(minsup)
        variants[row["dataset"], minsup].add(row["variant"])
    if any(choices != set(VARIANTS) for choices in variants.values()):
        raise ValueError("Correctness coverage requires both Julia variants at every point")
    dataset_order = [name for name in DATASETS if name in thresholds]
    columns = max(map(len, thresholds.values()))
    fig, ax = plt.subplots(figsize=(4.4, 1.95), layout="constrained")
    ax.set_yticks(range(len(dataset_order)), [DATASETS[name] for name in dataset_order])
    ax.set_xticks(range(columns), range(1, columns + 1))
    ax.set_xlabel(text["grid"])
    ax.set_ylim(len(dataset_order) - 0.5, -0.5)
    ax.set_xlim(-0.5, columns - 0.5)
    for index, name in enumerate(dataset_order):
        values = sorted(thresholds[name], reverse=True)
        ax.barh(index, len(values) - 0.12, left=-0.44, height=0.76, color="#176681")
        for column, value in enumerate(values):
            percent = format((value * 100).normalize(), "f").replace(".", text["decimal"])
            ax.text(column, index, percent, color="white", ha="center", va="center", fontsize=9)
        for column in range(len(values) - 1):
            ax.vlines(column + 0.5, index - 0.38, index + 0.38, color="white", linewidth=0.8)
    ax.tick_params(length=0)
    for spine in ax.spines.values():
        spine.set_visible(False)
    fig.savefig(destination)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path, help="run directory of the runtime campaign")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--language", choices=sorted(LABELS), default="en")
    args = parser.parse_args()
    rows = read_process_rows(args.run)
    require_exact(rows)
    args.out.mkdir(parents=True, exist_ok=True)
    plot_coverage(rows, args.out / "correctness-grid.pdf", args.language)


if __name__ == "__main__":
    main()
