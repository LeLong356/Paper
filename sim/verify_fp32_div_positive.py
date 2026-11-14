"""Verify FP32 divider with exact integer arithmetic, no double rounding.

Run: python3 verify_fp32_div_positive.py (Python 3 + Icarus Verilog).
Reference divides exactly then rounds once to FP32, nearest-even.
This is direct division, not rounded reciprocal followed by multiplication.
"""
from pathlib import Path
import random
import struct
import subprocess
import tempfile
from softmax_bf16_int8 import encode_bf16, vexp_bf16, decode_bf16, fp32


def round_ratio(n, d):
    q, r = divmod(n, d)
    return q + int(2*r > d or (2*r == d and q & 1))


def finite_ratio(bits):
    exponent = (bits >> 23) & 255
    mantissa = bits & 0x7fffff
    if exponent:
        mantissa |= 1 << 23
    power = (exponent if exponent else 1) - 127 - 23
    return (mantissa << power, 1) if power >= 0 else (mantissa, 1 << -power)


def reference(a, b):
    az, bz = (a & 0x7fffffff) == 0, (b & 0x7fffffff) == 0
    ai, bi = a == 0x7f800000, b == 0x7f800000
    invalid = ((a >> 31 and not az) or (b >> 31 and not bz) or
               ((a & 0x7fffffff) > 0x7f800000) or ((b & 0x7fffffff) > 0x7f800000))
    if invalid or (az and bz) or (ai and bi):
        return 0x7fc00000
    if bz or ai:
        return 0x7f800000
    if az or bi:
        return 0
    an, ad = finite_ratio(a)
    bn, bd = finite_ratio(b)
    n, d = an*bd, ad*bn
    exponent = n.bit_length() - d.bit_length()
    if (n < (d << exponent)) if exponent >= 0 else ((n << -exponent) < d):
        exponent -= 1
    if exponent < -126:
        # Subnormal spacing is exactly 2^-149; rounding may reach min normal.
        return round_ratio(n << 149, d)
    shift = 23-exponent
    mantissa = round_ratio(n << shift, d) if shift >= 0 else round_ratio(n, d << -shift)
    if mantissa == 1 << 24:
        mantissa >>= 1
        exponent += 1
    if exponent > 127:
        return 0x7f800000
    return ((exponent+127) << 23) | (mantissa & 0x7fffff)


def bits(value):
    return struct.unpack('>I', struct.pack('>f', value))[0]


def main():
    pairs = [(bits(6),bits(4)), (bits(1),bits(3)), (bits(0),bits(2)), (bits(1),bits(1))]
    edges = [0,1,2,3,0x7ffffe,0x7fffff,0x800000,0x800001,0x3f000000,
             0x3f7fffff,0x3f800000,0x3f800001,0x40000000,0x7f7fffff,
             0x7f800000,0x7fc00000,0x80000000,0xbf800000]
    pairs.extend((a,b) for a in edges for b in edges)
    # Underflow halfway, adjacent values, and subnormal-to-normal boundaries.
    for base in (1,3,0x7fffff,0x800000,0xffffff,0x1000000):
        for delta in (-1,0,1):
            for denom in (bits(2),bits(4),bits(2048)):
                pairs.append((base+delta,denom))
    rng = random.Random(20261030)
    pairs.extend((rng.randrange(1,0x7f800000),rng.randrange(1,0x7f800000)) for _ in range(10000))
    pairs.extend((rng.randrange(1,0x800000),rng.randrange(1,0x800000)) for _ in range(1000))
    # Real operands from the current softmax path, including tiny VEXP values.
    for length in (1,3,32,128,2048):
        row=[rng.randint(-87,0) for _ in range(length)]
        maximum=max(row)
        terms=[vexp_bf16(encode_bf16(x-maximum)) for x in row]
        total=0.0
        for term in terms:
            total=fp32(total+decode_bf16(term))
        pairs.extend((term << 16,bits(total)) for term in terms)
    assert reference(bits(6),bits(4)) == bits(1.5)
    assert reference(bits(1),bits(3)) == 0x3eaaaaab
    assert reference(1,bits(2)) == 0  # Exact halfway rounds to even zero.
    assert reference(3,bits(2)) == 2
    root=Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='fp32_div_') as directory:
        work=Path(directory)
        vectors=work/'vectors.txt'
        vectors.write_text(''.join(f'{a:08x} {b:08x} {reference(a,b):08x}\n' for a,b in pairs))
        compiled=subprocess.run(['iverilog','-g2012','-s','tb_fp32_div_positive','-o',str(work/'sim'),
                                 str(root/'rtl/fp32_div_positive.sv'),str(root/'tb/tb_fp32_div_positive.sv')],
                                capture_output=True,text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout+compiled.stderr)
        warnings=[line for line in compiled.stderr.splitlines() if 'constant selects in always_*' not in line]
        if warnings: print('\n'.join(warnings))
        subprocess.run(['vvp',str(work/'sim'),f'+VECTORS={vectors}'],check=True,timeout=120)


if __name__ == '__main__':
    main()
