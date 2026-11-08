"""Summarize complete-map coverage and paired process-memory measurements."""

import argparse
import csv
import statistics
import tomllib
from collections import defaultdict
from pathlib import Path


def read_process_rows(run):
    with (run / "runs.csv").open(newline="", encoding="utf-8-sig") as stream:
        return [row for row in csv.DictReader(stream) if row["timing_scope"] == "process"]


def write_table(path, header, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def correctness_rows(run):
    config = tomllib.loads((run / "config.toml").read_text(encoding="utf-8"))
    attempts = {}
    for row in read_process_rows(run):
        key = (row["dataset"], float(row["minsup_relative"]), row["variant"])
        if key in attempts:
            raise ValueError(f"expected one correctness attempt per point: {key}")
        attempts[key] = row
    for series in config["series"]:
        dataset = series["dataset"]
        for minsup in series["minsup"]:
            for variant in config["variants"]:
                row = attempts.get((dataset, minsup, variant))
                if row is None:
                    yield (dataset, minsup, "", variant, "not_run", *("",) * 12)
                    continue
                candidate_dir = run / "attempts" / row["attempt_id"]
                diff_path = candidate_dir / "comparison.toml"
                diff = tomllib.loads(diff_path.read_text(encoding="utf-8")) if diff_path.is_file() else {}
                reference = run / "references" / f"{dataset}-c{row['minsup_count']}" / "output.txt"
                rate = diff.get("match_rate")
                reference_count = ""
                if rate is not None:
                    with reference.open("rb") as stream:
                        reference_count = sum(b"#SUP:" in line for line in stream)
                union = reference_count + diff["extra"] if rate is not None else ""
                exact_count = round(rate * union) if rate is not None else ""
                status = "exact" if row["status"] == "ok" and diff.get("matches") else (
                    "mismatch" if rate is not None else row["status"] if row["status"] != "ok" else "unverified")
                yield (dataset, minsup, row["minsup_count"], variant, status, reference_count,
                       row["output_count"], exact_count, union, rate if rate is not None else "",
                       *(diff.get(field, "") for field in ("missing", "extra", "reference_duplicates",
                                                           "candidate_duplicates", "support_mismatches")),
                       row["attempt_id"], row["error"])


def memory_rows(run):
    config = tomllib.loads((run / "config.toml").read_text(encoding="utf-8"))
    planned_repeats = config["repeats"]
    points = defaultdict(lambda: defaultdict(dict))
    for row in read_process_rows(run):
        point = (row["dataset"], row["minsup_relative"], row["minsup_count"], row["input_sha256"])
        variants = points[point][row["repeat"]]
        if row["variant"] in variants:
            raise ValueError(f"duplicate memory attempt: {row['attempt_id']}")
        variants[row["variant"]] = row
    for (dataset, fraction, count, _), repeats in points.items():
        samples = []
        for pair in repeats.values():
            if not {"baseline", "optimized"} <= pair.keys():
                continue
            baseline, optimized = pair["baseline"], pair["optimized"]
            if not all(r["status"] == "ok" and r["correctness_status"] == "exact"
                       and r["peak_rss_bytes"] for r in (baseline, optimized)):
                continue
            if not baseline["memory_tool"] or not all(baseline[field] == optimized[field] for field in (
                    "comparison_reference_sha256", "memory_tool", "threads", "mode")):
                raise ValueError(f"incompatible memory pair: {dataset} at {fraction}")
            peaks = tuple(int(r["peak_rss_bytes"]) for r in (baseline, optimized))
            if min(peaks) <= 0:
                raise ValueError(f"invalid process RSS: {dataset} at {fraction}")
            samples.append(peaks)
        if not samples:
            yield (dataset, fraction, count, 0, planned_repeats, *("",) * 7)
            continue
        a, b = zip(*samples)
        ma, mb = statistics.median(a), statistics.median(b)
        yield (dataset, fraction, count, len(samples), planned_repeats, ma, mb,
               min(a), max(a), min(b), max(b), ma / mb)


def plot_memory(rows, path):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    valid = [r for r in rows if r[3] and r[3] == r[4]]
    if not valid:
        raise ValueError("no complete matched memory groups to plot")
    fig, (left, right) = plt.subplots(1, 2, figsize=(8.4, 3.0), layout="constrained")
    labels = [r[0] for r in valid]
    for offset, column, name, color in ((-0.18, 5, "Baseline", "#2166ac"),
                                         (0.18, 6, "Optimized", "#b35806")):
        left.barh([i + offset for i in range(len(valid))], [r[column] / 2**20 for r in valid],
                  height=0.32, label=name, color=color)
    left.set_yticks(range(len(valid)), labels)
    left.set_xlabel("Median peak RSS (MiB)")
    left.legend(frameon=False)
    right.barh(range(len(valid)), [r[-1] for r in valid], height=0.56, color="#4d4d4d")
    right.axvline(1, color="#666666", linestyle=":")
    right.set_yticks(range(len(valid)), labels)
    right.set_xlabel("Baseline / optimized median RSS")
    for ax in (left, right):
        ax.invert_yaxis()
    fig.savefig(path)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("correctness", "memory"))
    parser.add_argument("run", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--figure", type=Path)
    args = parser.parse_args()
    if args.kind == "correctness":
        write_table(args.out, ("dataset", "minsup", "min_count", "variant", "status", "reference_itemsets",
                    "candidate_itemsets", "exact_itemsets", "union_itemsets", "match_rate", "missing", "extra",
                    "reference_duplicates", "candidate_duplicates", "support_mismatches", "attempt", "error"),
                    correctness_rows(args.run))
    else:
        rows = list(memory_rows(args.run))
        write_table(args.out, ("dataset", "minsup", "min_count", "exact_pairs", "planned_repeats",
                    "baseline_median_bytes", "optimized_median_bytes", "baseline_min_bytes", "baseline_max_bytes",
                    "optimized_min_bytes", "optimized_max_bytes", "baseline_to_optimized"), rows)
        if args.figure:
            plot_memory(rows, args.figure)


if __name__ == "__main__":
    main()
