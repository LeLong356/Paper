# DMA v0 (u_dma, module dma_rd) Architecture Analysis

Date: 2026-11-03. Produced with the `vlsit-rtl-hierarchy-diagram` skill in **architecture mode**: the RTL of `dma_rd` is not written yet, so no RTL directory exists. Every block, interface and signal below comes from project documents, not from RTL; nothing is RTL-proven.

Evidence tags:
- **[FIXED]** decided by Long: block names, instance names, bus mnemonics and topology of Long's u_dma block diagram (upload of 2026-11-03), read-only 1D DMA with one request at a time (architecture doc 2026-10-30).
- **[PROPOSED]** Claude's proposal in `dma/dma_v0_4block.md` (2026-11-03): signal names, widths, state machines, assumptions A8 to A10.

## 1. Scope and evidence

| Item | Value |
|---|---|
| RTL root | none (architecture mode) |
| Selected top | `dma_rd`, instance `u_dma` inside `mhsa_accelerator` |
| Diagram level | N = 1 (page `01_LEVEL_1`: `u_dma` frame with its five children and one functional group) |
| Documents inspected | Long's u_dma block diagram (2026-11-03), `dma/dma_v0_4block.md` (2026-11-03), `mhsa/spec_latex/main.tex` §u_dma, `mhsa/arch_overview/specs/03_LEVEL_3_DMA.json` |
| Configuration | DATA_W = 32, ADDR_W = 32, MAX_OUT = 1, destination = bram_pp only (no dst demux in v0) |
| Evidence level | document level only |

## 2. Hierarchy

| Depth | Instance | Module | Source | Parent | Status |
|---|---|---|---|---|---|
| 0 | u_dma | dma_rd | dma_v0_4block.md §1 | u_acc | [FIXED] |
| 1 | (FG) Request FSM | own logic of dma_rd | §2 | u_dma | [FIXED] name, [PROPOSED] states |
| 1 | u_legal | burst_legalizer | §3 | u_dma | [FIXED] |
| 1 | u_ar | ar_fsm | §4 | u_dma | [FIXED] |
| 1 | u_info | burst_info_fifo | §5 | u_dma | [FIXED] |
| 1 | u_r | r_fsm | §6 | u_dma | [FIXED] |
| 1 | u_wr | bram_writer | §7 | u_dma | [FIXED] |

## 3. Module functions

| Module | Main function | Key state / datapath | Instance |
|---|---|---|---|
| dma_rd | Copies one contiguous DRAM region into one bram_pp bank over AXI4 read; one request at a time | Request FSM (own logic) plus five children | u_dma |
| burst_legalizer | Splits (address, beats) into bursts of at most 16 beats with no 4 KB crossing | address and remaining-beat registers | u_legal |
| ar_fsm | Issues bursts on the AXI4 AR channel and records them in the info FIFO | 2 states (AR_IDLE, AR_REQ), registered AR payload | u_ar |
| burst_info_fifo | Holds {beats, last} of bursts in flight, depth MAX_OUT | FIFO (1 register + valid in v0) | u_info |
| r_fsm | Receives the AXI4 R channel, checks RLAST/RRESP, forwards beats, drains on error | 3 states (R_IDLE, R_RECV, R_DRAIN), beat counter | u_r |
| bram_writer | Packs eight 32-bit beats into one 256-bit word and writes bram_pp | 224-bit buffer, beat index, word address, word counter | u_wr |

### 3a. Functional groups of dma_rd own logic

| Module | Group | Function | State elements | Outputs |
|---|---|---|---|---|
| dma_rd | Request FSM | Request capture and check, start of legalizer and writer, completion and error reporting | state (IDLE, CHECK, WAIT_RDY, RUN, FLUSH, DONE, ERR), captured request, error code, last-word flag | REQ responses, LOAD, WLD |

