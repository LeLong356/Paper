# Handoff — RISC-V-controlled MHSA accelerator (VC707): control plane done, DMA v0 next

Written for a fresh agent picking up this project. Read sections 1–3 first; section 7 is the spec for the immediate task (DMA v0).

---

## 1. Context

- **User**: Vietnamese Computer Engineering student (HCMUT). Writes in informal Vietnamese ("bồ" = you; the assistant refers to itself as "tui"). Reply in Vietnamese, same register.
- **Project**: RISC-V controlled Multi-Head Self-Attention (MHSA) accelerator on FPGA — Xilinx **VC707** (xc7vx485tffg1761-2). The user owns **data movement**: RISC-V ↔ accelerator interface, DMA off-chip → on-chip, buffers, protocol to the PE array.
- **Architecture (fixed by user)**:
  - Off-chip **DRAM** holds weights/activations. On-chip data is loaded into **BRAM**.
  - **IMEM / DMEM** only hold the RISC-V program and control data — they never hold tensor data.
  - Control path: VexRiscv dBus → decoder → {DMEM, Bridge → AXI4-Lite slave (accelerator registers)}.
  - Data path (to build): DMA engine, AXI4 burst, DRAM ↔ BRAM.

## 2. How the user wants to be supported (important)

- **The user writes core RTL themselves** ("đừng gen code, để tui tự code cho hiểu kiến trúc"). Give diagrams, state lists, signal tables, pitfall lists; then **review their code with a numbered error list**. Do NOT hand over finished core RTL (slave, bridge, DMA FSM).
- **Do write for them** the non-conceptual, repetitive parts when asked ("bạn viết dùm tôi"): long port lists, wiring/top-levels, testbenches, firmware, README, WaveDrom.
- Prefers **images/diagrams over text**; works **test each piece, then integrate**.
- Weak in Python — explain basics if Python appears.
- Occasionally pastes messages from unrelated projects (e.g. "min max fairness"); treat as noise unless asked.

## 3. Current state

Control plane is **functionally verified at every level and implemented**:

| Level | Result |
|---|---|
| `tb_slave_read.sv` | 28/28 |
| `tb_slave_write.sv` | 53/53 |
| `tb_integration.sv` (bridge+slave) | 87/87 (write 5 cycles, read 4) |
| `tb_soc.sv` | 5/5 |
| `tb_gentop.sv` (VexRiscv + firmware) | 8/8 |

Implementation on VC707, 200 MHz constraint: LUT 1061 (0.35%), FF 1241, BRAM 17 (1.65%), WNS +0.548 ns, TNS 0, Fmax ≈ 224 MHz, 0.312 W (vectorless).

Full details, memory map and WaveDrom diagrams: `/mnt/user-data/outputs/repo/README.md` and `/mnt/user-data/outputs/repo/docs/wavedrom/` (do not re-derive).

**Memory map**: IMEM 0x8000_0000–0x8000_FFFF (iBus only), DMEM 0x0000_0000–0x0000_FFFF, accelerator 0x4xxx_xxxx (16 regs at 0x4000_0000–0x4000_003C, `ACC_BASE_NIBBLE=4'h4`).

## 4. Fixed decisions and hardware constraints

