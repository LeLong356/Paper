"""Simulate the converter and compare bit-for-bit with Python encode_bf16.

Run in Ubuntu with Python 3 and Icarus Verilog: python3 verify_int33_to_bf16.py
"""
from pathlib import Path
import random
import subprocess
import tempfile

from softmax_bf16_int8 import encode_bf16


def main():
    lower, upper = -(1 << 32), (1 << 32) - 1
    values = set(range(-1024, 1025))
    values.update([lower, lower + 1, upper - 1, upper])
    # Powers of two, rounding halfway cases and adjacent integers, both signs.
    for k in range(33):
        for delta in (-1, 0, 1):
            for sign in (-1, 1):
                values.add(sign * ((1 << k) + delta))
    for k in range(8, 32):
        step = 1 << (k - 7)
        for mantissa in range(128, 256):
            midpoint = mantissa * step + step // 2
            for delta in (-1, 0, 1):
                values.update([midpoint + delta, -(midpoint + delta)])
    rng = random.Random(20261026)
    values.update(rng.randint(lower, upper) for _ in range(10000))
    values = sorted(x for x in values if lower <= x <= upper)
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="int33_bf16_") as directory:
        work = Path(directory)
        (work / "vectors.txt").write_text("".join(
            f"{x & ((1 << 33) - 1):09x} {encode_bf16(x):04x}\n" for x in values
        ))
        (work / "tb.sv").write_text('''`timescale 1ns/1ps
module tb;
  logic signed [32:0] in_data;
  wire [15:0] out_bf16;
  reg [15:0] expected;
  integer fd, status, count;
  int33_to_bf16 dut(.*);
  initial begin
    count = 0;
    fd = $fopen("vectors.txt", "r");
    if (!fd) $fatal(1, "Cannot open vectors");
    while (!$feof(fd)) begin
      status = $fscanf(fd, "%h %h", in_data, expected);
      if (status == 2) begin
        #1;
        if (out_bf16 !== expected)
          $fatal(1, "input=%0d got=%h expected=%h", in_data, out_bf16, expected);
        count = count + 1;
      end
    end
    $fclose(fd);
    $display("PASS: %0d INT33 values match Python BF16 model", count);
    $finish;
  end
endmodule
''')
        subprocess.run(["iverilog", "-g2012", "-s", "tb", "-o", str(work / "sim"),
                        str(root / 'rtl/int33_to_bf16.sv'), str(work / "tb.sv")], check=True)
        subprocess.run(["vvp", str(work / "sim")], cwd=work, check=True)


if __name__ == "__main__":
    main()
