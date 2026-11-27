"""Checks for scripts/plot_runtime_curves.py.

Run from the repository root with the plotting environment:
    uv run --no-project --python 3.12 --with matplotlib==3.10.7 python -m unittest tests/test_plot_runtime_curves.py
"""

import csv
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))

import plot_runtime_curves as plot

HEADER = ["dataset", "minsup_relative", "minsup_count", "series", "output_count", "exact_samples",
          "total_samples", "timeouts", "correctness_failures", "unverified", "interrupted",
          "other_incomplete", "median_seconds", "q1_seconds", "q3_seconds"]


def point(minsup, samples, median, q1=None, q3=None, series="Optimized"):
    q1 = median if q1 is None else q1
    q3 = median if q3 is None else q3
    return dict(zip(HEADER, ["chess", str(minsup), "100", series, "50", str(samples), str(samples),
                             "0", "0", "0", "0", "0", str(median), str(q1), str(q3)]))


class YLabelTest(unittest.TestCase):
    def test_one_sample_per_point_has_no_bars_to_describe(self):
        label = plot.ylabel([point(0.9, 1, 0.2), point(0.8, 1, 0.3)])
        self.assertNotIn("IQR", label)
        self.assertIn("one sample", label)

    def test_repeated_samples_describe_the_bars(self):
        label = plot.ylabel([point(0.9, 3, 0.2, 0.19, 0.22), point(0.8, 3, 0.3, 0.28, 0.31)])
        self.assertIn("IQR bars", label)

    def test_a_mix_names_where_the_bars_exist(self):
        label = plot.ylabel([point(0.9, 1, 0.2), point(0.8, 3, 0.3, 0.28, 0.31)])
        self.assertIn("IQR", label)
        self.assertIn("2 or more", label)

    def test_a_point_without_a_time_is_ignored(self):
        lost = point(0.7, 0, "", "", "")
        self.assertIn("one sample", plot.ylabel([point(0.9, 1, 0.2), lost]))


class FigureTest(unittest.TestCase):
    def run_main(self, rows):
        with tempfile.TemporaryDirectory() as tmp:
            curves = Path(tmp) / "curves.csv"
            with curves.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=HEADER)
                writer.writeheader()
                writer.writerows(rows)
            out = Path(tmp) / "figure"
            argv = sys.argv
            sys.argv = ["plot_runtime_curves.py", str(curves), "--out", str(out)]
            try:
                plot.main()
            finally:
                sys.argv = argv
            self.assertTrue((out / "runtime-curves.png").stat().st_size > 0)
            return (out / "runtime-curves.svg").read_text(encoding="utf-8")

    def test_single_sample_figure_does_not_claim_bars(self):
        svg = self.run_main([point(0.9, 1, 0.2), point(0.8, 1, 0.4)])
        self.assertIn("one sample", svg)
        self.assertNotIn("IQR", svg)

    def test_repeated_sample_figure_keeps_the_bars_label(self):
        svg = self.run_main([point(0.9, 3, 0.2, 0.19, 0.22), point(0.8, 3, 0.4, 0.38, 0.45)])
        self.assertIn("IQR bars", svg)


if __name__ == "__main__":
    unittest.main()
