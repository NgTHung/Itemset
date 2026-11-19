"""Plot runtime against database size, one panel per base database, from runtime_curves.jl's curves.csv.

Each subset dataset is named BASE-pPERCENT, as prepare_subsets.jl names it, and its transaction
count comes from data/benchmark/subsets.toml, so the x axis shows actual sizes, not fractions.
"""

import argparse
import csv
import re
import tomllib
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["svg.fonttype"] = "none"
import matplotlib.pyplot as plt

from plot_runtime_curves import assign_styles, compact, lost, read_points

SUBSET = re.compile(r"^(?P<base>.+)-p(?P<percent>[0-9.]+)$")
# The report is in Vietnamese, so its copy of the figure needs its own axis text.
LABELS = {
    "en": dict(x="Transactions, with frequent itemsets below", y="Median seconds, IQR bars", series={}),
    "vi": dict(x="Số giao dịch, số tập phổ biến bên dưới", y="Trung vị thời gian (s), thanh IQR",
               series={"Baseline Eclat": "Eclat cơ bản", "Optimized Eclat": "Eclat tối ưu",
                       "SPMF Eclat": "Eclat của SPMF", "SPMF PrePost+": "PrePost+ của SPMF"}),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("curves", type=Path)
    parser.add_argument("--subsets", type=Path, default=Path("data/benchmark/subsets.toml"))
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--language", choices=sorted(LABELS), default="en")
    args = parser.parse_args()
    rows = read_points(args.curves)
    manifest = tomllib.loads(args.subsets.read_text(encoding="utf-8"))
    panels = defaultdict(lambda: defaultdict(list))
    for row in rows:
        match = SUBSET.match(row["dataset"])
        if not match or row["dataset"] not in manifest:
            raise SystemExit(f"{row['dataset']} is not a subset recorded in {args.subsets}")
        row["transactions"] = manifest[row["dataset"]]["transactions"]
        panels[match["base"]][row["series"]].append(row)
    series = list(dict.fromkeys(r["series"] for r in rows))
    style = assign_styles(series)

    fig, axes = plt.subplots(1, len(panels), figsize=(4.2 * len(panels), 3.4), squeeze=False)
    table = []
    for ax, (base, by_series) in zip(axes.flat, panels.items()):
        sizes = sorted({r["transactions"] for rs in by_series.values() for r in rs})
        counts = {r["transactions"]: r["output_count"] for rs in by_series.values() for r in rs if r["output_count"]}
        for name in series:
            points = sorted(by_series.get(name, []), key=lambda r: r["transactions"])
            timed = [r for r in points if r["median_seconds"] and not lost(r)]
            xs = [r["transactions"] for r in timed]
            ys = [float(r["median_seconds"]) for r in timed]
            lower = [y - float(r["q1_seconds"]) for y, r in zip(ys, timed)]
            upper = [float(r["q3_seconds"]) - y for y, r in zip(ys, timed)]
            color, marker = style[name]
            ax.errorbar(xs, ys, yerr=[lower, upper], fmt=f"-{marker}", color=color, markersize=4.5,
                        capsize=2.5, linewidth=1.3, elinewidth=1.0,
                        label=LABELS[args.language]["series"].get(name, name))
            for r in points:
                table.append((base, name, r["transactions"], r["minsup_count"], r["output_count"],
                              r["median_seconds"], r["q1_seconds"], r["q3_seconds"], int(lost(r))))
        ax.set_xlim(0, sizes[-1] * 1.05)
        ax.set_ylim(bottom=0)
        ax.set_xticks(sizes, [f"{n / 1000:.0f}k\n{compact(counts[n])}" if n in counts else f"{n / 1000:.0f}k"
                              for n in sizes], fontsize=6.5)
        minsup = next(iter(by_series.values()))[0]["minsup_relative"]
        ax.set_title(f"{base}, minsup {minsup}", fontsize=10)
        ax.set_xlabel(LABELS[args.language]["x"], fontsize=7.5)
        ax.set_ylabel(LABELS[args.language]["y"], fontsize=8)
        ax.grid(axis="y", alpha=0.18)
        ax.spines[["top", "right"]].set_visible(False)
    axes.flat[0].legend(frameon=False, fontsize=7.5)
    fig.tight_layout()
    args.out.mkdir(parents=True, exist_ok=True)
    for suffix in ("png", "svg", "pdf"):
        fig.savefig(args.out / f"scalability.{suffix}", dpi=300, bbox_inches="tight")
    plt.close(fig)
    with (args.out / "scalability.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("database", "series", "transactions", "minsup_count", "output_count",
                         "median_seconds", "q1_seconds", "q3_seconds", "lost_samples"))
        writer.writerows(sorted(table))
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
