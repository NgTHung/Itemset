"""Plot the exact-map coverage and paired peak RSS for the IEEE report."""

import argparse
import csv
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path
from statistics import median
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
        for variant in VARIANTS
        for repeat in range(1, config["repeats"] + 1)
    )
    actual = Counter(map(attempt_key, rows))
    if actual != expected:
        raise ValueError(f"{run}: run does not contain exactly the planned attempts")
    return rows


def apply_retry(rows, retry):
    by_point = {attempt_key(row): row for row in rows}
    for attempt in retry:
        key = attempt_key(attempt)
        original = by_point.get(key)
        if original is None or exact(original) or not exact(attempt):
            raise ValueError(f"Retry must verify a failed point: {attempt['attempt_id']}")
        fields = ("input_sha256", "minsup_count", "code_revision", "mode", "threads", "julia_version", "cpu", "os")
        if any(original[field] != attempt[field] for field in fields):
            raise ValueError(f"Retry changed the comparison inputs: {attempt['attempt_id']}")
        by_point[key] = attempt
    return list(by_point.values())


def require_exact(rows):
    references = defaultdict(set)
    for row in rows:
        if not exact(row):
            raise ValueError(f"Nonmatching attempt: {row['attempt_id']}")
        references[row["dataset"], row["minsup_count"]].add(row["comparison_reference_sha256"])
    if any(len(digests) != 1 or "" in digests for digests in references.values()):
        raise ValueError("Expected one SPMF reference per dataset and count threshold")


def plot_coverage(rows, destination):
    thresholds = defaultdict(set)
    for row in rows:
        thresholds[row["dataset"]].add(Decimal(row["minsup_relative"]))
    dataset_order = [name for name in DATASETS if name in thresholds]
    columns = max(map(len, thresholds.values()))
    fig, ax = plt.subplots(figsize=(4.4, 1.95), layout="constrained")
    ax.set_yticks(range(len(dataset_order)), [DATASETS[name] for name in dataset_order])
    ax.set_xticks(range(columns), range(1, columns + 1))
    ax.set_xlabel("Thứ tự ngưỡng trong lưới")
    ax.set_ylim(len(dataset_order) - 0.5, -0.5)
    ax.set_xlim(-0.5, columns - 0.5)
    for index, name in enumerate(dataset_order):
        values = sorted(thresholds[name], reverse=True)
        ax.barh(index, len(values) - 0.12, left=-0.44, height=0.76, color="#176681")
        for column, value in enumerate(values):
            percent = format((value * 100).normalize(), "f").replace(".", ",")
            ax.text(column, index, percent, color="white", ha="center", va="center", fontsize=9)
        for column in range(len(values) - 1):
            ax.vlines(column + 0.5, index - 0.38, index + 0.38, color="white", linewidth=0.8)
    ax.tick_params(length=0)
    for spine in ax.spines.values():
        spine.set_visible(False)
    fig.savefig(destination)
    plt.close(fig)


def plot_memory(rows, destination):
    samples = defaultdict(list)
    points = defaultdict(set)
    for row in rows:
        peak = int(row["peak_rss_bytes"])
        if peak <= 0:
            raise ValueError(f"Invalid peak RSS for {row['attempt_id']}")
        samples[row["dataset"], row["variant"]].append(peak / 2**20)
        points[row["dataset"]].add((row["minsup_count"], row["memory_tool"]))
    if any(len(values) != 1 for values in points.values()):
        raise ValueError("Expected one consistent peak RSS measurement point per dataset")
    names = [name for name in DATASETS if (name, "baseline") in samples]
    fig, (left, right) = plt.subplots(1, 2, figsize=(8.0, 2.5), layout="constrained")
    medians = {}
    for variant, label, color, offset in (
        ("baseline", "Cơ bản", "#176681", -0.19),
        ("optimized", "Tối ưu", "#ad552e", 0.19),
    ):
        data = [samples[name, variant] for name in names]
        values = [median(peaks) for peaks in data]
        medians[variant] = values
        ranges = [
            [mid - min(peaks) for mid, peaks in zip(values, data)],
            [max(peaks) - mid for mid, peaks in zip(values, data)],
        ]
        left.barh([i + offset for i in range(len(names))], values, xerr=ranges,
                  height=0.31, color=color, label=label, error_kw={"capsize": 2, "elinewidth": 0.8})
    left.legend(loc="upper right", frameon=False, fontsize=9)
    left.set_xlabel("Trung vị peak RSS (MiB)")
    ratios = [a / b for a, b in zip(medians["baseline"], medians["optimized"])]
    right.barh(range(len(names)), ratios, color="#426779", height=0.57)
    right.axvline(1, color="#313131", linestyle=":", linewidth=1)
    right.set_xlabel("Trung vị cơ bản / tối ưu")
    for ax in (left, right):
        ax.set_yticks(range(len(names)), [DATASETS[name] for name in names])
        ax.invert_yaxis()
        ax.spines[["top", "right"]].set_visible(False)
    fig.savefig(destination, dpi=200)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("correctness", type=Path, help="report-correctness run directory")
    parser.add_argument("memory", type=Path, help="report-peak-memory run directory")
    parser.add_argument("--correctness-retry", type=Path, help="retry of failed correctness points")
    parser.add_argument("--memory-retry", type=Path, help="retry of failed memory points")
    parser.add_argument("--out", type=Path, default=Path("docs/report/figures"))
    args = parser.parse_args()
    exact_rows = read_process_rows(args.correctness)
    if args.correctness_retry:
        exact_rows = apply_retry(exact_rows, read_process_rows(args.correctness_retry))
    memory_rows = read_process_rows(args.memory)
    if args.memory_retry:
        memory_rows = apply_retry(memory_rows, read_process_rows(args.memory_retry))
    require_exact(exact_rows)
    require_exact(memory_rows)
    args.out.mkdir(parents=True, exist_ok=True)
    plot_coverage(exact_rows, args.out / "correctness-grid.pdf")
    plot_memory(memory_rows, args.out / "peak-memory.png")


if __name__ == "__main__":
    main()
