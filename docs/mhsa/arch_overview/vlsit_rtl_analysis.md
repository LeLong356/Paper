# MHSA Accelerator (VC707) Architecture Analysis

Date: 2026-10-30. Produced with the `vlsit-rtl-hierarchy-diagram` skill in **architecture mode**: no RTL directory was given, so every block, interface and signal below is taken from the project documents, not from RTL. Nothing here is RTL-proven.

Evidence tags used in every table:
- **[FIXED]** decided by Long (architecture doc `mhsa_accelerator_architecture.md`, 2026-10-30, or earlier thread decisions).
- **[EXISTS]** block already written and verified by Long or Minh (control plane, bram_pp, GEMM core), but the RTL is not in this project, so port names are from the documents.
- **[ASSUMED]** inferred by Claude, to be confirmed.
- **[PROPOSED]** Claude's proposal, not yet accepted.

## 1. Scope and evidence

| Item | Value |
|---|---|
| RTL root | none (architecture mode) |
| Selected top | `GenTop` (SoC top on VC707, handoff §3, §8) |
| Diagram depth | 3 levels: SoC (level 1), accelerator (level 2), DMA / GEMM core / bram_pp (level 3) |
| Documents inspected | `uploads/hearth/c2352bb0…` (= `mhsa_accelerator_architecture.md` v0, 2026-10-30), `dma/dma_v0_4block.md`, `handoff_mhsa_dma.md`, project memory notes on Minh's GEMM core and on `bram_pp` |
| Configuration assumptions | D_MODEL = 768, NUM_HEADS = 12, HEAD_DIM = 64, INT8 data, S = 128 for examples [ASSUMED]; target data bus AXI4 512-bit, v0 debug bus 32-bit |
| Evidence level | document level only |

## 2. Hierarchy

| Depth | Instance | Module | Source | Parent | Status |
|---|---|---|---|---|---|
| 0 | TOP | GenTop | handoff §8 | - | [EXISTS] |
| 1 | u_cpu | VexRiscv | handoff §1 | TOP | [EXISTS] |
| 1 | u_imem | IMEM | handoff §3 | TOP | [EXISTS] |
| 1 | u_dmem | DMEM | handoff §3 | TOP | [EXISTS] |
| 1 | u_dec | dbus_decoder | handoff §1 | TOP | [EXISTS] |
| 1 | u_bridge | Bridge | handoff §1 | TOP | [EXISTS] |
| 1 | u_acc | mhsa_accelerator | arch doc §1 | TOP | [FIXED] structure, RTL not written |
| 2 | u_csr | acc_csr_axil | arch doc §5 | u_acc | AXI4-Lite slave [EXISTS], register map [PROPOSED] |
| 2 | u_ctrl | acc_controller | arch doc §1, §6 | u_acc | [FIXED] role, FSM [PROPOSED] |
| 2 | u_dma | dma_rd | arch doc §2, dma_v0_4block.md | u_acc | [FIXED] read-only 1D, blocks [PROPOSED] |
| 2 | u_bram_pp | bram_pp | memory note 2026-10-27 | u_acc | [EXISTS] (Long) |
| 2 | u_gemm | gemm_core | memory note 2026-10-24 | u_acc | [EXISTS] (Minh) |
| 2 | u_softmax | softmax | memory note 2026-10-23 | u_acc | [EXISTS] (Long) |
| 2 | u_rbuf | qkv_buffer | arch doc §3, §8 item 3 | u_acc | [PROPOSED], location of Q/K/V not decided |
| 3 | (FG) Request FSM | FG of dma_rd | dma_v0_4block.md §1 | u_dma | [PROPOSED] |
| 3 | u_legal | burst_legalizer | dma_v0_4block.md §3 | u_dma | [PROPOSED] |
| 3 | u_ar | ar_fsm | dma_v0_4block.md §4a | u_dma | [PROPOSED] |
| 3 | u_info | burst_info_fifo | dma_v0_4block.md §4c | u_dma | [PROPOSED] |
| 3 | u_r | r_fsm | dma_v0_4block.md §4b | u_dma | [PROPOSED] |
| 3 | u_wr | bram_writer | dma_v0_4block.md §5 | u_dma | [PROPOSED] |
| 3 | u_a_bram | A_bram | memory note 2026-10-24 | u_gemm | [EXISTS] (Minh), instance name assumed |
| 3 | u_load | load_control | memory note 2026-10-24 | u_gemm | [EXISTS] |
| 3 | u_pe | Gemm | memory note 2026-10-24 | u_gemm | [EXISTS] |
| 3 | u_accum | Accumulate_control | memory note 2026-10-24 | u_gemm | [EXISTS] |
| 3 | u_bank0, u_bank1 | bram_6144x256 | memory note 2026-10-27 | u_bram_pp | [EXISTS] |
| 3 | (FG) Bank role FSM, Write steering, Read port | FG of bram_pp | memory note 2026-10-27 | u_bram_pp | [EXISTS] logic, grouping by Claude |

