"""Plot Eclat runtime and output volume against transaction width from two curves.csv files."""

import argparse
import csv
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["svg.fonttype"] = "none"
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

from plot_runtime_curves import assign_styles, compact, lost, read_points

WIDTH = re.compile(r"width-w(\d+)$")


def width_of(row):
    match = WIDTH.match(row["dataset"])
    if match is None:
        raise SystemExit(f"dataset {row['dataset']!r} is not a width database (width-wNN)")
    return int(match.group(1))


def plot_runtime(ax, rows, series, style, title):
    widths = sorted({width_of(r) for r in rows})
    ax.set_yscale("log")
    for name in series:
        color, marker = style[name]
        samples = sorted((r for r in rows if r["series"] == name), key=width_of)
        timed = [r for r in samples if r["median_seconds"]]
        ys = [float(r["median_seconds"]) for r in timed]
        ax.errorbar([width_of(r) for r in timed], ys,
                    yerr=[[y - float(r["q1_seconds"]) for y, r in zip(ys, timed)],
                          [float(r["q3_seconds"]) - y for y, r in zip(ys, timed)]],
                    fmt=f"-{marker}", color=color, markersize=4.5, capsize=2.5, linewidth=1.3, elinewidth=1.0)
        for r in samples:
            if lost(r):
                ax.plot([width_of(r)], [1], marker="X", color=color, markersize=9, markeredgecolor="#a02020",
                        markeredgewidth=1.2, linestyle="none", clip_on=False, transform=ax.get_xaxis_transform())
    counts = {width_of(r): r["output_count"] for r in rows if r["output_count"]}
    ax.set_xticks(widths, [f"{w}\n{compact(counts[w])}" if w in counts else str(w) for w in widths], fontsize=7)
    ax.set_xlabel("transaction width, with frequent itemsets below", fontsize=8)
    ax.set_title(title, fontsize=10)
    ax.minorticks_off()
    ax.grid(axis="y", which="both", alpha=0.18)
    ax.spines[["top", "right"]].set_visible(False)


def plot_output(ax, protocols):
    for (label, rows), (color, marker) in zip(protocols, (("#2468a2", "o"), ("#d97716", "s"))):
        seen = {}
        for r in rows:
            if r["output_count"]:
                seen[width_of(r)] = int(r["output_count"])
        widths = sorted(seen)
        ax.plot(widths, [seen[w] for w in widths], f"-{marker}", color=color, markersize=4.5, linewidth=1.3,
                label=label)
    ax.set_yscale("log")
    ax.set_xlabel("transaction width", fontsize=8)
    ax.set_ylabel("Frequent itemsets (log)", fontsize=8)
    ax.set_title("Output volume", fontsize=10)
    ax.legend(frameon=False, fontsize=8)
    ax.grid(axis="y", which="both", alpha=0.18)
    ax.spines[["top", "right"]].set_visible(False)


def read_mine_summary(path):
    """Median and IQR mine-scope seconds per variant and width from a run's summary.csv."""
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = [r for r in csv.DictReader(stream) if r["timing_scope"] == "mine" and r["median_seconds"]]
    if not rows:
        raise SystemExit(f"{path} has no mine-scope rows with a median")
    series = {}
    for r in rows:
        series.setdefault(r["variant"], []).append((width_of(r), float(r["median_seconds"]),
                                                    float(r["iqr_seconds"] or 0)))
    return {name: sorted(points) for name, points in series.items()}


def plot_mine(ax, summary, style):
    for name, points in summary.items():
        color, marker = style.get(name, ("#555555", "P"))
        xs, ys, iqr = zip(*points)
        ax.errorbar(xs, ys, yerr=[[i / 2 for i in iqr], [i / 2 for i in iqr]], fmt=f"-{marker}", color=color,
                    markersize=4.5, capsize=2.5, linewidth=1.3, elinewidth=1.0, label=name)
    ax.set_yscale("log")
    ax.set_xticks(sorted({x for pts in summary.values() for x, _, _ in pts}))
    ax.set_xlabel("transaction width", fontsize=8)
    ax.set_ylabel("Median mine seconds (log)", fontsize=8)
    ax.set_title("Matched output, warm mine scope", fontsize=10)
    ax.legend(frameon=False, fontsize=8)
    ax.grid(axis="y", which="both", alpha=0.18)
    ax.spines[["top", "right"]].set_visible(False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixed", type=Path, help="curves.csv of the fixed-minsup run")
    parser.add_argument("matched", type=Path, help="curves.csv of the matched-output run")
    parser.add_argument("--warm-summary", type=Path,
                        help="summary.csv of a warm matched run, for a fourth panel of mine-scope time")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    fixed, matched = read_points(args.fixed), read_points(args.matched)
    series = list(dict.fromkeys(r["series"] for r in fixed + matched))
    style = assign_styles(series)
    positive = [float(r["median_seconds"]) for r in fixed + matched if r["median_seconds"]]
    floor, ceiling = min(positive) / 1.8, max(positive) * 1.8

    summary = read_mine_summary(args.warm_summary) if args.warm_summary else None
    fig, axes = plt.subplots(1, 4 if summary else 3, figsize=(16.5 if summary else 12.5, 3.8))
    plot_runtime(axes[0], fixed, series, style, "Fixed minsup 0.05")
    plot_runtime(axes[1], matched, series, style, "Matched output, about 5,000 itemsets")
    for ax in axes[:2]:
        ax.set_ylim(floor, ceiling)
        ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:g}"))
    axes[0].set_ylabel("Median seconds (log), IQR bars", fontsize=8)
    plot_output(axes[2], [("fixed minsup 0.05", fixed), ("matched output", matched)])
    handles = [Line2D([], [], color=style[n][0], marker=style[n][1], linewidth=1.3, label=n) for n in series]
    if any(lost(r) for r in fixed + matched):
        handles.append(Line2D([], [], color="#777777", marker="X", markeredgecolor="#a02020", linestyle="none",
                              markersize=9, label="Timeout or lost samples (curves.csv)"))
    if summary:
        plot_mine(axes[3], summary, style)
    axes[1].legend(handles=handles, loc="upper left", frameon=False, fontsize=8)
    fig.tight_layout()
    args.out.mkdir(parents=True, exist_ok=True)
    for suffix in ("png", "svg"):
        fig.savefig(args.out / f"width-curves.{suffix}", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
