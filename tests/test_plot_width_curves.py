"""Checks for scripts/plot_width_curves.py.

Run from the repository root with the plotting environment:
    uv run --no-project --python 3.12 --with matplotlib==3.10.7 python -m unittest tests/test_plot_width_curves.py
"""

import csv
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

import matplotlib.pyplot as plt

import plot_width_curves as plot

HEADER = ["dataset", "minsup_count", "variant", "stage", "mode", "timing_scope", "successful_samples",
          "failed_samples", "unverified_samples", "median_seconds", "iqr_seconds", "samples_seconds",
          "max_peak_rss_bytes", "median_allocated_bytes", "median_gc_seconds", "gate_eligible"]


def summary_row(width, variant, samples, median, iqr, scope="mine"):
    return dict(zip(HEADER, [f"width-w{width:02d}", "10", variant, "width", "warm", scope,
                             str(len(samples.split(";")) if samples else 0), "0", "0", str(median), str(iqr),
                             samples, "1", "1", "0", "false"]))


def write_summary(path, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=HEADER)
        writer.writeheader()
        writer.writerows(rows)


class MineSummaryTest(unittest.TestCase):
    def read(self, rows):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "summary.csv"
            write_summary(path, rows)
            return plot.read_mine_summary(path)

    def test_offsets_reach_the_interpolated_quartiles(self):
        # Quartiles of [1, 2, 10] are 1.5 and 6.0 around a median of 2, so the bar is not symmetric.
        series = self.read([summary_row(5, "baseline", "1;2;10", 2.0, 4.5)])
        (width, median, lower, upper), = series["baseline"]
        self.assertEqual(width, 5)
        self.assertAlmostEqual(median - lower, 1.5)
        self.assertAlmostEqual(median + upper, 6.0)

    def test_quartiles_follow_the_harness_interpolation_on_a_recorded_row(self):
        # A row from a recorded warm run: summary.csv stores iqr_seconds as q3 - q1.
        samples = "0.0697577;0.0723522;0.0738871"
        series = self.read([summary_row(5, "baseline", samples, 0.0723522, 0.0020647000000000026)])
        (_, median, lower, upper), = series["baseline"]
        self.assertAlmostEqual(lower + upper, 0.0020647, places=12)
        # The median sits nearer the third sample, so Q1 is farther below it than Q3 is above it.
        self.assertAlmostEqual(lower, 0.00129725, places=12)
        self.assertAlmostEqual(upper, 0.00076745, places=12)

    def test_one_sample_has_no_bar(self):
        series = self.read([summary_row(5, "optimized", "0.25", 0.25, 0.0)])
        (_, _, lower, upper), = series["optimized"]
        self.assertEqual((lower, upper), (0.0, 0.0))

    def test_samples_are_sorted_before_the_quartiles(self):
        series = self.read([summary_row(5, "baseline", "10;1;2", 2.0, 4.5)])
        (_, median, lower, upper), = series["baseline"]
        self.assertAlmostEqual(median - lower, 1.5)
        self.assertAlmostEqual(median + upper, 6.0)

    def test_a_median_without_samples_is_an_error_not_a_zero_bar(self):
        with self.assertRaises(SystemExit):
            self.read([summary_row(5, "baseline", "", 2.0, 4.5)])

    def test_rows_of_other_scopes_are_ignored(self):
        rows = [summary_row(5, "baseline", "1;2;10", 2.0, 4.5), summary_row(5, "baseline", "9;9;9", 9.0, 0.0, "process")]
        self.assertEqual(len(self.read(rows)["baseline"]), 1)


class PlotMineTest(unittest.TestCase):
    def test_drawn_bar_ends_are_the_quartiles(self):
        summary = {"baseline": [(5, 2.0, 0.5, 4.0)]}
        fig, ax = plt.subplots()
        plot.plot_mine(ax, summary, {"baseline": ("#2468a2", "o")})
        bars = ax.containers[0].lines[2][0]
        (segment,) = bars.get_segments()
        ends = sorted(float(y) for _, y in segment)
        self.assertAlmostEqual(ends[0], 1.5)
        self.assertAlmostEqual(ends[1], 6.0)
        plt.close(fig)


if __name__ == "__main__":
    unittest.main()
