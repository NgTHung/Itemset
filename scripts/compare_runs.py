"""Plot one process series from each of several runs with median and IQR on a shared log axis."""

import argparse
import csv
import statistics
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["svg.fonttype"] = "none"
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

STYLES = (("#2468a2", "o"), ("#d97716", "s"), ("#25814a", "^"))


def read_series(spec):
    """Return {(dataset, minsup): samples} for a `LABEL=RUN:VARIANT[@STAGE]` spec, refusing inexact samples."""
    label, source = spec.split("=", 1)
    run, variant = source.rsplit(":", 1)
    variant, _, stage = variant.partition("@")
    samples = {}
    stages = set()
    with (Path(run) / "runs.csv").open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            if row["timing_scope"] == "process" and row["variant"] == variant and stage in ("", row["stage"]):
                stages.add(row["stage"])
                # A comparison figure has no place to show a failure, so a failed sample stops it.
                if row["status"] != "ok" or row["correctness_status"] != "exact":
                    raise SystemExit(f"{row['attempt_id']} in {run} is {row['status']}/{row['correctness_status']}")
                samples.setdefault((row["dataset"], row["minsup_relative"]), []).append(float(row["elapsed_seconds"]))
    if len(stages) > 1:
        raise SystemExit(f"{variant} in {run} has stages {sorted(stages)}; name one as {variant}@STAGE")
    if not samples:
        raise SystemExit(f"{run} has no process rows for {variant}{'@' + stage if stage else ''}")
    return label, samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("series", nargs="+", help="LABEL=RUN_DIR:VARIANT[@STAGE], at most three")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if len(args.series) > len(STYLES):
        parser.error(f"at most {len(STYLES)} series")
    series = [read_series(spec) for spec in args.series]
    points = list(series[0][1])
    for label, samples in series:
        if set(samples) != set(points):
            parser.error(f"{label} covers different points from {series[0][0]}")
    args.out.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(9.2, max(4.0, len(points) * 0.36)))
    with (args.out / "comparison.csv").open("w", newline="", encoding="utf-8") as target:
        writer = csv.writer(target)
        writer.writerow(("dataset", "minsup", "series", "samples", "median_seconds", "q1_seconds", "q3_seconds"))
        for index, (label, samples) in enumerate(series):
            color, marker = STYLES[index]
            for y, point in enumerate(points):
                times = samples[point]
                q1, median, q3 = statistics.quantiles(times, n=4, method="inclusive")
                writer.writerow((*point, label, len(times), median, q1, q3))
                ax.errorbar(median, y + (index - (len(series) - 1) / 2) * 0.22, xerr=[[median - q1], [q3 - median]],
                            fmt=marker, markersize=4.5, capsize=3, linewidth=1.2, color=color,
                            label=label if y == 0 else None)
    ax.set_xscale("log")
    ax.xaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:g}"))
    ax.set_yticks(range(len(points)), [f"{dataset} / {minsup}" for dataset, minsup in points])
    ax.invert_yaxis()
    ax.set_xlabel("Cold process seconds (log scale), median and IQR")
    ax.grid(axis="x", which="both", alpha=0.18)
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(loc="lower center", bbox_to_anchor=(0.5, 1.0), ncol=len(series), frameon=False, fontsize=9)
    fig.tight_layout()
    for suffix in ("png", "svg"):
        fig.savefig(args.out / f"comparison.{suffix}", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
