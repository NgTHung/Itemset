"""Check the growth fit behind the output-size table."""

import math
from pathlib import Path
import sys
from unittest import TestCase

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import plot_output_size as plot


class GrowthFitTest(TestCase):
    def test_power_law_gives_its_exponent_everywhere(self):
        xs = [0.9, 0.6, 0.3, 0.1]
        counts = [10 * x ** -3 for x in xs]
        fit = plot.growth_fit(xs, counts)
        self.assertAlmostEqual(fit.slope, 3.0)
        self.assertAlmostEqual(fit.r_squared, 1.0)
        for local in fit.adjacent_slopes:
            self.assertAlmostEqual(local, 3.0)

    def test_adjacent_slopes_follow_each_step(self):
        fit = plot.growth_fit([0.25, 0.2], [5545, 53583])
        self.assertAlmostEqual(fit.adjacent_slopes[0], math.log(53583 / 5545) / math.log(0.25 / 0.2))

    def test_per_hundredth_slope_measures_log_growth_per_0_01_of_minsup(self):
        fit = plot.growth_fit([0.02, 0.01], [100, 100 * math.e])
        self.assertAlmostEqual(fit.per_hundredth, 1.0)

    def test_scatter_lowers_r_squared(self):
        fit = plot.growth_fit([0.9, 0.6, 0.3, 0.1], [10, 300, 200, 5000])
        self.assertLess(fit.r_squared, 1.0)
        self.assertGreater(fit.r_squared, 0.0)
