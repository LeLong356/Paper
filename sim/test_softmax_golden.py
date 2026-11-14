import math
import unittest

from softmax_golden import softmax


class SoftmaxGoldenTests(unittest.TestCase):
    def assert_distribution(self, probabilities):
        self.assertTrue(all(math.isfinite(value) and 0 <= value <= 1 for value in probabilities))
        self.assertAlmostEqual(math.fsum(probabilities), 1.0, places=14)

    def assert_probabilities(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        self.assert_distribution(actual)
        for actual_value, expected_value in zip(actual, expected):
            self.assertAlmostEqual(actual_value, expected_value, places=12)

    def test_known_row(self):
        self.assert_probabilities(
            softmax([2, 1, 0]),
            [0.6652409557748218, 0.24472847105479764, 0.09003057317038046],
        )

    def test_equal_scores(self):
        for row in ([0, 0, 0], [17, 17, 17], [-20, -20, -20]):
            with self.subTest(row=row):
                self.assert_probabilities(softmax(row), [1 / 3] * 3)

    def test_negative_scores(self):
        self.assert_probabilities(softmax([-1, -2, -3]), softmax([2, 1, 0]))

    def test_large_common_offset(self):
        self.assert_probabilities(softmax([1002, 1001, 1000]), softmax([2, 1, 0]))

    def test_scale_applied_before_softmax(self):
        self.assert_probabilities(softmax([256, 128, 0], scale=1 / 128), softmax([2, 1, 0]))
        self.assertGreater(softmax([2, 1, 0], scale=2)[0], softmax([2, 1, 0])[0])

    def test_single_element(self):
        self.assert_probabilities(softmax([-123]), [1.0])

    def test_dominant_score(self):
        self.assert_probabilities(softmax([1000, 0, -1000]), [1.0, 0.0, 0.0])

    def test_signed_int32_extremes(self):
        self.assert_probabilities(softmax([2147483647, -2147483648]), [1.0, 0.0])

    def test_invalid_rows(self):
        for row in ([], [math.nan], [math.inf], [-math.inf], [0, math.nan]):
            with self.subTest(row=row), self.assertRaises(ValueError):
                softmax(row)

    def test_invalid_scales(self):
        for scale in (0, -1, math.nan, math.inf, -math.inf):
            with self.subTest(scale=scale), self.assertRaises(ValueError):
                softmax([1, 2], scale=scale)

    def test_scaled_input_overflow(self):
        with self.assertRaises(ValueError):
            softmax([1e308], scale=2)


if __name__ == "__main__":
    unittest.main()
