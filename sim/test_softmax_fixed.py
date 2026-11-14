import math
import unittest

from softmax_fixed import CONFIGS, exp_table, round_ratio, softmax_fixed, test_rows
from softmax_golden import softmax


class FixedSoftmaxTests(unittest.TestCase):
    def test_ties_to_even(self):
        self.assertEqual(round_ratio(5, 2), 2)
        self.assertEqual(round_ratio(7, 2), 4)
        self.assertEqual(round_ratio(8, 3), 3)

    def test_singleton_and_uniform(self):
        for config in CONFIGS:
            self.assertEqual(softmax_fixed([-5], config)["probabilities"], [1.0])
            self.assertEqual(softmax_fixed([0] * 8, config)["probabilities"], [0.125] * 8)

    def test_scale_and_shift(self):
        for config in CONFIGS:
            expected = softmax_fixed([2, 1, 0], config)["probabilities"]
            self.assertEqual(softmax_fixed([256, 128, 0], config, scale=1/128)["probabilities"], expected)
            self.assertEqual(softmax_fixed([-1, -2, -3], config)["probabilities"], expected)

    def test_lut_endpoints_and_cutoff(self):
        for config in CONFIGS:
            self.assertEqual(exp_table(config.input_fraction, config.probability_fraction)[0], 1 << config.probability_fraction)
            result = softmax_fixed([0, -17], config)
            self.assertEqual(result["exp_cutoffs"], 1)
            self.assertEqual(result["probabilities"], [1.0, 0.0])

    def test_large_offset_preserves_differences(self):
        for config in CONFIGS:
            result = softmax_fixed([1002, 1001, 1000], config)
            self.assertEqual(result["input_saturations"], 0)
            self.assertEqual(result["encoded_output"], softmax_fixed([2, 1, 0], config)["encoded_output"])
            self.assertEqual(result["differences_int33"], [0, -1, -2])

    def test_int33_extremes_and_scaling_order(self):
        for config in CONFIGS:
            result = softmax_fixed([2147483647, -2147483648], config)
            self.assertEqual(result["differences_int33"], [0, -4294967295])
            self.assertEqual(result["probabilities"], [1.0, 0.0])
            self.assertEqual(result["exp_cutoffs"], 1)
            scaled = softmax_fixed([2147483647, -2147483648], config, scale=2**-32)
            self.assertEqual(scaled["exp_cutoffs"], 0)
            self.assertLess(abs(scaled["probabilities"][0] - 0.7310585786), 0.005)

    def test_cutoff_boundary(self):
        for config in CONFIGS:
            self.assertEqual(softmax_fixed([0, -16], config)["exp_cutoffs"], 0)
            self.assertEqual(softmax_fixed([0, -17], config)["exp_cutoffs"], 1)

    def test_long_uniform_and_accumulator(self):
        for config in CONFIGS:
            result = softmax_fixed([0] * 2048, config)
            self.assertEqual(result["accumulator"], 2048 << config.probability_fraction)
            self.assertLess(result["accumulator"], 1 << config.accumulator_width)
            expected = 0.0 if config.probability_fraction == 8 else 1.0
            self.assertEqual(math.fsum(result["probabilities"]), expected)

    def test_probability_range_and_accuracy(self):
        for config, limit in zip(CONFIGS, (0.04, 0.004, 0.0003)):
            for row in test_rows():
                with self.subTest(config=config.name, length=len(row)):
                    result = softmax_fixed(row, config)
                    self.assertEqual(result["input_saturations"], 0)
                    self.assertTrue(all(0 <= value <= 1 for value in result["probabilities"]))
                    self.assertLess(max(abs(actual - expected) for actual, expected in zip(result["probabilities"], softmax(row))), limit)

    def test_invalid_inputs(self):
        for row in ([], [0] * 2049, [math.nan], [math.inf], [1.5], [2147483648], [-2147483649]):
            with self.assertRaises(ValueError):
                softmax_fixed(row)
        for scale in (0, -1, math.nan, math.inf):
            with self.assertRaises(ValueError):
                softmax_fixed([1], scale=scale)


if __name__ == "__main__":
    unittest.main()
