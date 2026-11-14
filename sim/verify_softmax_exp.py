"""Run the partial softmax RTL against Python, scale=1 (no sum/division).

Usage in Ubuntu: python3 verify_softmax_exp.py
Requires Python 3, iverilog and vvp. No third-party Python packages.
"""
from pathlib import Path
import random
import subprocess
import tempfile

from softmax_bf16_int8 import encode_bf16, vexp_bf16, decode_bf16


def main():
    rows = [[2, 1, 0], [10, 25, -3], [-5, -8, -2], [0],
            [-(1 << 31)], [-(1 << 31), (1 << 31)-1],
            [1002, 1001, 1000], [7]*8, [0]*32,
            list(range(-16, 16)),
            [0, -1, -80, -87, -88, -89, -128, -255, -257, -259, -511, -513]]
    rng = random.Random(20261026)
    for n in (2, 3, 8, 16, 31, 32):
        for _ in range(5):
            rows.append([rng.randint(-16, 16) for _ in range(n)])
            rows.append([rng.randint(-(1 << 31), (1 << 31)-1) for _ in range(n)])
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="softmax_exp_") as directory:
        work = Path(directory)
        lines = []
        for row in rows:
            maximum = max(row)
            lines.append(f"{len(row)} {maximum & 0xffffffff:08x}\n")
            for value in row:
                difference = value - maximum
                bf16 = encode_bf16(difference)
                lines.append(f"{value & 0xffffffff:08x} {difference & ((1<<33)-1):09x} "
                             f"{bf16:04x} {vexp_bf16(bf16):04x}\n")
        vectors = work / "vectors.txt"
        vectors.write_text("".join(lines))
        sources = ["rtl/softmax_row_max.sv", "rtl/int33_to_bf16.sv", "rtl/vexp.sv",
                   "rtl/softmax_exp.sv", "tb/tb_softmax_exp.sv"]
        subprocess.run(["iverilog", "-g2012", "-s", "tb_softmax_exp", "-o", str(work / "sim"),
                        *(str(root / name) for name in sources)], check=True)
        subprocess.run(["vvp", str(work / "sim"), f"+VECTORS={vectors}"], check=True)
    print("Example [2, 1, 0]: approximate exponentials =",
          [decode_bf16(vexp_bf16(encode_bf16(x))) for x in (0, -1, -2)])


if __name__ == "__main__":
    main()
