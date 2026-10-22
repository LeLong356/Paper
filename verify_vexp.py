import math
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


def decode_bf16(bits):
    return struct.unpack(">f", struct.pack(">I", bits << 16))[0]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def analyze(dump_path):
    samples = []
    for expected_input, line in enumerate(dump_path.read_text().splitlines()):
        input_bits, output_bits = (int(field, 16) for field in line.split())
        require(input_bits == expected_input, "Missing, duplicated or out-of-order input")
        exponent = (input_bits >> 7) & 255
        fraction = input_bits & 127
        if exponent == 0:
            require(output_bits == 0x3F80, "Zero/subnormal input did not produce one")
        if exponent == 255:
            expected = 0x7FC0 if fraction else (0 if input_bits >> 15 else 0x7F80)
            require(output_bits == expected, "Incorrect NaN/infinity handling")
        else:
            require(output_bits < 0x7F81, "Finite input produced negative or NaN output")
            require(output_bits == 0 or output_bits >= 0x0080, "Output subnormal was not flushed")
            if input_bits >> 15:
                require(output_bits <= 0x3F80, "Negative input produced output above one")
        samples.append((input_bits, output_bits, decode_bf16(input_bits), decode_bf16(output_bits)))
    require(len(samples) == 65536, f"Expected 65536 patterns, got {len(samples)}")
    finite = sorted((value, result) for _, _, value, result in samples if math.isfinite(value))
    for previous, current in zip(finite, finite[1:]):
        if current[0] > previous[0]:
            require(current[1] >= previous[1], f"Monotonicity failure: {previous} -> {current}")
    print("PASS: special values, output flush-to-zero, range and monotonicity checks")
    for low, high in [(-8, 0), (-16, 0), (-80, 80)]:
        errors = [
            (abs(result / math.exp(value) - 1), bits, output, value, result)
            for bits, output, value, result in samples
            if low <= value <= high
        ]
        worst = max(errors)
        mean_error = sum(entry[0] for entry in errors) / len(errors)
        print(
            f"[{low}, {high}]: count={len(errors)}, max_relative_error={worst[0] * 100:.8f}%, "
            f"mean_per_bit_pattern={mean_error * 100:.8f}%, "
            f"worst_input=0x{worst[1]:04X} ({worst[3]}), "
            f"output=0x{worst[2]:04X} ({worst[4]}), reference={math.exp(worst[3]):.12g}"
        )
        require(worst[0] < 0.01, f"Relative error exceeds the 1% regression limit on [{low}, {high}]")
    print("PASS: accuracy regression limits on the three stated intervals")


def main():
    root = Path(__file__).resolve().parent
    for tool in ("iverilog", "vvp"):
        if shutil.which(tool) is None:
            raise SystemExit(f"Required tool not found: {tool}")
    with tempfile.TemporaryDirectory(prefix="vexp-verification-") as directory:
        temporary = Path(directory)
        executable = temporary / "simulation.vvp"
        dump = temporary / "outputs.txt"
        subprocess.run(
            ["iverilog", "-g2012", "-s", "tb_vexp_vivado", "-o", str(executable),
             str(root / "vexp.sv"), str(root / "tb.sv")],
            check=True,
        )
        subprocess.run(["vvp", str(executable), f"+DUMP={dump}"], check=True)
        analyze(dump)


if __name__ == "__main__":
    main()
