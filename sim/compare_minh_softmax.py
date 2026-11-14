"""Compare INT32 softmax against Minh's committed GEMM vectors, scale=1."""

import argparse
import math
from pathlib import Path
import subprocess

from softmax_fixed import CONFIGS, softmax_fixed
from softmax_golden import softmax


def git(*arguments):
    root = Path(__file__).resolve().parents[1]
    return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()


def load_vector(commit, filename, width):
    directory = "Gemm_Accelerate/Simulation_Sources/top_test_hexfile/"
    encoded = [int(value, 16) for value in git("show", f"{commit}:{directory}{filename}").split()]
    if not all(0 <= value < (1 << width) for value in encoded):
        raise ValueError("hex value exceeds declared width")
    return [value - (1 << width) if value & (1 << (width - 1)) else value for value in encoded]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="origin/Minh")
    args = parser.parse_args()
    commit = git("rev-parse", args.ref)
    matrix_a = load_vector(commit, "matrix_A.hex", 8)
    matrix_b = load_vector(commit, "matrix_B.hex", 8)
    matrix_c = load_vector(commit, "matrix_C.hex", 32)
    size = math.isqrt(len(matrix_c))
    if size < 2 or size * size != len(matrix_c) or len(matrix_a) != len(matrix_c) or len(matrix_b) != len(matrix_c):
        raise ValueError("expected equally sized square matrix fixtures")
    expected = [
        sum(matrix_a[row * size + inner] * matrix_b[inner * size + column] for inner in range(size))
        for row in range(size) for column in range(size)
    ]
    if expected != matrix_c:
        raise AssertionError("matrix_C does not match exact integer A @ B")
    rows = [matrix_c[offset:offset + size] for offset in range(0, len(matrix_c), size)]
    references = [softmax(row) for row in rows]
    gaps = [sorted(row)[-1] - sorted(row)[-2] for row in rows]
    print(f"Source commit: {commit}; shape={size}x{size}; scale=1; A@B matches C exactly")
    print(f"INT32 range: [{min(matrix_c)}, {max(matrix_c)}]; top-two gap: [{min(gaps)}, {max(gaps)}]")
    for config in CONFIGS:
        results = [softmax_fixed(row, config) for row in rows]
        errors = [abs(actual - expected) for result, reference in zip(results, references)
                  for actual, expected in zip(result["probabilities"], reference)]
        sum_error = max(abs(math.fsum(result["probabilities"]) - 1) for result in results)
        one_hot = sum(result["probabilities"].count(1.0) == 1 and result["probabilities"].count(0.0) == size - 1 for result in results)
        print(f"{config.name}: max_abs={max(errors):.12g}, mean_abs={math.fsum(errors)/len(errors):.12g}, "
              f"max_sum_error={sum_error:.12g}, cutoff={sum(result['exp_cutoffs'] for result in results)}, one_hot_rows={one_hot}/{size}")
    print("Committed reference vectors, not a new simulation of Minh RTL. Near-one-hot rows at scale=1 are not representative accuracy coverage.")


if __name__ == "__main__":
    main()