Minh's original core also had `B_bram` (768x256). In this architecture `bram_pp` takes its place outside the core [ASSUMED from the 2026-10-24 advice "B_bram 2-bank ping-pong first"].

## 3. Module functions

| Module | Main function | Status |
|---|---|---|
| VexRiscv | RV32 CPU; writes configuration, starts a task, polls DONE. Never touches tensor data. | [EXISTS] |
| IMEM / DMEM | Program memory (instruction bus only) and data memory (data bus). | [EXISTS] |
| dbus_decoder | Routes data-bus accesses by address: 0x0000_xxxx to DMEM, 0x4xxx_xxxx to the bridge. | [EXISTS] |
| Bridge | Converts one data-bus command at a time into an AXI4-Lite transaction. | [EXISTS] |
| mhsa_accelerator | Multi-head self-attention engine: loads X and Wq/Wk/Wv from DRAM, computes Q, K, V, scores, softmax and S·V. | [FIXED] |
| acc_csr_axil | AXI4-Lite register file: CTRL, STATUS, base addresses, SEQ_LEN, CFG, perf counters. | [PROPOSED] map |
| acc_controller | After START decides what data is needed and when; issues 1D DMA requests per chunk, starts GEMM and softmax, reports task done/error. v0 is sequential (load, then compute). | [FIXED] role |
| dma_rd | Copies one contiguous DRAM region (addr, len) into a BRAM over AXI4 read bursts; no write channel, no stride. | [FIXED] |
| bram_pp | Two 6144x256 banks that swap roles (one written by DMA, one read by GEMM). | [EXISTS] |
| gemm_core | INT8 32x32 tile GEMM (outer product + accumulate), A operand from A_bram, B operand from bram_pp. | [EXISTS] |
| softmax | Row softmax over attention scores. | [EXISTS] |
| qkv_buffer | Holds Q, K, V and scores between stages (3 x S x 768 B; exceeds one bank at S = 128). | [PROPOSED] |

### 3a. Functional groups

| Module | Group | Function |
|---|---|---|
| dma_rd | Request FSM | IDLE, CHECK, WAIT_RDY, RUN, FLUSH, DONE/ERR; captures the request into shadow registers |
| bram_pp | Bank role FSM | wr_bank / rd_bank toggle on wr_done / rd_done, full[1:0] |
| bram_pp | Write steering | routes the write port to the bank selected by wr_bank |
| bram_pp | Read port | sends the read address to the read bank and muxes dout with rd_bank delayed one cycle (synchronous BRAM) |

## 4-6. Interfaces and signal groups