- **Harvard-pure SoC**: IMEM is wired to iBus only → no `.data` copy, `.rodata` unreadable via dBus. Globals must be assigned at runtime inside `main()`. The current `firmware/start.S` is the **no-`.data`** version — treat it as authoritative. (Optional: add `ASSERT(__data_start == __data_end, ...)` to `link.ld`.)
- VexRiscv: DBus is one transaction at a time; `cmd_payload_mask` pre-shifted by address[1:0]; reset is active-high (`ARESETn = ~reset`); reset vector 0x80000000.
- VC707 clock is a **differential 200 MHz** (E19/E18) → board bring-up needs a clocking wizard / IBUFDS for a single-ended `clk`. Reset needs debounce (`firmware/debounce.sv`). LED IOSTANDARD is LVCMOS18.
- XDC for timing runs: one line, `create_clock -name clk -period 5.000 [get_ports clk]`. Do not import the full master XDC (ports don't match; also remove the gist `vc707.xdc` from the project).
- Synthesis note: logic is trimmed if there is no observable output → keep an `LED[7:0]` that captures the last accelerator write data (hierarchical refs like `u_slave.mem[15]` are simulation-only).

## 5. Pitfalls already hit (don't repeat)

- AXI payload must be valid **together with** VALID and held until handshake (user once assigned payload after the handshake).
- `cmd_ready` must reset to 1 (reset 0 deadlocks the bridge).
- Write path: keep AW/W handling as independent `if` blocks (an else-if chain loses simultaneous AW/W); commit when `aw_done && w_done && !BVALID`; BVALID resets to 0.
- `AWPROT/ARPROT` must be driven by the master (Bridge currently leaves them undriven).
- Assistant's past mistakes to avoid: claiming A9 is AXI4-Lite (it is B1.1; ARM IHI 0022), suggesting hierarchical refs for synthesis, writing a `.data`-copying `start.S` without checking IMEM wiring.

## 6. Open items

| # | Item | Status |
|---|---|---|
| 1 | Nested git repo: folder "CPU + AXI4-Lite" is an embedded repo inside the parent → `git rm --cached "CPU + AXI4-Lite"` (quote: spaces), then separate repos or merge | **unresolved — ask what the parent folder holds** |
| 2 | `Bridge.sv` cleanup: `assign AWPROT=3'b000; assign ARPROT=3'b000;`, remove unused vars, module name `bridge` | unconfirmed |
| 3 | Per-module utilization for `slave`/`bridge`/`decoder` (keep hierarchy or OOC synth `-mode out_of_context`) | not done |
| 4 | 2 critical DRC warnings (likely unconstrained I/O, harmless for reports) | unchecked |
| 5 | Optional slave improvements: remove 1-cycle commit delay, SLVERR on bad address, bridge `rsp_ready` only on reads | optional |
| 6 | Copy `tb_*.sv` into repo `tb/`, export WaveDrom SVGs | optional |
| 7 | **DMA v0** | **next task** |
| 8 | Later: real register map (START/DONE, Q/K/V base addresses, tiling cfg), tile-size computation (needs seq_len, heads, head_dim, precision e.g. W4A8, BRAM budget minus the 17 already used), MIG DDR3 + clock-domain crossing, UART | future |

## 7. DMA v0 — spec to start from

Goal: a basic DMA engine, **not yet** tied to MHSA tile sizes.

- **Scope v0**: read-only (DRAM → BRAM), 32-bit data, AXI4 **INCR** bursts of 16 beats, source address and length aligned, no 4 KB-crossing handling yet (document the constraint; split bursts at 4 KB boundaries in v1).
- **AXI4 read channels**: AR (`ARLEN = beats−1`, `ARSIZE = 3'b010`, `ARBURST = INCR`, `ARID`), R (`RLAST` marks the final beat; `RRESP` check).
- **Suggested FSM**: IDLE → AR (issue burst) → R (accept beats, write to BRAM, count) → next burst or DONE/ERR.
- **Counters**: remaining bytes/beats, current address; optionally cycle and byte counters for later roofline measurements.
- **Later**: write channel (BRAM read has 1-cycle latency), frontend registers inside the AXI4-Lite slave (SRC, DST, LEN, START, DONE/ERR), AGU / hardware loop, ping-pong buffers.
- **Workflow**: the user writes the port list and the FSM; the assistant writes the testbench with an **AXI4 burst memory model** (random RVALID gaps, first-beat delay, RLAST check) in parallel, then reviews the user's code with a numbered list.
- **Pitfalls to brief the user on**: payload held until handshake; RLAST sanity; AXI ID matching; never cross 4 KB; backpressure from BRAM write; reset values of ready/valid.

## 8. Files created (all under `/mnt/user-data/outputs/`)

- Testbenches: `tb_slave_read.sv`, `tb_slave_write.sv`, `tb_integration.sv`, `tb_soc.sv`, `tb_gentop.sv`
- RTL (assistant-written wiring): `GenTop.sv`, `dbus_decoder_full.sv`, `dbus_decoder.sv` (skeleton)
- Firmware `firmware/`: `start.S`, `link.ld` (IMEM 0x80000000 64K, DMEM 0x0 64K, stack 2 KB), `main.c`, `Makefile` (PREFIX `riscv64-unknown-elf-`), `bin2hex.py`, `vc707.xdc`, `debounce.sv`
- Docs: `repo/README.md`, `repo/docs/wavedrom/1_write_dbus_bridge_slave.json`, `2_read_dbus_bridge_slave.json`, `3_slave_w_before_aw.json`, `Data_Movement_MHSA_Accelerator_Ban_Dich.md` (Vietnamese translation of the research report on MHSA data movement)
- The user's own RTL (`AXI4_lite_slave.sv`, `Bridge.sv`, `decoder.sv`, `DMEM.sv`, `IMEM.sv`, `GenTop.sv`, `VexRiscv.v`) lives in `/mnt/user-data/uploads/` — **always re-read the latest version before reviewing or editing**.

## 9. References

- DMA: iDMA (pulp-platform; Benz et al.) frontend/midend/backend; alexforencich/verilog-axi (`axi_ram`, `axi_dma_rd/wr`, `axi_cdma`); AMD PG021 AXI DMA (Simple mode registers).
- AXI: ARM IHI 0022 (AXI4-Lite = Part B/B1.1).
- Accelerator/dataflow: TileFlow (MICRO'23); two BKU theses (HK251 DAGD1, HK252 DATN, Lâm Nhi et al.).
- The user's four notes (`dma_and_tiling_strategies`, `on_chip_memory_hierarchy`, `dataflow_architectures`, `weight_streaming_vs_caching`, `.md`) are background reading — **verify claims before relying on them**.

## 10. Suggested skills

- `how-to` — walkthrough-style guidance for AXI DMA learning path.
- `vlsit-wavedrom-waveform` — burst waveforms (AR/R with RLAST, backpressure).
- `vlsit-asic-ip-microspec` — a concise micro-spec for DMA v0 before the user codes it.
- `vlsit-rtl-hierarchy-diagram` — block diagram of DMA + AXI-Lite frontend + BRAM.
- `read-doc` / `paper-lookup` / `pdf-reading` — iDMA paper, PG021, TileFlow.
- `scientific-writing` — if the report/README needs expansion.
- **Do NOT use** `vlsit-rtl-generator` for core RTL — the user wants to write it.

## 11. First action for the next session

1. Ask (briefly) whether the nested git repo and the `Bridge.sv` cleanup are done.
2. Ask whether the user is ready to write the DMA v0 port list; meanwhile start the AXI4 burst-memory testbench.
