"""Plot frequent-itemset counts and mean itemset length against minsup from output_size.jl's output-size.csv.

Both panels share one log minsup axis that decreases to the right, so each line reads as the threshold
falls. Dense databases draw solid and sparse ones dashed, and the CSV beside the figure gives each
dataset's log-log slope, the growth rate the report compares.
"""

import argparse
import csv
import math
from pathlib import Path
from typing import NamedTuple

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["svg.fonttype"] = "none"
import matplotlib.pyplot as plt

from plot_runtime_curves import display_name

DENSE = {"chess", "mushroom", "accidents"}
COLORS = {"chess": "#2468a2", "mushroom": "#8c4fa1", "accidents": "#b0384b",
          "retail": "#d97716", "T10I4D100K": "#25814a"}
MARKERS = {"chess": "o", "mushroom": "D", "accidents": "v", "retail": "s", "T10I4D100K": "^"}


class GrowthFit(NamedTuple):
    slope: float
    r_squared: float
    adjacent_slopes: list
    per_hundredth: float


def least_squares(xs, ys):
    """Slope and coefficient of determination of the least-squares line of ys on xs."""
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    slope = sum((a - mx) * (b - my) for a, b in zip(xs, ys)) / sum((a - mx) ** 2 for a in xs)
    residual = sum((b - my - slope * (a - mx)) ** 2 for a, b in zip(xs, ys))
    total = sum((b - my) ** 2 for b in ys)
    return slope, 1 - residual / total


def growth_fit(xs, counts):
    """Fit log(count) = c - s log(minsup), with slopes negated so faster growth is a larger number.

    The fit also gives the slope between each pair of adjacent thresholds, which shows where
    the curve bends, and the slope of log(count) per 0.01 of minsup, which the report contrasts
    with s because it depends on the scale of each database's minsup range.
    """
    lx, ly = [math.log(x) for x in xs], [math.log(y) for y in counts]
    slope, r_squared = least_squares(lx, ly)
    adjacent = [-(ly[i + 1] - ly[i]) / (lx[i + 1] - lx[i]) for i in range(len(xs) - 1)]
    linear_slope, _ = least_squares(xs, ly)
    return GrowthFit(-slope, r_squared, adjacent, -0.01 * linear_slope)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("table", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    with args.table.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise SystemExit(f"{args.table} has no rows")
    datasets = list(dict.fromkeys(r["dataset"] for r in rows))
    unknown = [d for d in datasets if d not in COLORS]
    if unknown:
        raise SystemExit(f"no style for {', '.join(unknown)}")

    fig, (counts_ax, length_ax) = plt.subplots(1, 2, figsize=(8.4, 3.4))
    slopes = []
    for dataset in datasets:
        points = sorted((r for r in rows if r["dataset"] == dataset), key=lambda r: -float(r["minsup_relative"]))
        xs = [float(r["minsup_relative"]) for r in points]
        counts = [int(r["output_count"]) for r in points]
        lengths = [float(r["mean_length"]) for r in points]
        kind = "dense" if dataset in DENSE else "sparse"
        style = dict(color=COLORS[dataset], marker=MARKERS[dataset], markersize=4.5, linewidth=1.3,
                     linestyle="-" if dataset in DENSE else "--", label=f"{display_name(dataset)} ({kind})")
        counts_ax.plot(xs, counts, **style)
        length_ax.plot(xs, lengths, **style)
        fit = growth_fit(xs, counts)
        slopes.append((dataset, kind, xs[0], xs[-1], counts[0], counts[-1], round(fit.slope, 2),
                       round(fit.r_squared, 3), " ".join(f"{s:.1f}" for s in fit.adjacent_slopes),
                       round(fit.per_hundredth, 2)))
    for ax in (counts_ax, length_ax):
        ax.set_xscale("log")
        ax.invert_xaxis()
        ax.set_xlabel("minsup (log, decreasing)", fontsize=8)
        ax.grid(which="major", alpha=0.18)
        ax.spines[["top", "right"]].set_visible(False)
        ax.tick_params(labelsize=7.5)
        ax.xaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:g}"))
    counts_ax.set_yscale("log")
    counts_ax.set_ylabel("Frequent itemsets (log)", fontsize=8)
    length_ax.set_ylabel("Mean itemset length", fontsize=8)
    length_ax.set_ylim(bottom=0)
    counts_ax.legend(frameon=False, fontsize=7)
    fig.tight_layout()
    args.out.mkdir(parents=True, exist_ok=True)
    for suffix in ("png", "svg", "pdf"):
        fig.savefig(args.out / f"output-size.{suffix}", dpi=300, bbox_inches="tight")
    plt.close(fig)
    with (args.out / "output-growth.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("dataset", "kind", "minsup_high", "minsup_low", "count_high", "count_low", "log_log_slope",
                         "r_squared", "adjacent_slopes", "log_slope_per_0.01_minsup"))
        writer.writerows(slopes)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
