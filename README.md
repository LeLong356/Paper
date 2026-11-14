# FPGA softmax core

The [softmax top module](rtl/softmax.sv) accepts a row of signed INT32 scores and emits one INT8 probability code per score, in input order. It subtracts the row maximum in INT33, approximates each exponential in BF16, accumulates the sum in FP32 and divides each exponential by that sum. The final stage scales each probability by 127 and rounds to the nearest integer with ties to even. Decode an output code `q` as `q / 127`.

- [RTL specification](docs/softmax/SOFTMAX_SPEC.md) — port list, row protocol, datapath, seven-state controller and verification results.
- [FPGA power, performance and area report](docs/softmax/PPA_Report.md) — synthesis resources, routed timing, estimated power and simulated row latency for capacities of 32, 64, 128 and 256.

## Processing one row

Set `MAX_LENGTH` at synthesis time (default 256). With reset released, present `start` and a `row_length` from 1 through `MAX_LENGTH` when `ready` is high. Each subsequent rising edge with both `in_valid` and `in_ready` transfers one score. Capture each code on `out_valid`. The core asserts `out_last` and `done` with the final valid code. The consumer must accept every valid output.

## Repository layout

| Directory | Contents |
|---|---|
| [rtl/](rtl/) | Synthesizable SystemVerilog sources. Select `softmax` as the synthesis top. |
| [tb/](tb/) | SystemVerilog testbenches for the core and its arithmetic blocks. |
| [sim/](sim/) | Python reference models, unit tests, simulation drivers and an optional comparison against GEMM vectors. |
| [docs/softmax/](docs/softmax/) | Architecture and FPGA reports with their figures. |
| [docs/vexp/](docs/vexp/) | VEXP architecture and simulation images. |

## Run verification

From the repository root, use Python 3 and Icarus Verilog (`iverilog` and `vvp` on PATH). The drivers use the Python standard library and create temporary simulation files.

```sh
python3 sim/verify_softmax.py
python3 -m unittest discover -s sim
python3 sim/verify_vexp.py
```

The first command checks the S = 32 testbench against the reference, including internal FP32 quotients, INT8 outputs, reset and final-element signaling. For input `[2, 1, 0]`, the expected RTL codes are `[84, 31, 11]`. The standalone VEXP regression checks all 65,536 BF16 encodings and measures approximation error over three input ranges. The specification lists the block-level drivers.

## Mathematical reference

`sim/softmax_golden.py` computes one floating-point row with `math.exp`. Supply finite inputs and a finite positive scale. The default scale is 1, matching the RTL input convention. Include any application-specific attention scaling in the supplied scale.

```sh
python3 sim/softmax_golden.py 2 1 0
python3 sim/softmax_golden.py --scale 0.0078125 256 128 0
```

Both examples produce probabilities of approximately 0.66524, 0.24473 and 0.09003. The separate fixed-point model in `sim/softmax_fixed.py` explores lookup-table configurations. Use `sim/verify_softmax.py` for bit-level comparison with the implemented core.
