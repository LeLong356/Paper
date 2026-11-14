"""Run with python3 -m unittest test_softmax_buffers (requires Icarus Verilog)."""
from pathlib import Path
import random
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TB = r'''module tb;
    parameter DEPTH = 32;
    localparam WIDTH = $clog2(DEPTH + 1);
    logic clk = 0, rst_n = 0, start = 0, exp_valid = 0, exp_last = 0;
    logic [WIDTH-1:0] row_length, read_index = 0;
    logic [15:0] exp_data;
    wire [15:0] read_data;
    wire ready, sum_valid;
    wire [31:0] sum_fp32;
    integer f, n, sample, addr, expected;
    softmax_sum #(.MAX_LENGTH(DEPTH)) dut (.*);
    always #5 clk = ~clk;
    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        f = $fopen("vectors", "r");
        while ($fscanf(f, "%d", n) == 1) begin
            start = 1; row_length = n;
            @(negedge clk);
            if (ready || read_data !== 0) $fatal(1, "stale data on start");
            start = 0;
            for (integer i = 0; i < n; i++) begin
                if ($fscanf(f, "%h", sample) != 1) $fatal;
                exp_data = sample; exp_valid = 1; exp_last = i == n-1;
                @(negedge clk);
            end
            exp_valid = 0; exp_last = 0;
            wait (sum_valid);
            @(negedge clk);
            repeat (n + 2) begin
                if ($fscanf(f, "%d %h", addr, expected) != 2) $fatal;
                read_index = addr;
                @(negedge clk);
                if (read_data !== expected[15:0])
                    $fatal(1, "depth=%0d length=%0d addr=%0d got=%h expected=%h",
                           DEPTH, n, addr, read_data, expected);
            end
        end
        $finish;
    end
    initial #1000000 $fatal(1, "timeout");
endmodule
'''


class BufferTests(unittest.TestCase):
    def simulate(self, directory, top, sources, *options):
        subprocess.run(["iverilog", "-g2012", "-s", top, *options, "-o", "sim",
                        *sources], cwd=directory, check=True)
        subprocess.run(["vvp", "sim"], cwd=directory, check=True, timeout=60)

    def test_row_stream(self):
        with tempfile.TemporaryDirectory() as directory:
            self.simulate(directory, "tb_softmax_row_max",
                          [ROOT / 'rtl/softmax_row_max.sv', ROOT / 'tb/tb_softmax_row_max.sv'])

    def test_exp_random_readback(self):
        for depth in (1, 17, 32):
            with self.subTest(depth=depth), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                rng = random.Random(depth)
                lines = []
                for n in (depth, 1, max(1, depth // 2)):
                    row = [rng.randrange(0x3800, 0x3f81) for _ in range(n)]
                    lines.extend([str(n), *(f"{value:04x}" for value in row)])
                    order = list(range(n))
                    rng.shuffle(order)
                    # Check stale locations and a high address that can alias a RAM word.
                    order.extend([n, (1 << depth.bit_length()) - 1])
                    for address in order:
                        expected = row[address] if address < n else 0
                        lines.append(f"{address} {expected:04x}")
                (work / "vectors").write_text("\n".join(lines) + "\n")
                (work / "tb.sv").write_text(TB)
                self.simulate(work, "tb", [ROOT / 'rtl/fp32_add_positive.sv',
                                           ROOT / 'rtl/softmax_sum.sv', work / "tb.sv"],
                              f"-Ptb.DEPTH={depth}")


if __name__ == "__main__":
    unittest.main()