| ID | Interface | Category | Active -> passive | Signals |
|---|---|---|---|---|
| IBUS | Instruction bus | custom (VexRiscv iBus) | u_cpu -> u_imem | cmd_valid, cmd_ready, cmd_pc[31:0]; rsp_valid, rsp_inst[31:0] |
| DBUS | Data bus | custom (VexRiscv dBus) | u_cpu -> u_dec | cmd_valid, cmd_ready, cmd_wr, cmd_address[31:0], cmd_data[31:0], cmd_mask[3:0], cmd_size[1:0]; rsp_ready, rsp_data[31:0] |
| DMB | DMEM port | custom | u_dec -> u_dmem | sel, we, addr, wdata[31:0], mask[3:0]; rdata[31:0] |
| CMD | Bridge command | handshake | u_dec -> u_bridge | cmd_valid, cmd_ready, cmd_wr, cmd_addr[31:0], cmd_data[31:0], cmd_mask[3:0]; rsp_valid, rsp_data[31:0] |
| AXIL | AXI4-Lite | standard (AXI4-Lite, verified) | u_bridge -> u_csr | AW, W, B, AR, R channels |
| CFG | Task configuration | custom | u_csr -> u_ctrl | start [pulse], clr [pulse], x_base, wq_base, wk_base, wv_base, seq_len, cfg |
| STS | Task status | custom | u_ctrl -> u_csr | busy [level], task_done [pulse], task_err [pulse], err_code[2:0], perf_cyc_dma, perf_cyc_cmp, perf_bytes |
| REQ | DMA request | handshake (valid/ready) | u_ctrl -> u_dma | req_valid, req_addr[31:0], req_len_bytes[31:0], req_dst_waddr[12:0], req_dst_sel (proposed); req_ready, dma_done [pulse], dma_error [pulse], dma_err_code[2:0] |
| MAXI | AXI4 read | standard (AXI4 read channels only) | u_dma -> DRAM (MIG) | ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID, ARREADY; RDATA, RRESP, RLAST, RID, RVALID, RREADY |
| BWR | BRAM write port | custom | u_dma -> u_bram_pp | we, waddr[12:0], din[255:0]; wr_ready [level], wr_done [pulse] |
| XWR | X load write port (proposed group) | custom | u_dma -> u_gemm (A_bram) | we, waddr, din[255:0] |
| BRD | BRAM read port | custom | u_gemm -> u_bram_pp | re, raddr[12:0], rd_done [pulse]; dout[255:0], full[1:0] |
| GCT | GEMM control (proposed group) | handshake (start/done) | u_ctrl -> u_gemm | gemm_start [pulse], m, n, k tile counts, out_sel; gemm_done [pulse] |
| SCT | Softmax control (proposed group) | handshake (start/done) | u_ctrl -> u_softmax | smx_start [pulse], row_len; smx_done [pulse] |
| RWR | Result write (proposed group) | custom | u_gemm -> u_rbuf | we, waddr, wdata |
| ORD | Operand read (proposed group) | custom | u_gemm -> u_rbuf | re, raddr; rdata |
| SMX | Softmax buffer access (proposed group) | custom | u_softmax -> u_rbuf | re, raddr, we, waddr, wdata; rdata |
| OUT | Result output (open) | custom | u_rbuf -> outside | not decided (stream, AXI4-Lite read or AXI write) |
| CLK | Clock and reset | custom | external -> all blocks | clk, rst |

Level-3 internal interfaces (DMA, GEMM, bram_pp) are listed in the Interface Table of each level-3 page in the diagram; their signals are copied from `dma_v0_4block.md` and the bram_pp notes.

## 7. Conditional and unresolved items

1. Where X lands (A_bram inside the core, a third bram_pp bank, or a separate buffer) is open (arch doc §8 item 2). Drawn as XWR, proposed.
2. Where Q/K/V live (arch doc §8 item 3). Drawn as `u_rbuf` with a dashed outline.
3. Output O path (arch doc §8 item 7). Drawn as an open stub.
4. Clock: CPU provides the accelerator clock; CDC points are listed in `dma_v0_4block.md` §7. Drawn as one clock domain.
5. Wo and bias, softmax scaling 1/√d, and the QK / SV stages are not detailed in the controller FSM yet.
6. Port names of the existing RTL (VexRiscv, decoder, bridge, GEMM core) come from documents, not from RTL; the instance names are placeholders.

## 8. Diagram mapping

| Page | Frame | Blocks |
|---|---|---|
| 01_LEVEL_1_SOC | TOP (GenTop) | u_cpu, u_imem, u_dmem, u_dec, u_bridge, u_acc |
| 02_LEVEL_2_ACCEL | u_acc (mhsa_accelerator) | u_csr, u_ctrl, u_dma, u_bram_pp, u_gemm, u_softmax, u_rbuf |
| 03_LEVEL_3_DMA | u_dma (dma_rd) | Request FSM, u_legal, u_ar, u_info, u_r, u_wr |
| 03_LEVEL_3_GEMM | u_gemm (gemm_core) | u_a_bram, u_load, u_pe, u_accum |
| 03_LEVEL_3_BRAM_PP | u_bram_pp (bram_pp) | Bank role FSM, Write steering, Read port, u_bank0, u_bank1 |
