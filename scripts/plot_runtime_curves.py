"""Plot runtime against minsup, one panel per dataset, from the curves.csv that runtime_curves.jl writes."""

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["svg.fonttype"] = "none"
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

# Same colors and markers as report_measurements.py. A series takes the style of the contender its
# label names, so a figure with two contenders colors them as one with four; other labels take
# the spare styles in order.
KNOWN = (("baseline", ("#2468a2", "o")), ("optimized", ("#8c4fa1", "D")),
         ("eclat", ("#d97716", "s")), ("prepost", ("#25814a", "^")))
SPARE = (("#b0384b", "v"), ("#555555", "P"), ("#8a6200", "X"), ("#1a8a8a", "<"))


def assign_styles(series):
    """Map each label to a (color, marker), keeping the known contenders' colors and never reusing one."""
    styles, taken, spare = {}, set(), iter(SPARE)
    for name in series:
        for keyword, style in KNOWN:
            if keyword in name.lower() and style not in taken:
                styles[name] = style
                taken.add(style)
                break
    for name in series:
        if name not in styles:
            styles[name] = next(spare)
    return styles
REQUIRED = ("dataset", "minsup_relative", "minsup_count", "series", "output_count", "exact_samples",
            "total_samples", "timeouts", "correctness_failures", "unverified", "interrupted",
            "other_incomplete", "median_seconds", "q1_seconds", "q3_seconds")


def read_points(path):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit(f"{path} lacks the columns {', '.join(missing)}")
        rows = list(reader)
    if not rows:
        raise SystemExit(f"{path} has no rows")
    return rows


def lost(row):
    return any(int(row[k]) for k in ("timeouts", "correctness_failures", "unverified", "interrupted",
                                    "other_incomplete"))


def compact(count):
    """An itemset count in three digits, so the labels under neighboring thresholds do not overlap."""
    count = int(count)
    if count < 1000:
        return str(count)
    if count < 1_000_000:
        return f"{count / 1000:.3g}k"
    return f"{count / 1_000_000:.3g}M"


def use_log_x(minsups):
    """A threshold range wider than a factor of five is easier to read on a log axis."""
    return max(minsups) / min(minsups) > 5


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("curves", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--columns", type=int, default=3)
    args = parser.parse_args()
    rows = read_points(args.curves)
    series = list(dict.fromkeys(r["series"] for r in rows))
    if len(series) > len(KNOWN) + len(SPARE):
        parser.error(f"at most {len(KNOWN) + len(SPARE)} series")
    style = assign_styles(series)
    datasets = list(dict.fromkeys(r["dataset"] for r in rows))
    by_dataset = defaultdict(lambda: defaultdict(list))
    for row in rows:
        by_dataset[row["dataset"]][row["series"]].append(row)

    columns = min(args.columns, len(datasets) + 1)
    grid_rows = math.ceil((len(datasets) + 1) / columns)
    fig, axes = plt.subplots(grid_rows, columns, figsize=(4.0 * columns, 3.5 * grid_rows), squeeze=False)
    flat = list(axes.flat)
    any_lost = False
    positive = [float(r["median_seconds"]) for r in rows if r["median_seconds"]]
    floor, ceiling = min(positive) / 1.8, max(positive) * 1.8
    for ax, dataset in zip(flat, datasets):
        points = by_dataset[dataset]
        minsups = sorted({float(r["minsup_relative"]) for rs in points.values() for r in rs}, reverse=True)
        counts = {float(r["minsup_relative"]): r["output_count"] for rs in points.values() for r in rs
                  if r["output_count"]}
        ax.set_yscale("log")
        ax.set_ylim(floor, ceiling)
        if use_log_x(minsups):
            ax.set_xscale("log")
        ax.set_xlim(minsups[0] * (1.12 if use_log_x(minsups) else 1.0 + 0.04 * (minsups[0] - minsups[-1]) / minsups[0]),
                    minsups[-1] / (1.12 if use_log_x(minsups) else 1.0 + 0.04 * (minsups[0] - minsups[-1]) / minsups[-1]))
        for name in series:
            color, marker = style[name]
            samples = sorted(points.get(name, []), key=lambda r: -float(r["minsup_relative"]))
            timed = [r for r in samples if r["median_seconds"]]
            xs = [float(r["minsup_relative"]) for r in timed]
            ys = [float(r["median_seconds"]) for r in timed]
            lower = [y - float(r["q1_seconds"]) for y, r in zip(ys, timed)]
            upper = [float(r["q3_seconds"]) - y for y, r in zip(ys, timed)]
            ax.errorbar(xs, ys, yerr=[lower, upper], fmt=f"-{marker}", color=color, markersize=4.5,
                        capsize=2.5, linewidth=1.3, elinewidth=1.0)
            for r in samples:
                if lost(r):
                    any_lost = True
                    ax.plot([float(r["minsup_relative"])], [1], marker="X", color=color, markersize=9,
                            markeredgecolor="#a02020", markeredgewidth=1.2, linestyle="none", clip_on=False,
                            transform=ax.get_xaxis_transform())
        ax.set_xticks(minsups, [f"{m:g}\n{compact(counts[m])}" if m in counts else f"{m:g}" for m in minsups],
                      fontsize=6.5)
        ax.minorticks_off()
        ax.set_title(dataset, fontsize=10)
        ax.set_xlabel("minsup, with frequent itemsets below", fontsize=7.5)
        ax.grid(axis="y", which="both", alpha=0.18)
        ax.spines[["top", "right"]].set_visible(False)
    for ax in flat[:len(datasets)]:
        ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:g}"))
    for ax in flat[0::columns]:
        ax.set_ylabel("Median seconds (log), IQR bars", fontsize=8)

    legend_ax = flat[len(datasets)]
    legend_ax.axis("off")
    handles = [Line2D([], [], color=style[n][0], marker=style[n][1], linewidth=1.3, label=n) for n in series]
    if any_lost:
        handles.append(Line2D([], [], color="#777777", marker="X", markeredgecolor="#a02020", linestyle="none",
                              markersize=9, label="Timeout or lost samples (curves.csv)"))
    legend_ax.legend(handles=handles, loc="center", frameon=False, fontsize=9)
    for ax in flat[len(datasets) + 1:]:
        ax.axis("off")
    fig.tight_layout()
    args.out.mkdir(parents=True, exist_ok=True)
    for suffix in ("png", "svg"):
        fig.savefig(args.out / f"runtime-curves.{suffix}", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
