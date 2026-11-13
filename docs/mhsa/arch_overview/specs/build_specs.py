"""Build one generator spec per page for the MHSA architecture overview."""
import json, os, sys

SHA = "D1631ACF98A920526B235E8970FEDDC9305EA2F0D6A35C6529CD220D62AFABB6"
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
DOC = "arch doc"          # mhsa_accelerator_architecture.md v0 (2026-10-30)


def w(lbl):
    v = max(len(x) for x in lbl) * 9 + 24
    return -(-v // 20) * 20


def blk(key, label, row, col, func, src, width=None):
    return {"key": key, "label": label, "width": width or w(label), "row": row, "col": col,
            "row_name": f"{label[0]} {label[1]}", "function": func, "source": src}


def con(i, s, ss, d, ds):
    return {"id": i, "src": s, "src_side": ss, "dst": d, "dst_side": ds}


def ext(i, b, side, d, text, pos=0, pad=False):
    e = {"id": i, "block": b, "side": side, "dir": d, "pos": pos, "text": text}
    if pad:
        e["pad"] = True
    return e


def itf(i, name, cat, act, sig):
    return {"id": i, "name": name, "category": cat, "active": act, "signals": sig}


def spec(frame, frame_func, frame_src, blocks, conns, exts, sinks, itfs, note):
    return {"library_sha256": SHA, "layout": {"gap_h": 90, "gap_v": 80, "margin": 40, "block_h": 60},
            "top": {"frame_label": frame, "block_label": frame, "block_row": [" ".join(frame), frame_func, frame_src]},
            "frame_row": [" ".join(frame) + " frame", frame_func, frame_src],
            "frame_interfaces": [e["id"] for e in exts],
            "blocks": blocks, "connectors": conns, "externals": exts,
            "nets": [{"entry": "CLK", "sinks": sinks}] if sinks else [],
            "interfaces": itfs, "legend_note": note}


NOTE = ("Architecture mode: drawn from project documents, not from RTL. [EXISTS] = block already written; "
        "[FIXED] = decided by Long; [PROPOSED] = Claude proposal; dashed outline = location or existence not decided. "
        "FG = functional group of the module own logic. [pulse] = one-cycle signal, [level] = held value.")
CLKI = itf("CLK", "Clock and reset", "custom", "external -> all blocks (distribution tree)", "clk, rst (one clock domain assumed in v0)")

# ---------------------------------------------------------------- page 1: SoC
p1 = spec(["TOP", "(GenTop)"],
          "[EXISTS] VC707 SoC top. A VexRiscv CPU runs firmware from an instruction memory and reaches a data memory and the accelerator register window through an address decoder; the accelerator window is converted to AXI4-Lite by a bridge. The MHSA accelerator is the only block that reads DRAM (MIG DDR3, external) for tensor data; the CPU never touches tensor data.",
          "handoff_mhsa_dma.md 1, 3; arch doc 1",
          [blk("CPU", ["u_cpu", "(VexRiscv)"], 0, 0,
               "[EXISTS] RV32 CPU. It fetches instructions on its instruction bus and issues one data-bus transaction at a time. In this system its firmware only writes the task configuration into the accelerator registers, sets START and polls the DONE flag; it never moves tensor data.",
               "handoff 1, 4"),
           blk("DEC", ["u_dec", "(dbus_decoder)"], 0, 1,
               "[EXISTS] Address decoder of the data bus. Accesses to the low 64 KiB go to the data memory; accesses to the 0x4xxx_xxxx window go to the bridge. It returns the response of the selected target to the CPU.",
               "handoff 1, 3"),
           blk("BRG", ["u_bridge", "(Bridge)"], 0, 2,
               "[EXISTS] Converts a single data-bus command into one AXI4-Lite read or write transaction and returns the read data or write response. Verified at 5 cycles per write and 4 per read.",
               "handoff 3, 5"),
           blk("ACC", ["u_acc", "(mhsa_accelerator)"], 0, 3,
               "[FIXED] Multi-head self-attention engine (D = 768, 12 heads of 64, INT8, assumed). After START its own controller requests contiguous chunks (X, then Wq, Wk, Wv in three 768 x 256 chunks each) from DRAM through a read-only DMA, runs the tile GEMM core and the softmax unit, and reports DONE or ERR in its status register. v0 is sequential: load, then compute. Expanded on page 02.",
               "arch doc 1-7"),
           blk("IMEM", ["u_imem", "(IMEM)"], 1, 0,
               "[EXISTS] 64 KiB instruction memory at 0x8000_0000, wired to the instruction bus only (Harvard), so the firmware has no initialised data section.",
               "handoff 3, 4"),
           blk("DMEM", ["u_dmem", "(DMEM)"], 1, 1,
               "[EXISTS] 64 KiB data memory at 0x0000_0000 for stack and control variables; it never holds tensor data.",
               "handoff 1, 3")],
          [con("IBUS", "CPU", "B", "IMEM", "T"), con("DBUS", "CPU", "R", "DEC", "L"),
           con("DMB", "DEC", "B", "DMEM", "T"), con("CMD", "DEC", "R", "BRG", "L"),
           con("AXIL", "BRG", "R", "ACC", "L")],
          [ext("MAXI", "ACC", "B", "out", ["MAXI", "AXI4 read (AR, R)", "to DRAM (MIG DDR3)"]),
           ext("CLK", "ACC", "T", "in", ["CLK", "clk, rst"])],
          [{"id": "C1", "block": "CPU", "side": "T", "pos": 0}, {"id": "C2", "block": "DEC", "side": "T", "pos": 0},
           {"id": "C3", "block": "BRG", "side": "T", "pos": 0}, {"id": "C4", "block": "IMEM", "side": "L", "pos": 0},
           {"id": "C5", "block": "DMEM", "side": "R", "pos": 0}],
          [itf("IBUS", "Instruction bus", "custom (VexRiscv iBus)", "u_cpu -> u_imem", "cmd_valid, cmd_ready, cmd_pc[31:0]; u_imem -> u_cpu: rsp_valid, rsp_inst[31:0]"),
           itf("DBUS", "Data bus", "custom (VexRiscv dBus)", "u_cpu -> u_dec", "cmd_valid, cmd_ready, cmd_wr, cmd_address[31:0], cmd_data[31:0], cmd_mask[3:0], cmd_size[1:0]; u_dec -> u_cpu: rsp_ready, rsp_data[31:0]"),
           itf("DMB", "DMEM port", "custom", "u_dec -> u_dmem", "sel, we, addr, wdata[31:0], mask[3:0]; u_dmem -> u_dec: rdata[31:0]"),
           itf("CMD", "Bridge command", "handshake (valid/ready)", "u_dec -> u_bridge", "cmd_valid, cmd_ready, cmd_wr, cmd_addr[31:0], cmd_data[31:0], cmd_mask[3:0]; u_bridge -> u_dec: rsp_valid, rsp_data[31:0]"),
           itf("AXIL", "AXI4-Lite", "standard (AXI4-Lite)", "u_bridge -> u_acc", "AWADDR, AWPROT, AWVALID, AWREADY, WDATA, WSTRB, WVALID, WREADY, BRESP, BVALID, BREADY, ARADDR, ARPROT, ARVALID, ARREADY, RDATA, RRESP, RVALID, RREADY"),
           itf("MAXI", "AXI4 read", "standard (AXI4, read channels only)", "u_acc -> DRAM", "ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID, ARREADY; DRAM -> u_acc: RDATA (32 bit debug, 512 bit target), RRESP, RLAST, RID, RVALID, RREADY"),
           CLKI], NOTE)

# ---------------------------------------------------------------- page 2: accelerator
p2 = spec(["u_acc", "(mhsa_accelerator)"],
          "[FIXED] The CPU only configures and starts. The controller then owns the schedule: for each chunk it issues one 1D request (address, length, destination) to the read-only DMA, waits for its completion, starts the GEMM core on the loaded chunk, and moves on (v0 sequential: no overlap of load and compute). Weights Wq, Wk, Wv are 768 x 768 each and arrive in three 768 x 256 chunks, one chunk filling exactly one bram_pp bank. Weights are never written back to DRAM.",
          "arch doc 1-6",
          [blk("CSR", ["u_csr", "(acc_csr_axil)"], 0, 0,
               "[EXISTS slave / PROPOSED map] AXI4-Lite slave holding the task registers: CTRL (self-clearing START, CLR), STATUS (BUSY, sticky DONE and ERR with an error code, write-one-to-clear), DRAM base addresses of X, Wq, Wk, Wv, sequence length, head configuration and three performance counters. Configuration writes are blocked while busy. DONE reflects the end of the whole task, not of one chunk.",
               "arch doc 5"),
           blk("CTRL", ["u_ctrl", "(acc_controller)"], 0, 1,
               "[FIXED role / PROPOSED FSM] Task sequencer. On START it loads X, then for each weight matrix and each of its three chunks requests the chunk from the DMA, waits for the chunk-done pulse, starts the GEMM core and waits for it; then runs the score, softmax and score x V stages and the output step. Any DMA error or a watchdog timeout ends the task in ERR. It also counts cycles spent waiting for DMA and computing.",
               "arch doc 1, 6"),
           blk("SMX", ["u_softmax", "(softmax)"], 0, 2,
               "[EXISTS] Row softmax over the attention scores of one head; started by the controller, reads score rows and writes probabilities back. The 1/sqrt(d) scale is not yet placed (open).",
               "memory 2026-10-23"),
           blk("DMA", ["u_dma", "(dma_rd)"], 1, 0,
               "[FIXED] Read-only DMA. Accepts one request at a time (no queue), splits it into legal AXI4 INCR bursts (at most 16 beats, no 4 KB crossing), receives the data, packs beats into 256-bit words and writes them to the destination BRAM; reports chunk done or error. No stride support: software lays out every chunk contiguously in DRAM. Expanded on page 03_LEVEL_3_DMA.",
               "arch doc 2; dma_v0_4block.md"),
           blk("BPP", ["u_bram_pp", "(bram_pp)"], 1, 1,
               "[EXISTS] Ping-pong weight buffer: two banks of 6144 x 256 bit (196 608 B = one 768 x 256 INT8 chunk each). One bank is written by the DMA while the other is read by the GEMM core; the roles swap when a write and a read are complete. Expanded on page 03_LEVEL_3_BRAM_PP.",
               "memory 2026-10-27"),
           blk("GEMM", ["u_gemm", "(gemm_core)"], 2, 1,
               "[EXISTS] Minh's INT8 tile GEMM (32 x 32 tile). The A operand (activation) comes from its internal A buffer, the B operand (weight chunk) from bram_pp; outer-product, accumulate and load stages overlap at about 33 cycles per tile pair. Only one output tile is accumulated at a time, so k is the innermost loop. Expanded on page 03_LEVEL_3_GEMM.",
               "memory 2026-10-24"),
           blk("RBUF", ["u_rbuf", "(qkv_buffer)"], 2, 2,
               "[PROPOSED, dashed] Storage for Q, K, V (each S x 768 B) and the score rows between stages. Its location (on-chip BRAM, cache or write-back to DRAM) is not decided; 3 x 98 304 B at S = 128 already exceeds one bank.",
               "arch doc 3, 8 item 3") | {"dashed": True}],
          [con("CFG", "CSR", "R", "CTRL", "L"), con("STS", "CTRL", "L", "CSR", "R"),
           con("REQ", "CTRL", "B", "DMA", "T"), con("SCT", "CTRL", "R", "SMX", "L"),
           con("GCT", "CTRL", "R", "GEMM", "T"),
           con("BWR", "DMA", "R", "BPP", "L"), con("BRD", "GEMM", "T", "BPP", "B"),
           con("XWR", "DMA", "B", "GEMM", "L"),
           con("RWR", "GEMM", "R", "RBUF", "L"), con("ORD", "GEMM", "R", "RBUF", "L"),
           con("SMX", "SMX", "B", "RBUF", "T")],
          [ext("AXIL", "CSR", "L", "in", ["AXIL", "AXI4-Lite slave"]),
           ext("MAXI", "DMA", "L", "out", ["MAXI", "AXI4 read", "to DRAM"]),
           ext("OUT", "RBUF", "R", "out", ["OUT", "result O (open)"]),
           ext("CLK", "CSR", "T", "in", ["CLK", "clk, rst"])],
          [{"id": "C1", "block": "CTRL", "side": "T", "pos": 0}, {"id": "C2", "block": "SMX", "side": "R", "pos": 0},
           {"id": "C3", "block": "RBUF", "side": "B", "pos": 0}, {"id": "C4", "block": "DMA", "side": "L", "pos": -20},
           {"id": "C5", "block": "BPP", "side": "R", "pos": 0}, {"id": "C6", "block": "GEMM", "side": "B", "pos": 0}],
          [p1["interfaces"][4],
           itf("CFG", "Task configuration", "custom", "u_csr -> u_ctrl", "start [pulse], clr [pulse], x_base[31:0], wq_base[31:0], wk_base[31:0], wv_base[31:0], seq_len, cfg (num_heads, head_dim, mode)"),
           itf("STS", "Task status", "custom", "u_ctrl -> u_csr", "busy [level], task_done [pulse], task_err [pulse], err_code[2:0], perf_cyc_dma[31:0], perf_cyc_cmp[31:0], perf_bytes[31:0]"),
           itf("REQ", "DMA request", "handshake (valid/ready)", "u_ctrl -> u_dma", "req_valid, req_addr[31:0], req_len_bytes[31:0], req_dst_waddr[12:0], req_dst_sel (proposed); u_dma -> u_ctrl: req_ready, dma_done [pulse], dma_error [pulse], dma_err_code[2:0]"),
           itf("MAXI", "AXI4 read", "standard (AXI4, read channels only)", "u_dma -> DRAM", "ARADDR, ARLEN, ARSIZE, ARBURST, ARID, ARVALID, ARREADY; DRAM -> u_dma: RDATA, RRESP, RLAST, RID, RVALID, RREADY"),
           itf("BWR", "BRAM write port", "custom", "u_dma -> u_bram_pp", "we, waddr[12:0], din[255:0]; u_bram_pp -> u_dma: wr_ready [level], wr_done [pulse]"),
           itf("XWR", "X load write port (proposed group)", "custom", "u_dma -> u_gemm", "we, waddr, din[255:0] (destination of X still open)"),
           itf("BRD", "BRAM read port", "custom", "u_gemm -> u_bram_pp", "re, raddr[12:0], rd_done [pulse]; u_bram_pp -> u_gemm: dout[255:0], full[1:0]"),
           itf("GCT", "GEMM control (proposed group)", "handshake (start/done)", "u_ctrl -> u_gemm", "gemm_start [pulse], m_tiles, n_tiles, k_tiles, out_sel; u_gemm -> u_ctrl: gemm_done [pulse]"),
           itf("SCT", "Softmax control (proposed group)", "handshake (start/done)", "u_ctrl -> u_softmax", "smx_start [pulse], row_len; u_softmax -> u_ctrl: smx_done [pulse]"),
           itf("RWR", "Result write (proposed group)", "custom", "u_gemm -> u_rbuf", "we, waddr, wdata"),
           itf("ORD", "Operand read (proposed group)", "custom", "u_gemm -> u_rbuf", "re, raddr; u_rbuf -> u_gemm: rdata"),
           itf("SMX", "Softmax buffer access (proposed group)", "custom", "u_softmax -> u_rbuf", "re, raddr, we, waddr, wdata; u_rbuf -> u_softmax: rdata"),
           itf("OUT", "Result output (open)", "custom", "u_rbuf -> outside", "not decided: stream port, AXI4-Lite read or AXI4 write channel"),
           CLKI], NOTE)

# ---------------------------------------------------------------- page 3: DMA
p3 = spec(["u_dma", "(dma_rd)"],
          "[PROPOSED blocks] Read-only DMA built from four blocks plus a small request FSM. The FSM checks and captures one request, the legalizer turns it into legal bursts, the AR FSM issues them, the info FIFO remembers each burst in flight (depth MAX_OUT = 1 in v0), the R FSM checks and forwards the beats, and the writer packs eight 32-bit beats into one 256-bit word for bram_pp. On a response error the R side drains all outstanding beats before reporting.",
          "dma_v0_4block.md 1-5",
          [blk("FSM", ["Request FSM", "(FG of dma_rd)"], 1, 0,
               "IDLE, CHECK, WAIT_RDY, RUN, FLUSH, DONE or ERR. CHECK rejects a length that is zero or not a multiple of 32 B, or a destination that overflows the bank. WAIT_RDY waits for a free bank, then loads the legalizer and the writer. FLUSH waits until all bursts are issued, none is in flight and the last word is written, then emits a one-cycle done or error.",
               "dma_v0_4block.md 1"),
           blk("LEG", ["u_legal", "(burst_legalizer)"], 0, 0,
               "Splits (address, total beats) into bursts of min(16, beats left, beats to the next 4 KB boundary); holds only the current address and the remaining beat count and advances them only on a handshake.",
               "dma_v0_4block.md 3"),
           blk("AR", ["u_ar", "(ar_fsm)"], 0, 1,
               "Drives the AXI4 address channel: holds address and length (beats minus one) stable until accepted, never lowers the valid early, and records each accepted burst in the info FIFO while fewer than MAX_OUT bursts are in flight.",
               "dma_v0_4block.md 4a"),
           blk("INFO", ["u_info", "(burst_info_fifo)"], 0, 2,
               "Small FIFO of {beats, last} per burst in flight; depth MAX_OUT (1 in v0, a register with a valid flag). Its occupancy is the in-flight burst count.",
               "dma_v0_4block.md 4c"),
           blk("R", ["u_r", "(r_fsm)"], 1, 1,
               "Accepts read data while the writer is ready, counts beats against the expected burst length, checks the last flag and the response code, pops the info FIFO at the end of a burst, and on an error keeps accepting and discarding beats until all bursts in flight are drained.",
               "dma_v0_4block.md 4b"),
           blk("WR", ["u_wr", "(bram_writer)"], 1, 2,
               "Packs eight 32-bit beats into one 256-bit word (first beat in the low bits), writes it at the current word address and increments it; counts words independently of burst boundaries and signals when the last word is written.",
               "dma_v0_4block.md 5")],
          [con("LOAD", "FSM", "T", "LEG", "B"), con("BST", "LEG", "R", "AR", "L"),
           con("PUSH", "AR", "R", "INFO", "L"), con("POP", "R", "R", "INFO", "B"),
           con("BEAT", "R", "R", "WR", "L"), con("RST", "R", "L", "FSM", "R"),
           con("ar_done", "AR", "B", "FSM", "R"), con("WLD", "FSM", "B", "WR", "B")],
          [ext("REQ", "FSM", "L", "in", ["REQ", "request from u_ctrl"]),
           ext("AXAR", "AR", "T", "out", ["AXAR", "ARADDR, ARLEN, ARSIZE,", "ARBURST, ARID, ARVALID, ARREADY"]),
           ext("AXR", "R", "B", "in", ["AXR", "RDATA, RRESP, RLAST,", "RID, RVALID, RREADY"], pos=-30),
           ext("BWR", "WR", "R", "out", ["BWR", "to u_bram_pp"]),
           ext("CLK", "LEG", "T", "in", ["CLK", "clk, rst"])],
          [{"id": "C1", "block": "INFO", "side": "T", "pos": 0}, {"id": "C2", "block": "FSM", "side": "L", "pos": 15},
           {"id": "C3", "block": "WR", "side": "B", "pos": 30}, {"id": "C4", "block": "R", "side": "B", "pos": 30},
           {"id": "C5", "block": "AR", "side": "T", "pos": 30}],
          [itf("REQ", "DMA request", "handshake (valid/ready)", "u_ctrl -> Request FSM", "req_valid, req_addr[31:0], req_len_bytes[31:0], req_dst_waddr[12:0]; Request FSM -> u_ctrl: req_ready, dma_done [pulse], dma_error [pulse], dma_err_code[2:0]"),
           itf("LOAD", "Legalizer load", "handshake (load pulse)", "Request FSM -> u_legal", "load [pulse], src[31:0], total_beats[29:0]"),
           itf("BST", "Burst descriptor", "handshake (valid/ready)", "u_legal -> u_ar", "bst_valid, bst_addr[31:0], bst_beats[4:0], bst_last; u_ar -> u_legal: bst_ready"),
           itf("PUSH", "Info FIFO push", "handshake (FIFO push)", "u_ar -> u_info", "push, push_beats[4:0], push_last; u_info -> u_ar: full"),
           itf("POP", "Info FIFO pop", "handshake (FIFO pop)", "u_r -> u_info", "pop; u_info -> u_r: empty, head_beats[4:0], head_last"),
           itf("BEAT", "Beat stream", "handshake (valid/ready)", "u_r -> u_wr", "beat_valid, beat_data[31:0], beat_last; u_wr -> u_r: beat_ready"),
           itf("RST", "Read status", "custom", "u_r -> Request FSM", "r_idle [level], rd_err [pulse], err_code[2:0]"),
           itf("ar_done", "AR done", "custom", "u_ar -> Request FSM", "ar_done [level]"),
           itf("WLD", "Writer load and done", "handshake (load/done)", "Request FSM -> u_wr", "load [pulse], cfg_dst[12:0], len_words; u_wr -> Request FSM: wr_last_done [pulse]"),
           itf("AXAR", "AXI4 read address channel", "standard (AXI4 AR)", "u_ar -> DRAM", "ARADDR[31:0], ARLEN[7:0], ARSIZE[2:0], ARBURST[1:0], ARID, ARVALID; DRAM -> u_ar: ARREADY"),
           itf("AXR", "AXI4 read data channel", "standard (AXI4 R)", "DRAM -> u_r", "RDATA[31:0], RRESP[1:0], RLAST, RID, RVALID; u_r -> DRAM: RREADY"),
           itf("BWR", "BRAM write port", "custom", "u_wr -> u_bram_pp", "we, waddr[12:0], din[255:0]; u_bram_pp -> u_wr, Request FSM: wr_ready [level], wr_done [pulse]"),
           itf("CLK", "Clock and reset", "custom", "external -> all blocks", "clk, rst")], NOTE)

# ---------------------------------------------------------------- page 4: GEMM
p4 = spec(["u_gemm", "(gemm_core)"],
          "[EXISTS, Minh] INT8 tile GEMM with TILE = 32. The load controller walks the loops n, m, k, row and reads one A word and one B word per cycle (one 256-bit word = one 32-element tile row); the PE array forms the outer product of a tile pair in 32 cycles; the accumulator sums the k partial tiles of one output tile. The three stages overlap at about 33 cycles per tile pair. In this architecture the B operand comes from bram_pp instead of the original internal B_bram.",
          "memory 2026-10-24",
          [blk("ABR", ["u_a_bram", "(A_bram)"], 0, 1,
               "Activation buffer of 64 x 768 INT8 (1536 words of 256 bit, one word = one tile row). It is written only while the core is idle (load all, then start); 64 rows limit S unless the buffer grows.",
               "memory 2026-10-24"),
           blk("LD", ["u_load", "(load_control)"], 0, 0,
               "Address generator and loop sequencer (n, m, k, row). Reads A and B words in parallel, 32 cycles per tile pair; because only one output tile is held, k is the innermost loop and every B word is re-read once per output row block.",
               "memory 2026-10-24"),
           blk("PE", ["u_pe", "(Gemm)"], 1, 0,
               "32 x 32 INT8 outer-product array: each cycle multiplies one A column vector by one B row vector and adds the products into a 32 x 32 partial tile; one tile pair takes 32 cycles.",
               "memory 2026-10-24"),
           blk("AC", ["u_accum", "(Accumulate_control)"], 1, 1,
               "Adds the partial tiles over k into the output tile (bias would be added at the start of a new dot product) and emits the finished tile. Accumulator width needs at least 25 signed bits for K = 768 (open).",
               "memory 2026-10-24; arch doc 8 item 5", width=240)],
          [con("ARD", "LD", "R", "ABR", "L"), con("TIL", "LD", "B", "PE", "T"), con("PPT", "PE", "R", "AC", "L")],
          [ext("XWR", "ABR", "R", "in", ["XWR", "X load from u_dma"]),
           ext("BRD", "LD", "T", "out", ["BRD", "read port of u_bram_pp"], pos=-20),
           ext("GCT", "LD", "L", "in", ["GCT", "start/done from u_ctrl"]),
           ext("RWR", "AC", "B", "out", ["RWR", "C tile to u_rbuf"]),
           ext("CLK", "PE", "B", "in", ["CLK", "clk, rst"])],
          [{"id": "C1", "block": "LD", "side": "L", "pos": 15}, {"id": "C2", "block": "ABR", "side": "T", "pos": -20},
           {"id": "C3", "block": "AC", "side": "R", "pos": 0}],
          [itf("ARD", "A buffer read", "custom", "u_load -> u_a_bram", "a_re, a_raddr[10:0]; u_a_bram -> u_load: a_rdata[255:0]"),
           itf("TIL", "Tile operands", "custom", "u_load -> u_pe", "op_valid, a_vec[255:0], b_vec[255:0], tile_first, tile_last"),
           itf("PPT", "Partial tile", "custom", "u_pe -> u_accum", "pp_valid, pp_tile (32 x 32 partial sums), new_dotproduct"),
           itf("XWR", "X load write port (proposed group)", "custom", "u_dma -> u_a_bram", "we, waddr[10:0], din[255:0]"),
           itf("BRD", "BRAM read port", "custom", "u_load -> u_bram_pp", "re, raddr[12:0], rd_done [pulse]; u_bram_pp -> u_load: dout[255:0], full[1:0]"),
           itf("GCT", "GEMM control (proposed group)", "handshake (start/done)", "u_ctrl -> u_load", "gemm_start [pulse], m_tiles, n_tiles, k_tiles, out_sel; u_load -> u_ctrl: gemm_done [pulse]"),
           itf("RWR", "Result write (proposed group)", "custom", "u_accum -> u_rbuf", "we, waddr, wdata"),
           CLKI], NOTE + " Signal names on this page are descriptive; Minh's RTL port names were not available.")

# ---------------------------------------------------------------- page 5: bram_pp
p5 = spec(["u_bram_pp", "(bram_pp)"],
          "[EXISTS, Long] Two 6144 x 256 synchronous BRAM banks that swap roles. A small role FSM keeps which bank is being written and which is being read, toggles the write bank on write-done and the read bank on read-done, and keeps a full flag per bank. Writes are steered to the write bank; reads go to the read bank and the output is selected with the read-bank select delayed by one cycle because the BRAM has one cycle of read latency.",
          "memory 2026-10-27; wave/bram_pp.json",
          [blk("ROLE", ["Bank role FSM", "(FG of bram_pp)"], 0, 1,
               "Holds the write-bank and read-bank selects and the two full flags. Sets a full flag and toggles the write bank when the last word of a bank is written; clears it and toggles the read bank when the reader reports done. Reports a free bank to the DMA and the full flags to the reader. Synchronous reset (open: consistency with other blocks).",
               "memory 2026-10-27"),
           blk("WS", ["Write steering", "(FG of bram_pp)"], 1, 0,
               "Routes the single write port (enable, address, data) to the bank selected by the role FSM; the other bank sees no write.",
               "memory 2026-10-27"),
           blk("B0", ["u_bank0", "(bram_6144x256)"], 1, 1,
               "Bank 0: 6144 words of 256 bit (196 608 B, one 768 x 256 INT8 chunk), one write port and one synchronous read port.",
               "memory 2026-10-27"),
           blk("RP", ["Read port", "(FG of bram_pp)"], 1, 2,
               "Sends the read address to the read bank and selects the output word with the read-bank select delayed one cycle to match the synchronous BRAM latency.",
               "memory 2026-10-27"),
           blk("B1", ["u_bank1", "(bram_6144x256)"], 2, 1,
               "Bank 1: identical to bank 0; written while bank 0 is read, and the reverse after a swap.",
               "memory 2026-10-27")],
          [con("WSEL", "ROLE", "L", "WS", "T"), con("RSEL", "ROLE", "R", "RP", "T"),
           con("WP0", "WS", "R", "B0", "L"), con("WP1", "WS", "B", "B1", "L"),
           con("RP0", "RP", "L", "B0", "R"), con("RP1", "RP", "B", "B1", "R")],
          [ext("BWR", "WS", "L", "in", ["BWR", "we, waddr, din"]),
           ext("BRD", "RP", "R", "in", ["BRD", "re, raddr, dout"]),
           ext("BST", "ROLE", "T", "out", ["BST", "wr_ready, wr_done,", "rd_done, full[1:0]"], pos=40),
           ext("CLK", "ROLE", "T", "in", ["CLK", "clk, rst"], pos=-60)],
          [{"id": "C1", "block": "WS", "side": "L", "pos": 15}, {"id": "C2", "block": "RP", "side": "R", "pos": 15},
           {"id": "C3", "block": "B1", "side": "B", "pos": 0}],
          [itf("WSEL", "Write-bank select", "custom", "Bank role FSM -> Write steering", "wr_bank [level]"),
           itf("RSEL", "Read-bank select", "custom", "Bank role FSM -> Read port", "rd_bank [level], rd_bank_q [level, delayed 1 cycle]"),
           itf("WP0", "Bank 0 write port", "custom", "Write steering -> u_bank0", "we0, waddr[12:0], din[255:0]"),
           itf("WP1", "Bank 1 write port", "custom", "Write steering -> u_bank1", "we1, waddr[12:0], din[255:0]"),
           itf("RP0", "Bank 0 read port", "custom", "Read port -> u_bank0", "re0, raddr[12:0]; u_bank0 -> Read port: dout0[255:0]"),
           itf("RP1", "Bank 1 read port", "custom", "Read port -> u_bank1", "re1, raddr[12:0]; u_bank1 -> Read port: dout1[255:0]"),
           itf("BWR", "BRAM write port (data part)", "custom", "u_dma -> Write steering", "we, waddr[12:0], din[255:0]"),
           itf("BRD", "BRAM read port (data part)", "custom", "u_gemm -> Read port", "re, raddr[12:0]; Read port -> u_gemm: dout[255:0]"),
           itf("BST", "Bank status (status part of BWR and BRD)", "custom", "Bank role FSM <-> u_dma, u_gemm", "Bank role FSM -> u_dma: wr_ready [level], wr_done [pulse]; u_gemm -> Bank role FSM: rd_done [pulse]; Bank role FSM -> u_gemm: full[1:0] [level]"),
           itf("CLK", "Clock and reset", "custom", "external -> all blocks", "clk, rst (synchronous reset). u_bank0 uses the same clk; its branch is not drawn because all four sides of u_bank0 are taken by other connectors")], NOTE)

pages = [("01_LEVEL_1_SOC", p1), ("02_LEVEL_2_ACCEL", p2), ("03_LEVEL_3_DMA", p3),
         ("03_LEVEL_3_GEMM", p4), ("03_LEVEL_3_BRAM_PP", p5)]
for name, s in pages:
    with open(os.path.join(OUT, name + ".json"), "w") as fh:
        json.dump(s, fh, indent=1)
print(" ".join(n for n, _ in pages))
