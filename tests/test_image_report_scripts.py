"""Check comparison summaries and provenance checks for image figures."""

import csv
import hashlib
from pathlib import Path
import sys
import tempfile
from unittest import TestCase
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import plot_image_evidence as plot
import summarize_validation as summary


class ComparisonSummaryTest(TestCase):
    def test_reference_duplicates_do_not_inflate_union_or_matches(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            (run / "config.toml").write_text(
                'variants = ["baseline"]\n[[series]]\ndataset = "toy"\nminsup = [0.5]\n', encoding="utf-8"
            )
            with (run / "runs.csv").open("w", newline="", encoding="utf-8") as stream:
                row = dict(dataset="toy", minsup_relative="0.5", minsup_count="2", variant="baseline",
                           timing_scope="process", status="error", output_count="2", attempt_id="one", error="")
                writer = csv.DictWriter(stream, fieldnames=row)
                writer.writeheader()
                writer.writerow(row)
            (run / "attempts/one").mkdir(parents=True)
            (run / "attempts/one/comparison.toml").write_text(
                "matches = false\nmatch_rate = 0.5\nextra = 0\nmissing = 0\nreference_duplicates = 1\n"
                "candidate_duplicates = 0\nsupport_mismatches = 0\n", encoding="utf-8"
            )
            (run / "references/toy-c2").mkdir(parents=True)
            (run / "references/toy-c2/output.txt").write_text(
                "@ITEM=1=word\n1 2 #SUP: 2\n2 1 #SUP: 2\n3 #SUP: 2\n", encoding="utf-8"
            )
            row, = summary.correctness_rows(run)
            self.assertEqual(row[4:10], ("mismatch", 2, "2", 1, 2, 0.5))


class ImagePlotTest(TestCase):
    def test_draws_verified_pixels_and_detects_altered_patch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "semeion.data", root / "contrast.png"
            line = " ".join(["0"] * 256 + ["1"] + ["0"] * 9)
            data = f"{line}\n{line}\n".encode()
            source.write_bytes(data)
            (root / "mining_manifest.toml").write_text(
                f'source_sha256 = "{hashlib.sha256(data).hexdigest()}"\n', encoding="utf-8"
            )
            (root / "examples.tsv").write_text(
                "image_id\tminsup\titems\tlabel\tpresent_words\tmissing_words\n"
                "1\t0.05\t1\t0\t1\t\n2\t0.05\t1\t0\t\t1\n", encoding="utf-8"
            )
            path = root / "example_patches.tsv"
            header = "image_id\tminsup\titems\tword\trow\tcol\tpatch_row_major\n1\t0.05\t1\t1\t1\t1\t"
            command = ["plot", str(source), str(root), str(output), "--ids", "1", "2", "--words", "1"]
            path.write_text(header + "0" * 16 + "\n", encoding="utf-8")
            with patch("sys.argv", command):
                plot.main()
                self.assertEqual(output.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
                path.write_text(header + "1" * 16 + "\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "source patch differs for image 1"):
                    plot.main()
