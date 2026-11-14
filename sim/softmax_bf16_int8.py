"""INT32 -> signed INT33 difference -> BF16 VEXP -> FP32 normalization -> INT8."""

import argparse
import math
import operator
from pathlib import Path
import random
import struct
import subprocess
import tempfile

from softmax_golden import softmax
from verify_vexp import decode_bf16


def round_ratio(numerator, denominator):
    quotient, remainder = divmod(numerator, denominator)
    return quotient + int(2 * remainder > denominator or (2 * remainder == denominator and quotient % 2))


def encode_bf16(value):
    """Round the Python float directly to BF16, nearest with ties to even."""
    value = float(value)
    if math.isnan(value):
        return 0x7FC0
    sign = 0x8000 if math.copysign(1.0, value) < 0 else 0
    magnitude = abs(value)
    if math.isinf(magnitude):
        return sign | 0x7F80
    if magnitude == 0:
        return sign
    exponent = max(math.frexp(magnitude)[1] - 1, -126)
    if exponent > 127:
        return sign | 0x7F80
    numerator, denominator = magnitude.as_integer_ratio()
    shift = exponent - 7
    if shift < 0:
        numerator <<= -shift
    else:
        denominator <<= shift
    mantissa = round_ratio(numerator, denominator)
    if mantissa == 256:
        mantissa = 128
        exponent += 1
    if exponent > 127:
        return sign | 0x7F80
    if mantissa < 128:
        return sign | mantissa
    return sign | ((exponent + 127) << 7) | (mantissa - 128)


def vexp_bf16(bits):
    """Bit-level model of the current vexp.sv, including its unchanged px."""
    sign = bits >> 15
    exponent = (bits >> 7) & 255
    fraction = bits & 127
    if exponent == 0:
        return 0x3F80
    if exponent == 255 and fraction:
        return 0x7FC0
    if exponent > 133:
        return 0 if sign else 0x7F80
    product = (128 + fraction) * 23637
    shift = 141 - exponent
    magnitude = (product >> shift) + ((product >> (shift - 1)) & 1)
    encoded = 16256 + (-magnitude if sign else magnitude)
    if encoded < 128:
        return 0
    if encoded >= 32640:
        return 0x7F80
    fraction = encoded & 127
    if fraction < 64:
        corrected = (7 * fraction * (fraction + 422)) // 4096
    else:
        corrected = 127 - (7 * (127 - fraction) * (fraction + 278)) // 2048
    return (encoded & 0xFF80) | corrected


def fp32(value):
    return struct.unpack(">f", struct.pack(">f", value))[0]


def quantize_int8(probability):
    return max(0, min(127, round(fp32(probability * 127))))


def softmax_bf16_int8(values, scale=1.0):
    try:
        values = [operator.index(value) for value in values]
    except TypeError as error:
        raise ValueError("input must contain INT32 integers") from error
    if not 1 <= len(values) <= 32:
        raise ValueError("row length must be 1..32")
    if not all(-(1 << 31) <= value < (1 << 31) for value in values):
        raise ValueError("input exceeds signed INT32 range")
    scale = float(scale)
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("scale must be finite and positive")
    maximum = max(values)
    differences = [value - maximum for value in values]
    if not all(-(1 << 32) <= value < (1 << 32) for value in differences):
        raise OverflowError("signed INT33 subtraction overflow")
    scaled = [value * scale for value in differences]
    if not all(math.isfinite(value) for value in scaled):
        raise ValueError("scaled difference exceeds Python floating-point range")
    input_bf16 = [encode_bf16(value) for value in scaled]
    exp_bf16 = [vexp_bf16(bits) for bits in input_bf16]
    exponentials = [decode_bf16(bits) for bits in exp_bf16]
    denominator = 0.0
    for value in exponentials:
        denominator = fp32(denominator + value)
    reciprocal = fp32(1.0 / denominator)
    probabilities = [fp32(value * reciprocal) for value in exponentials]
    output = [quantize_int8(value) for value in probabilities]
    return {
        "differences_int33": differences,
        "input_bf16": input_bf16,
        "exp_bf16": exp_bf16,
        "denominator_fp32": denominator,
        "probabilities_fp32": probabilities,
        "output_int8": output,
        "decoded_output": [value / 127 for value in output],
    }


def verify_rtl():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="vexp-python-check-") as directory:
        binary = Path(directory) / "sim.vvp"
        dump = Path(directory) / "outputs.txt"
        subprocess.run(["iverilog", "-g2012", "-s", "tb_vexp_vivado", "-o", str(binary),
                        str(root / 'rtl/vexp.sv'), str(root / 'tb/tb.sv')], check=True)
        subprocess.run(["vvp", str(binary), f"+DUMP={dump}"], check=True)
        lines = dump.read_text().splitlines()
        if len(lines) != 65536:
            raise AssertionError("expected all 65536 input patterns")
        for expected_input, line in enumerate(lines):
            bits, output = (int(field, 16) for field in line.split())
            if bits != expected_input or output != vexp_bf16(bits):
                raise AssertionError(f"Python/RTL mismatch: {line}")
    print("PASS: Python VEXP matches current RTL for all 65536 BF16 patterns")


def compare_rows(rows, scale, label):
    before_errors, after_errors, sum_errors = [], [], []
    all_zero = 0
    for row in rows:
        reference = softmax(row, scale)
        result = softmax_bf16_int8(row, scale)
        before_errors.extend(abs(actual - expected) for actual, expected in zip(result["probabilities_fp32"], reference))
        after_errors.extend(abs(actual - expected) for actual, expected in zip(result["decoded_output"], reference))
        sum_errors.append(abs(math.fsum(result["decoded_output"]) - 1))
        all_zero += not any(result["output_int8"])
    print(f"{label}: rows={len(rows)}, scale={scale}, max_error_before_INT8={max(before_errors):.12g}, "
          f"max_error_after_INT8={max(after_errors):.12g}, max_decoded_sum_error={max(sum_errors):.12g}, all_zero_rows={all_zero}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--verify-rtl", action="store_true")
    parser.add_argument("--minh-ref")
    args = parser.parse_args()
    if args.verify_rtl:
        verify_rtl()
    for row in ([2, 1, 0], [1002, 1001, 1000], [0, 0, 0]):
        result = softmax_bf16_int8(row, args.scale)
        print(f"{row}: INT8={result['output_int8']}, decoded={result['decoded_output']}")
    generator = random.Random(20261024)
    rows = [[2, 1, 0], [-1, -2, -3], [2147483647, -2147483648]]
    for length in (2, 8, 16, 31, 32):
        rows.append([0] * length)
        rows.extend([generator.randint(-8, 8) for _ in range(length)] for _ in range(8))
    compare_rows(rows, args.scale, "Synthetic INT32")
    if args.minh_ref:
        from compare_minh_softmax import git, load_vector

        commit = git("rev-parse", args.minh_ref)
        matrix = load_vector(commit, "matrix_C.hex", 32)
        size = math.isqrt(len(matrix))
        if not size or size * size != len(matrix):
            raise ValueError("expected square matrix C fixture")
        rows = [matrix[offset:offset + size] for offset in range(0, len(matrix), size)]
        compare_rows(rows, args.scale, f"Minh C fixture {commit}")


if __name__ == "__main__":
    main()
