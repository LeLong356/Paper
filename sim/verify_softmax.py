"""End-to-end softmax.sv verification; scale=1, signed INT8 output 0..127.

Run from the repository root: python3 sim/verify_softmax.py
Requires Python 3 and Icarus Verilog, no third-party Python packages.
Reference: INT33 subtract -> BF16 -> current VEXP -> sequential FP32 sum
-> direct division rounded to FP32 -> FP32 multiply by 127 -> nearest-even INT8.
Also reports error against the floating-point mathematical golden model.
"""
from pathlib import Path
import math
import random
import struct
import subprocess
import tempfile
from softmax_bf16_int8 import encode_bf16, vexp_bf16, decode_bf16, fp32, quantize_int8
from verify_fp32_div_positive import reference as divide_reference, bits
from softmax_golden import softmax


def reference(row):
    maximum=max(row)
    terms=[vexp_bf16(encode_bf16(value-maximum)) for value in row]
    total=0.0
    for term in terms:
        total=fp32(total+decode_bf16(term))
    total_bits=bits(total)
    return total_bits,[divide_reference(term<<16,total_bits) for term in terms]


def real(value):
    return struct.unpack('>f',struct.pack('>I',value))[0]


def verify_capacity(capacity):
    rows=[[2,1,0],[10,25,-3],[-5,-8,-2],[0],[-(1<<31)],
          [-(1<<31),(1<<31)-1],[(1<<31)-1,(1<<31)-2,(1<<31)-3],
          [1002,1001,1000],[7]*8,[0]*32,list(range(-16,16)),
          [0,-1,-80,-87,-88,-89,-128,-255,-257,-259,-511,-513],
          [0]*31+[-87], [0,-1000,0,-1000]]
    # Equal probabilities exercise rounding ties and several row lengths.
    rows.extend([[0]*length for length in (2,3,7,15,16,31)])
    rng=random.Random(20261101)
    for length in (2,3,8,16,31,32):
        for _ in range(5):
            rows.append([rng.randint(-16,16) for _ in range(length)])
            rows.append([rng.randint(-(1<<31),(1<<31)-1) for _ in range(length)])
    # Keep the original S=32 vectors and exercise the upper addresses of larger builds.
    if capacity > 32:
        rows.extend([
            [rng.randint(-16, 16) for _ in range(capacity - 1)],
            [0] * capacity,
            [i % 8 - 4 for i in range(capacity)],
            [-(1 << 31), (1 << 31) - 1] * (capacity // 2),
        ])
    expected=[reference(row) for row in rows]
    root=Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='softmax_full_') as directory:
        work=Path(directory)
        lines=[]
        for row,(total,outputs) in zip(rows,expected):
            lines.append(f'{len(row)} {total:08x}\n')
            lines.extend(f'{value & 0xffffffff:08x} {out:08x} {quantize_int8(real(out)):02x}\n'
                         for value,out in zip(row,outputs))
        vectors=work/'vectors.txt'; dump=work/'outputs.txt'
        vectors.write_text(''.join(lines))
        files=['rtl/softmax.sv','rtl/softmax_exp_sum.sv','rtl/softmax_exp.sv','rtl/softmax_row_max.sv',
               'rtl/int33_to_bf16.sv','rtl/vexp.sv','rtl/softmax_sum.sv','rtl/fp32_add_positive.sv',
               'rtl/fp32_div_positive.sv','rtl/fp32_to_int8.sv','tb/tb_softmax.sv']
        compiled=subprocess.run(['iverilog','-g2012','-s','tb_softmax',
                                 f'-Ptb_softmax.MAX_LENGTH={capacity}','-o',str(work/'sim'),
                                 *(str(root/name) for name in files)],capture_output=True,text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout+compiled.stderr)
        warnings=[line for line in compiled.stderr.splitlines() if 'constant selects in always_*' not in line]
        if warnings: print('\n'.join(warnings))
        subprocess.run(['vvp',str(work/'sim'),f'+VECTORS={vectors}',f'+OUTPUT={dump}'],check=True,timeout=120)
        actual=[[] for _ in rows]
        records=iter(dump.read_text().splitlines())
        for r,(_,outputs) in enumerate(expected):
            for i,expected_bits in enumerate(outputs):
                fields=next(records).split()
                assert (int(fields[0]),int(fields[1]))==(r,i), 'Output ordering mismatch'
                actual_bits=int(fields[2],16)
                assert actual_bits==quantize_int8(real(expected_bits)), 'INT8 output mismatch'
                actual[r].append(actual_bits)
        assert next(records,None) is None, 'Extra outputs'
    errors=[]; sum_errors=[]
    for row,outputs in zip(rows,actual):
        golden=softmax(row,scale=1.0)
        assert all(0<=q<=127 for q in outputs)
        decoded=[q/127 for q in outputs]
        errors.extend(abs(p-g) for p,g in zip(decoded,golden))
        sum_errors.append(abs(math.fsum(decoded)-1.0))
    print('Example [2,1,0] RTL INT8:',actual[0])
    print('Equal 2-element row INT8:',actual[14])
    print('Equal 32-element row: nonzero outputs =',sum(q!=0 for q in actual[9]))
    print(f'Max absolute error of INT8/127 vs mathematical golden: {max(errors):.12g}')
    print(f'Mean absolute error vs mathematical golden: {math.fsum(errors)/len(errors):.12g}')
    print(f'Max |sum(INT8/127)-1|: {max(sum_errors):.12g}')
    print('Direct-division reference used; the older reciprocal-then-multiply model may differ by a few bits.')


if __name__=='__main__':
    for capacity in (32, 64, 128, 256):
        print(f'Checking S = {capacity}', flush=True)
        verify_capacity(capacity)
