"""Run the integrated INT32 -> VEXP -> FP32 sum test (scale=1, no division).

Usage: python3 verify_softmax_exp_sum.py (Python 3 and Icarus Verilog).
Reference uses current VEXP approximation, then FP32 rounding after EVERY add.
"""
from pathlib import Path
import random
import struct
import subprocess
import tempfile
from softmax_bf16_int8 import encode_bf16, vexp_bf16, decode_bf16, fp32


def reference(row):
    maximum = max(row)
    total = 0.0
    for value in row:
        term = decode_bf16(vexp_bf16(encode_bf16(value - maximum)))
        total = fp32(total + term)
    return total


def main():
    rows = [[2,1,0], [10,25,-3], [-5,-8,-2], [0], [-(1<<31)],
            [-(1<<31),(1<<31)-1], [1002,1001,1000], [7]*8,
            [0]*32, list(range(-16,16)),
            [0,-1,-80,-87,-88,-89,-128,-255,-257,-259,-511,-513]]
    rng = random.Random(20261029)
    for length in (2,3,8,16,31,32):
        for _ in range(5):
            rows.append([rng.randint(-16,16) for _ in range(length)])
            rows.append([rng.randint(-(1<<31),(1<<31)-1) for _ in range(length)])
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='softmax_exp_sum_') as directory:
        work = Path(directory)
        lines = []
        for row in rows:
            bits = struct.unpack('>I',struct.pack('>f',reference(row)))[0]
            lines.append(f'{len(row)} {bits:08x}\n')
            maximum = max(row)
            lines.extend(f'{value & 0xffffffff:08x} {vexp_bf16(encode_bf16(value-maximum)):04x}\n'
                         for value in row)
        vectors = work/'vectors.txt'
        vectors.write_text(''.join(lines))
        files = ['rtl/softmax_row_max.sv','rtl/int33_to_bf16.sv','rtl/vexp.sv','rtl/softmax_exp.sv',
                 'rtl/fp32_add_positive.sv','rtl/softmax_sum.sv','rtl/softmax_exp_sum.sv','tb/tb_softmax_exp_sum.sv']
        compiled = subprocess.run(['iverilog','-g2012','-s','tb_softmax_exp_sum','-o',str(work/'sim'),
                                   *(str(root/name) for name in files)],capture_output=True,text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout+compiled.stderr)
        warnings = [line for line in compiled.stderr.splitlines() if 'constant selects in always_*' not in line]
        if warnings: print('\n'.join(warnings))
        subprocess.run(['vvp',str(work/'sim'),f'+VECTORS={vectors}'],check=True)
    print('Python sum for [2, 1, 0]:',reference([2,1,0]))


if __name__ == '__main__':
    main()
