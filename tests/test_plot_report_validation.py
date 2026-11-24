"""Check which benchmark results can enter the report figures."""

import csv
from pathlib import Path
import sys
import tempfile
from unittest import TestCase

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import plot_report_validation as report


def result(variant="baseline", **overrides):
    row = dict(attempt_id=f"chess-{variant}", dataset="chess", minsup_relative="0.80",
               minsup_count="16", variant=variant, repeat="1", timing_scope="process",
               status="ok", correctness_status="exact", match_rate="1.0",
               comparison_reference_sha256="ref", peak_rss_bytes="1000000", memory_tool="rss")
    return row | overrides


class ReportValidationTest(TestCase):
    def test_reads_config_variants_and_equivalent_decimal_thresholds(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            (run / "config.toml").write_text(
                'variants = ["baseline"]\nrepeats = 1\n[[series]]\ndataset = "chess"\nminsup = [0.8]\n',
                encoding="utf-8",
            )
            row = result()
            with (run / "runs.csv").open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=row)
                writer.writeheader()
                writer.writerow(row)
            self.assertEqual(report.read_process_rows(run), [row])

    def test_rejects_unverified_results_and_inconsistent_references(self):
        baseline = result()
        with self.assertRaisesRegex(ValueError, "Nonmatching attempt: chess-optimized"):
            report.require_exact([baseline, result("optimized", correctness_status="unverified")])
        with self.assertRaisesRegex(ValueError, "one SPMF reference"):
            report.require_exact([baseline, result("optimized", comparison_reference_sha256="different")])
        report.require_exact([baseline, result("optimized")])

    def test_names_attempt_when_peak_rss_is_missing(self):
        row = result(peak_rss_bytes="")
        with self.assertRaisesRegex(ValueError, "Invalid peak RSS for chess-baseline"):
            report.plot_memory([row], Path("unused.png"))

    def test_does_not_plot_unpaired_coverage(self):
        with self.assertRaisesRegex(ValueError, "both Julia variants"):
            report.plot_coverage([result()], Path("unused.pdf"))
