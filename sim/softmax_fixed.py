"""Integer softmax model with quantized exp LUT and rounded reciprocal."""

from dataclasses import dataclass
from functools import lru_cache
import math
import operator
import random

from softmax_golden import softmax


@dataclass(frozen=True)
class Config:
    name: str
    input_fraction: int
    probability_fraction: int
    max_length: int = 2048

    @property
    def input_width(self):
        return 32

    @property
    def accumulator_width(self):
        return (self.max_length << self.probability_fraction).bit_length()

    @property
    def reciprocal_fraction(self):
        return self.probability_fraction + (self.max_length - 1).bit_length()


CONFIGS = (Config("small", 4, 8), Config("medium", 8, 12), Config("large", 12, 16))


def round_ratio(numerator, denominator):
    """Round a nonnegative rational to nearest, ties to even."""
    quotient, remainder = divmod(numerator, denominator)
    return quotient + int(2 * remainder > denominator or (2 * remainder == denominator and quotient % 2))


@lru_cache(maxsize=3)
def exp_table(input_fraction, output_fraction):
    """Generate quantized exp(-index / 2**F) over [-16, 0]."""
    return tuple(
        round(math.exp(-index / (1 << input_fraction)) * (1 << output_fraction))
        for index in range((16 << input_fraction) + 1)
    )


def softmax_fixed(values, config=CONFIGS[1], scale=1.0):
    """Subtract the INT32 maximum exactly in signed 33-bit, then scale."""
    if config not in CONFIGS:
        raise ValueError("use one of the predefined CONFIGS")
    scale = float(scale)
    try:
        values = [operator.index(value) for value in values]
    except TypeError as error:
        raise ValueError("inputs must be signed INT32 integers") from error
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("scale must be finite and positive")
    if not 1 <= len(values) <= config.max_length:
        raise ValueError(f"row length must be between 1 and {config.max_length}")
    if not all(-(1 << 31) <= value < (1 << 31) for value in values):
        raise ValueError("inputs must be within signed INT32 range")
    peak = max(values)
    differences = [value - peak for value in values]
    if not all(-(1 << 32) <= value < (1 << 32) for value in differences):
        raise OverflowError("signed 33-bit subtraction overflow")
    scale_numerator, scale_denominator = scale.as_integer_ratio()
    cutoff = [-value * scale_numerator > 16 * scale_denominator for value in differences]
    distances = [
        0 if clipped else round_ratio(-value * scale_numerator * (1 << config.input_fraction), scale_denominator)
        for value, clipped in zip(differences, cutoff)
    ]
    table = exp_table(config.input_fraction, config.probability_fraction)
    exponentials = [0 if clipped else table[distance] for distance, clipped in zip(distances, cutoff)]
    denominator = sum(exponentials)
    if not 0 < denominator < (1 << config.accumulator_width):
        raise OverflowError("accumulator range exceeded")
    reciprocal = round_ratio(1 << (config.probability_fraction + config.reciprocal_fraction), denominator)
    unit = 1 << config.probability_fraction
    outputs = [min(unit, round_ratio(value * reciprocal, 1 << config.reciprocal_fraction)) for value in exponentials]
    return {
        "probabilities": [value / unit for value in outputs],
        "encoded_output": outputs,
        "input_saturations": 0,
        "differences_int33": differences,
        "exp_cutoffs": sum(cutoff),
        "exp_zeros": exponentials.count(0),
        "accumulator": denominator,
    }


def test_rows():
    generator = random.Random(20261024)
    rows = [[2, 1, 0], [-1, -2, -3], [0, 0, 0], [7]]
    for length in (8, 32, 128, 512, 2048):
        rows.append([0] * length)
        rows.append([8] + [-8] * (length - 1))
        for _ in range(8):
            rows.append([generator.randint(-128, 127) for _ in range(length)])
            rows.append([generator.randint(-8, 8) for _ in range(length)])
    return rows


def main():
    rows = test_rows()
    references = [softmax(row, scale=1) for row in rows]
    print(f"Scale=1; {len(rows)} INT32 rows; seed=20261024; lengths up to 2048; inputs in [-128,127]")
    print("name input(W,F) difference_fraction exp/output(W,F) sum_bits reciprocal(W,F) max_abs_error mean_abs_error max_sum_error saturations")
    for config in CONFIGS:
        errors = []
        sum_errors = []
        saturations = 0
        for row, reference in zip(rows, references):
            result = softmax_fixed(row, config)
            errors.extend(abs(actual - expected) for actual, expected in zip(result["probabilities"], reference))
            sum_errors.append(abs(math.fsum(result["probabilities"]) - 1))
            saturations += result["input_saturations"]
        print(
            f"{config.name} (32,0) {config.input_fraction} "
            f"({config.probability_fraction + 1},{config.probability_fraction}) "
            f"{config.accumulator_width} ({config.reciprocal_fraction + 1},{config.reciprocal_fraction}) "
            f"{max(errors):.9f} {math.fsum(errors)/len(errors):.9f} {max(sum_errors):.9f} {saturations}"
        )
        print(f"  [2,1,0]: {softmax_fixed([2, 1, 0], config)['probabilities']}")
        uniform = softmax_fixed([0] * 2048, config)
        stress = softmax_fixed([1002, 1001, 1000], config)
        print(f"  uniform length 2048: output sum={math.fsum(uniform['probabilities'])}")
        print(f"  offset check [1002,1001,1000]: {stress['probabilities']}, saturated inputs={stress['input_saturations']}")
    print("LUT numerical experiment, not vexp BF16 emulation or synthesis/area results.")


if __name__ == "__main__":
    main()