Only one functional group exists, so per RHD-082 it is drawn as a single FG block (Long's diagram also shows it as one block).

## 4. Signal analysis

All signal types are [PROPOSED] from `dma_v0_4block.md`; level versus pulse is taken from the described behavior (for example "one cycle" or "held").

| Signal | Src | Dst | Width | Type | Group |
|---|---|---|---|---|---|
| req_valid / req_ready | u_ctrl / Request FSM | Request FSM / u_ctrl | 1 / 1 | ctrl (valid/ready) | REQ |
| req_addr, req_len, req_dst_waddr | u_ctrl | Request FSM | 32, 32, 13 | addr / data | REQ |
| dma_done, dma_err | Request FSM | u_ctrl | 1, 1 | status, pulse | REQ |
| dma_err_code | Request FSM | u_ctrl | 3 | status, level | REQ |
| leg_load, leg_abort | Request FSM | u_legal | 1, 1 | ctrl, pulse | LOAD |
| leg_src, leg_total_beats | Request FSM | u_legal | 32, 30 | addr / data | LOAD |
| bst_valid, bst_addr, bst_beats, bst_last | u_legal | u_ar | 1, 32, 5, 1 | valid/ready payload | BST |
| bst_ready | u_ar | u_legal | 1 | ctrl | BST |
| push, push_beats, push_last | u_ar | u_info | 1, 5, 1 | FIFO push, pulse | PUSH |
| full | u_info | u_ar | 1 | status, level | PUSH |
| ar_done | u_ar | Request FSM | 1 | status, level | ar_done |
| pop | u_r | u_info | 1 | FIFO pop, pulse | POP |
| empty, head_beats, head_last | u_info | u_r | 1, 5, 1 | status / data, level | POP |
| r_idle | u_r | Request FSM | 1 | status, level | RST |
| r_err, r_err_code | u_r | Request FSM | 1, 3 | status, pulse / level | RST |
| beat_valid, beat_data, beat_last | u_r | u_wr | 1, 32, 1 | valid/ready payload | BEAT |
| beat_ready | u_wr | u_r | 1 | ctrl | BEAT |
| wr_load, wr_dst, wr_len_words | Request FSM | u_wr | 1, 13, 13 | ctrl pulse / addr / data | WLD |
| wr_bank_ready, wr_last_done | u_wr | Request FSM | 1, 1 | status level / pulse | WLD |
| ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID / ARREADY | u_ar / DRAM | DRAM / u_ar | 32, 8, 3, 2, 1, 1 / 1 | AXI4 AR | AXAR |
| RDATA, RRESP, RLAST, RID, RVALID / RREADY | DRAM / u_r | u_r / DRAM | 32, 2, 1, 1, 1 / 1 | AXI4 R | AXR |
| we, waddr, din / wr_ready, wr_done | u_wr / u_bram_pp | u_bram_pp / u_wr | 1, 13, 256 / 1, 1 | BRAM write | BWR |
| clk, rst | external | all blocks | 1, 1 | clock, reset | CLK |

## 5. Interface classification

| Interface | Category | Active -> passive | Notes |
|---|---|---|---|
| REQ | handshake (valid/ready) | u_ctrl -> Request FSM | done/err returned in the same group |
| LOAD | handshake (load pulse) | Request FSM -> u_legal | |
| BST | handshake (valid/ready) | u_legal -> u_ar | |
| PUSH | handshake (FIFO push) | u_ar -> u_info | |
| POP | handshake (FIFO pop) | u_r -> u_info | |
| BEAT | handshake (valid/ready) | u_r -> u_wr | CDC point later (async FIFO) |
| WLD | handshake (load/done) | Request FSM -> u_wr | |
| RST | custom | u_r -> Request FSM | name clashes visually with reset; open item O-1 |
| ar_done | custom (single signal) | u_ar -> Request FSM | |
| AXAR | standard protocol-like (AXI4 AR) | u_ar -> DRAM | ARLOCK, ARCACHE, ARPROT, ARQOS are constants (main.tex) and not drawn |
| AXR | standard protocol-like (AXI4 R) | DRAM -> u_r | |
| BWR | custom | u_wr -> u_bram_pp | |
| CLK | custom (clock/reset) | external -> all | distribution tree |

## 6. Signal groups

| Mnemonic | Interface name | Catalog match | Endpoints |
|---|---|---|---|
| REQ | DMA request | (proposed group) DMA request | u_ctrl, Request FSM |
| LOAD | Legalizer load | (custom) | Request FSM, u_legal |
| BST | Burst descriptor | valid/ready | u_legal, u_ar |
| PUSH | Info FIFO push | FIFO push | u_ar, u_info |
| POP | Info FIFO pop | FIFO pop | u_r, u_info |
| BEAT | Beat stream | valid/ready | u_r, u_wr |
| RST | Read status | (custom) | u_r, Request FSM |
| ar_done | Address side done | single signal | u_ar, Request FSM |
| WLD | Writer load and done | (custom) | Request FSM, u_wr |
| AXAR | AXI4 read address channel | AXI4 | u_ar, DRAM |
| AXR | AXI4 read data channel | AXI4 | u_r, DRAM |
| BWR | BRAM write port | memory write | u_wr, u_bram_pp |
| CLK | Clock and reset | clock/reset | external, all blocks |

Ungrouped signals: none.

## 7. Conditional and unresolved items

- O-1: mnemonic `RST` (read status) may be confused with reset; kept as in Long's diagram.
- O-2: A8 to A10 of `dma_v0_4block.md` (ar_done as a combinational level, abort via LOAD, wr_ready forwarded by u_wr through WLD) are proposals needed to keep Long's topology; to be confirmed.
- O-3: main.tex adds a dst demux (BWR or XWR), 14-bit waddr and DATA_W = 512; these are not part of v0 and are not drawn.

## 8. Diagram mapping

Page `01_LEVEL_1`: frame u_dma (dma_rd) with blocks Request FSM (FG of dma_rd), u_legal, u_ar, u_info, u_r, u_wr; internal connectors LOAD, BST, PUSH, POP, BEAT, RST, ar_done, WLD; boundary stubs REQ, AXAR, AXR, BWR; distribution tree CLK.
