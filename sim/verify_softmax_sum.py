"""Run: python3 verify_softmax_sum.py (requires Icarus Verilog).

Checks standalone FP32 addition and buffered BF16-row summation.
No division or changes to the upstream chain.
"""
from pathlib import Path
import random
import struct
import subprocess
import tempfile
from softmax_bf16_int8 import encode_bf16, decode_bf16, vexp_bf16


def bits(x):
    try:
        return struct.unpack('>I', struct.pack('>f', x))[0]
    except OverflowError:
        return 0x7f800000


def real(x):
    return struct.unpack('>f', struct.pack('>I', x))[0]


TB = r'''`timescale 1ns/1ps
module tb;
    localparam int MAX_LENGTH = 32;
  logic clk=0, rst_n=0, start=0, exp_valid=0, exp_last=0;
  logic [$clog2(MAX_LENGTH+1)-1:0] row_length=0;
  logic [15:0] exp_data=0;
  wire ready, sum_valid;
  wire [31:0] sum_fp32;
  logic [$clog2(MAX_LENGTH+1)-1:0] read_index=0;
  wire [15:0] read_data;
  logic av=0;
  logic [31:0] a=0,b=0;
  wire ar,ov;
  wire [31:0] result;
  reg [31:0] expected;
  reg [15:0] data[0:MAX_LENGTH-1];
  integer f,s,n,count=0,rows=0,cycles;
  softmax_sum dut(.*);
  fp32_add_positive adder(.clk(clk),.rst_n(rst_n),.in_valid(av),.in_ready(ar),
    .a(a),.b(b),.result(result),.out_valid(ov));
  always #2.5 clk=~clk; // 5 ns period (200 MHz)
  // Independent expected-data pipeline: compare every valid and every bubble.
  reg [5:0] expected_valid;
  reg [31:0] delayed_expected[0:5];
  integer checked=0;
  always @(posedge clk) begin
    if (!rst_n) expected_valid = 0;
    else begin
      expected_valid = {expected_valid[4:0], av};
      for (integer i=5; i>0; i--) delayed_expected[i] = delayed_expected[i-1];
      delayed_expected[0] = expected;
      #1;
      if (ov !== expected_valid[5]) $fatal(1,"Adder valid misaligned");
      if (ov) begin
        if (result !== delayed_expected[5])
          $fatal(1,"Adder got %h expected %h",result,delayed_expected[5]);
        checked++;
      end
    end
  end
  task reset_all;
    @(negedge clk); rst_n=0; start=0; exp_valid=0; av=0;
    #1; if(sum_valid !== 0 || ready !== 1 || ov !== 0) $fatal(1,"Reset failed");
    @(negedge clk); rst_n=1;
  endtask
  task start_row(input integer length);
    @(negedge clk); start=1; row_length=length;
    @(posedge clk); #1;
    if(ready !== 0 || sum_valid !== 0) $fatal(1,"Start failed");
    @(negedge clk); start=0; row_length=0;
  endtask
  initial begin
    reset_all();
    // Discard several in-flight requests before any can retire.
    av=1; a=0; b=0; expected=0;
    repeat(3) @(posedge clk);
    reset_all();
    f=$fopen("adds.txt","r"); if(!f) $fatal(1,"Missing adds");
    while(!$feof(f)) begin
      @(negedge clk);
      s=$fscanf(f,"%h %h %h",a,b,expected);
      if(s==3) begin
        if(count%17==3) begin
          av=0;
          @(negedge clk);
        end
        av=1;
        count=count+1;
      end else if(!$feof(f)) $fatal(1,"Malformed adds");
    end
    $fclose(f); av=0;
    repeat(7) @(negedge clk);
    if(checked!=count || ov !== 0) $fatal(1,"Output count mismatch");
    // Invalid row lengths are ignored.
    @(negedge clk); start=1; row_length=0;
    @(posedge clk); #1; if(ready !== 1) $fatal(1,"Accepted zero length");
    @(negedge clk); row_length=MAX_LENGTH+1;
    @(posedge clk); #1; if(ready !== 1) $fatal(1,"Accepted oversized row");
    @(negedge clk); start=0;
    // Reset during receive and during pending accumulation.
    start_row(2); exp_valid=1; exp_data=16'h3f80; exp_last=0;
    @(posedge clk); #1; reset_all();
    start_row(1); exp_valid=1; exp_data=16'h3f80; exp_last=1;
    @(posedge clk); #1;
    @(negedge clk); exp_valid=0;
    @(posedge clk); #1; reset_all();
    f=$fopen("rows.txt","r"); if(!f) $fatal(1,"Missing rows");
    while(!$feof(f)) begin
      s=$fscanf(f,"%d %h",n,expected);
      if(s==2) begin
        for(integer i=0;i<n;i=i+1) begin
          s=$fscanf(f,"%h",data[i]); if(s!=1) $fatal(1,"Malformed data");
        end
        start_row(n);
        for(integer i=0;i<n;i=i+1) begin
          if(i%3==1) begin
            exp_valid=0; exp_data=16'h3f80;
            @(posedge clk); #1;
            if(sum_valid !== 0 || dut.received_count !== i) $fatal(1,"Bubble accepted");
            @(negedge clk);
          end
          exp_valid=1; exp_data=data[i]; exp_last=(i==n-1);
          @(posedge clk); #1;
          if(sum_valid !== 0 || ready !== 0) $fatal(1,"Premature complete");
          @(negedge clk);
        end
        exp_valid=0; exp_last=0;
        // Start while busy must be ignored.
        start=1; row_length=1;
        cycles=0;
        while(sum_valid !== 1 && cycles<8*n+4) begin
          @(posedge clk); #1; cycles=cycles+1;
          if(ready !== 0) $fatal(1,"Ready while busy");
        end
        if(sum_valid !== 1 || sum_fp32 !== expected)
          $fatal(1,"Row %0d length %0d got %h expected %h",rows,n,sum_fp32,expected);
        if(rows==0) $display("Example sum FP32 = %h",sum_fp32);
        @(negedge clk); start=0;
        @(posedge clk); #1;
        if(sum_valid !== 0 || ready !== 1) $fatal(1,"Completion pulse/ready failed");
        rows=rows+1;
      end else if(!$feof(f)) $fatal(1,"Malformed header");
    end
    $display("PASS: %0d FP32 adds, %0d row sums; bubbles, reset, invalid lengths, busy start checked",count,rows);
    $finish;
  end
  initial begin #5000000; $fatal(1,"Timeout"); end
endmodule
'''


