"""Run standalone quantizer verification: python3 verify_fp32_to_int8.py.

Python reference: round(FP32_round(p * 127)), then clamp to 0..127.
Uses the existing model's quantize_int8 for finite inputs in [0,1].
NaN/negative -> 0, input >= 1 (including +inf) -> 127.
No softmax RTL integration and no third-party Python packages required.
"""
from pathlib import Path
import math
import random
import struct
import subprocess
import tempfile
from softmax_bf16_int8 import quantize_int8


def bits(value):
    return struct.unpack('>I',struct.pack('>f',value))[0]


def real(value):
    return struct.unpack('>f',struct.pack('>I',value))[0]


def reference(raw):
    p=real(raw)
    if math.isnan(p) or p<=0:
        return 0
    if p>=1:
        return 127
    return quantize_int8(p)


def main():
    values={0,0x80000000,1,0x7fffff,0x800000,0x7f800000,0xff800000,
            0x7fc00000,0x7f800001,0xffc00000,0x7f7fffff,0xff7fffff}
    # Every integer rounding boundary (k+0.5)/127 and nearby FP32 inputs.
    for k in range(127):
        midpoint=bits((k+0.5)/127)
        values.update(midpoint+offset for offset in range(-8,9))
    for p in (0,1/256,1/254,0.5,1.0,0.6645035743713379,0.24529525637626648,0.09020116925239563):
        center=bits(p)
        values.update(x for x in range(max(0,center-8),center+9))
    # Sweep mantissa samples in every relevant exponent bin.
    for exponent in range(119,127):
        values.update((exponent<<23)|fraction for fraction in range(0,1<<23,4096))
    rng=random.Random(20261102)
    values.update(bits(rng.random()) for _ in range(10000))
    values.update(rng.getrandbits(32) for _ in range(10000))
    values=sorted(values)
    # Demonstrate that both rounding steps matter for this test set.
    double_round_cases=sum(reference(x)!=round(real(x)*127)
                           for x in values if 0<=real(x)<=1)
    assert double_round_cases>0, 'Missing coverage for two-step rounding'
    root=Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='fp32_int8_') as directory:
        work=Path(directory); vectors=work/'vectors.txt'
        vectors.write_text(''.join(f'{raw:08x} {reference(raw)}\n' for raw in values))
        compiled=subprocess.run(['iverilog','-g2012','-s','tb_fp32_to_int8','-o',str(work/'sim'),
                                 str(root/'rtl/fp32_to_int8.sv'),str(root/'tb/tb_fp32_to_int8.sv')],
                                capture_output=True,text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout+compiled.stderr)
        warnings=[line for line in compiled.stderr.splitlines() if 'constant selects in always_*' not in line]
        if warnings: print('\n'.join(warnings))
        subprocess.run(['vvp',str(work/'sim'),f'+VECTORS={vectors}'],check=True,timeout=120)
    print(f'Two-rounding-step edge cases checked: {double_round_cases}')
    for p in (0.0,0.5,1.0,0.6645035743713379,0.24529525637626648,0.09020116925239563):
        print(f'{p:.9g} -> {reference(bits(p))}')


if __name__=='__main__':
    main()
