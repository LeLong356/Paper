"""Floating-point reference for one softmax row; no RTL or BF16 emulation."""

import argparse
import math


def softmax(values, scale=1.0):
    """Return softmax(scale * values) for a nonempty row of finite numbers."""
    scale = float(scale)
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("scale must be finite and greater than zero")
    values = [float(value) for value in values]
    if not values:
        raise ValueError("input row must not be empty")
    if not all(math.isfinite(value) for value in values):
        raise ValueError("input values must be finite")
    scores = [value * scale for value in values]
    if not all(math.isfinite(score) for score in scores):
        raise ValueError("scaled input exceeds the floating-point range")
    maximum = max(scores)
    exponentials = [math.exp(score - maximum) for score in scores]
    denominator = math.fsum(exponentials)
    return [value / denominator for value in exponentials]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("values", nargs="*", type=float, default=[2.0, 1.0, 0.0])
    parser.add_argument("--scale", type=float, default=1.0, help="positive input multiplier (default: 1)")
    args = parser.parse_args()
    try:
        probabilities = softmax(args.values, args.scale)
    except ValueError as error:
        parser.error(str(error))
    print(f"Input: {args.values}")
    print(f"Scale: {args.scale}")
    print("Softmax: [" + ", ".join(f"{value:.10f}" for value in probabilities) + "]")
    print(f"Sum: {math.fsum(probabilities):.12f}")


if __name__ == "__main__":
    main()