def main():
    rng = random.Random(20261027)
    special = [0, 1, 0x7fffff, 0x800000, 0x3f800000, 0x33800000,
               0x33800001, 0x3f800001, 0x3fffffff, 0x7f7fffff]
    pairs = [(a,b) for a in special for b in special]
    pairs += [(rng.randrange(0x7f800000), rng.randrange(0x7f800000)) for _ in range(10000)]
    # Explicit ties for odd/even low bits and significand carry.
    pairs += [(a, 0x33800000+d) for a in range(0x3f800000,0x3f800010) for d in (-1,0,1)]
    rows = [[vexp_bf16(encode_bf16(x)) for x in (0,-1,-2)], [0], [0x3f80],
            [0x3f80]*32, [0]*32, [1,0x7f,0x80],
            [0x3f80,0x3380,0x3380], [0x3380,0x3380,0x3f80]]
    for n in (2,8,16,31,32):
        for _ in range(4):
            row = [rng.randint(-80,0) for _ in range(n)]
            maximum = max(row)
            rows.append([vexp_bf16(encode_bf16(x-maximum)) for x in row])
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='softmax_sum_') as directory:
        work=Path(directory)
        vectors = [(a, b, bits(real(a) + real(b))) for a, b in pairs]
        vectors.extend([(0x7f800000, 0, 0x7f800000),
                        (0, 0x7f800001, 0x7fc00000),
                        (0x80000000, 0x7f800000, 0x7fc00000)])
        (work/'adds.txt').write_text(''.join(f'{a:08x} {b:08x} {out:08x}\n'
                                             for a, b, out in vectors))
        text=[]
        for row in rows:
            total=0.0
            for x in row:
                total=real(bits(total+decode_bf16(x)))
            text.append(f'{len(row)} {bits(total):08x}\n')
            text.extend(f'{x:04x}\n' for x in row)
        (work/'rows.txt').write_text(''.join(text))
        (work/'tb.sv').write_text(TB)
        command=['iverilog','-g2012','-s','tb','-o',str(work/'sim'),
                 str(root/'rtl/softmax_sum.sv'),str(root/'rtl/fp32_add_positive.sv'),str(work/'tb.sv')]
        compiled=subprocess.run(command,capture_output=True,text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout+compiled.stderr)
        # Icarus emits benign constant-select sensitivity notices for always_comb.
        warnings=[line for line in compiled.stderr.splitlines() if 'constant selects in always_*' not in line]
        if warnings: print('\n'.join(warnings))
        subprocess.run(['vvp',str(work/'sim')],cwd=work,check=True)


if __name__ == '__main__':
    main()
