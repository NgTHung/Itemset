"""Plot exact-map timing samples with median and IQR, retaining failure counts."""

import argparse
import csv
import html
import importlib.metadata
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
matplotlib.rcParams["svg.fonttype"] = "none"
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--mode", choices=("cold", "warm"), default="cold")
    parser.add_argument("--scope", default="process")
    args = parser.parse_args()
    with (args.run / "runs.csv").open(newline="", encoding="utf-8-sig") as source:
        rows = [r for r in csv.DictReader(source)
                if r["mode"] == args.mode and r["timing_scope"] == args.scope]
    if not rows:
        parser.error("no rows match the requested mode and timing scope")
    with (args.run / "summary.csv").open(newline="", encoding="utf-8-sig") as source:
        summaries = {(r["dataset"], r["minsup_count"], r["variant"], r["stage"], r["mode"], r["timing_scope"]): r
                     for r in csv.DictReader(source)}
    groups = defaultdict(list)
    points = []
    variants = []
    for row in rows:
        point = (row["dataset"], row["minsup_count"])
        if point not in points:
            points.append(point)
        if row["variant"] not in variants:
            variants.append(row["variant"])
        groups[point, row["variant"]].append(row)
    records = []
    for point in points:
        for variant in variants:
            samples = groups[point, variant]
            exact = [r for r in samples if r["status"] == "ok" and r["correctness_status"] == "exact"]
            times = [float(r["elapsed_seconds"]) for r in exact]
            quartiles = statistics.quantiles(times, n=4, method="inclusive") if len(times) > 1 else times * 3
            record = dict(dataset=point[0], minsup_count=point[1], variant=variant,
                          minsup_relative=samples[0]["minsup_relative"],
                          output_count=exact[0]["output_count"] if exact else "",
                          exact_samples=len(exact), total_samples=len(samples),
                          invalid_samples=len(samples) - len(exact),
                          median_seconds=statistics.median(times) if times else "",
                          q1_seconds=quartiles[0] if times else "",
                          q3_seconds=quartiles[2] if times else "",
                          max_peak_rss_bytes=max((int(r["peak_rss_bytes"]) for r in exact
                                                 if r["peak_rss_bytes"]), default=""))
            summary = summaries[point[0], point[1], variant, samples[0]["stage"], args.mode, args.scope]
            if times:
                assert math.isclose(record["median_seconds"], float(summary["median_seconds"]), rel_tol=1e-12)
                assert math.isclose(quartiles[2] - quartiles[0], float(summary["iqr_seconds"]), abs_tol=1e-12)
            assert len(exact) == int(summary["successful_samples"])
            records.append(record)
    args.out.mkdir(parents=True, exist_ok=True)
    with (args.out / "process-summary.csv").open("w", newline="", encoding="utf-8") as target:
        writer = csv.DictWriter(target, fieldnames=records[0].keys())
        writer.writeheader()
        writer.writerows(records)

    fig, ax = plt.subplots(figsize=(9.2, max(4.0, len(points) * 0.59)))
    colors = {"baseline": "#2468a2", "optimized": "#8c4fa1", "spmf": "#d97716", "prepost": "#25814a"}
    names = {"baseline": "Julia baseline", "optimized": "Julia optimized",
             "spmf": "SPMF Eclat", "prepost": "SPMF PrePost+"}
    labels = []
    positive_times = [r["median_seconds"] for r in records if r["median_seconds"] != ""]
    if not positive_times:
        parser.error("no exact successful samples to plot; see the retained failure rows")
    for point_index, point in enumerate(points):
        matching = [r for r in records if (r["dataset"], r["minsup_count"]) == point]
        labels.append(f"{point[0]} / {matching[0]['minsup_relative']}")
        for variant_index, record in enumerate(matching):
            offset = (variant_index - (len(variants) - 1) / 2) * 0.20
            y = point_index + offset
            median = record["median_seconds"]
            if median != "":
                ax.errorbar(median, y, xerr=[[median - record["q1_seconds"]],
                                            [record["q3_seconds"] - median]],
                            fmt={"baseline": "o", "optimized": "D", "spmf": "s", "prepost": "^"}.get(record["variant"], "o"),
                            markersize=4.5, capsize=3, linewidth=1.2,
                            color=colors.get(record["variant"], "#555555"),
                            label=names.get(record["variant"], record["variant"]) if point_index == 0 else None)
            if record["invalid_samples"]:
                ax.text(max(positive_times) * 1.15, y,
                        f"{record['variant']}: {record['invalid_samples']}/{record['total_samples']} invalid",
                        fontsize=7, va="center", color="#a02020")
    ax.set_xscale("log")
    ax.xaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:g}"))
    ax.set_yticks(range(len(points)), labels)
    ax.invert_yaxis()
    ax.set_xlabel(f"{args.mode.capitalize()} {args.scope} seconds (log scale), median and IQR")
    ax.grid(axis="x", which="both", alpha=0.18)
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, 1.09), ncol=len(variants), frameon=False, fontsize=9)
    fig.tight_layout()
    for suffix in ("png", "svg"):
        fig.savefig(args.out / f"timings.{suffix}", dpi=300, bbox_inches="tight")
    plt.close(fig)

    verified = sum(r["exact_samples"] for r in records)
    total = sum(r["total_samples"] for r in records)
    svg = (args.out / "timings.svg").read_text(encoding="utf-8")
    svg = svg[svg.index("<svg"):]
    cells = "".join("<tr>" + "".join(f"<td>{html.escape(str(r[k]))}</td>" for k in
                    ("dataset", "minsup_relative", "variant", "median_seconds", "exact_samples", "invalid_samples"))
                    + "</tr>" for r in records)
    page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
    svg{{width:100%;height:500px}}p{{color:var(--muted-foreground)}}
    details{{margin-top:12px}}.table{{overflow-x:auto}}table{{border-collapse:collapse;font-size:12px}}
    th,td{{padding:6px 10px;text-align:left;border-bottom:1px solid var(--border)}}
    </style></head><body>{svg}
    <p>{verified}/{total} attempts produced outputs matching separate SPMF Eclat maps exactly.
    Development samples do not establish the five-repeat scored gate.
    Source: {html.escape(args.run.name)}.</p><details><summary>Timing data and failures</summary><div class="table">
    <table><thead><tr><th>Dataset</th><th>Minsup</th><th>Variant</th><th>Median s</th><th>Exact</th><th>Invalid</th>
    </tr></thead><tbody>{cells}</tbody></table></div></details></body></html>"""
    (args.out / "timings.html").write_text(page, encoding="utf-8")
    metadata = dict(python=sys.version, source=str(args.run.resolve()), scope=args.scope, mode=args.mode,
                    packages={d.metadata["Name"]: d.version for d in importlib.metadata.distributions()},
                    independent_summary_checks=len(records), exact_outputs=verified, total_outputs=total)
    (args.out / "plot-environment.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"{verified}/{total} exact outputs; wrote {args.out}")


if __name__ == "__main__":
    main()
