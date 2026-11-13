# Các dạng kiến trúc DMA và cái nào hợp với bài MHSA trên VC707

Viết ngày 2026-10-18 cho dự án MHSA accelerator (VexRiscv + AXI4-Lite, VC707). Nguồn ở cuối file; chỗ nào là tui suy luận/ước lượng thì có ghi rõ.

---

## 1. Cách nhìn chung: DMA = control plane + data plane

Paper iDMA (Benz et al., IEEE TC 2023) tách mọi DMA thành 3 khúc, dùng khung này để so các kiến trúc rất tiện:

```
 CPU / accelerator
        │  (cách CPU "ra lệnh")
 ┌──────▼──────┐   1D transfer    ┌──────────────┐   1D transfer   ┌────────────────────────────┐
 │  FRONT-END  │ ───────────────▶ │   MID-END    │ ──────────────▶ │          BACK-END          │
 │ reg / desc  │ (src,dst,len)    │ 2D/ND, split │                 │ legalizer → AR/R  ⇄  buffer │
 │ / instr     │                  │ (tùy chọn)   │                 │            → AW/W/B         │
 └─────────────┘                  └──────────────┘                 └────────────────────────────┘
   "lệnh vào bằng gì"          "1 lệnh lớn → nhiều lệnh 1D"        "chuyển byte thật sự trên bus"
```

- **Front-end**: CPU giao việc cho DMA bằng gì (thanh ghi, descriptor trong RAM, hay lệnh custom).
- **Mid-end** (không bắt buộc): biến 1 transfer phức tạp (2D/ND tensor) thành chuỗi transfer 1D.
- **Back-end**: chuyển dữ liệu thật. Gồm *legalizer* (cắt burst cho hợp luật AXI: ≤256 beat và không vượt biên 4 KB), *read/write manager*, và *buffer* ở giữa để tách read với write.

Như vậy "dạng kiến trúc DMA" thực ra là các lựa chọn độc lập trên từng trục dưới đây.

## 2. Các dạng kiến trúc theo từng trục

### 2.1 Theo front-end (cách lập trình DMA)

| Dạng | Cách hoạt động | Ví dụ | Ưu | Nhược |
|---|---|---|---|---|
| **Register-programmed** (direct register) | CPU ghi SRC, DST, LEN vào thanh ghi rồi ghi START, poll DONE | AMD AXI DMA *Direct Register Mode*, µDMA (PULP), iDMA `reg_32` | Đơn giản nhất, ít LUT, dễ debug | Mỗi transfer CPU phải can thiệp → CPU thành nút cổ chai khi có nhiều tile nhỏ |
| **Descriptor / Scatter-Gather** | CPU dựng danh sách descriptor (linked list) trong RAM, DMA tự fetch descriptor và chạy hết chuỗi | AMD AXI DMA *SG mode*, Synopsys DW_axi_dmac, iDMA `desc_64` | CPU rảnh, chạy được hàng loạt transfer không liên tục | Cần thêm 1 master port đọc descriptor, logic phức tạp hơn; descriptor phải nằm ở bộ nhớ DMA đọc được |
| **Instruction / command-queue** | Lệnh DMA là lệnh của CPU (ISA extension) hoặc đẩy vào FIFO lệnh | iDMA `inst_64` trên Snitch (launch 3 chu kỳ), Gemmini `mvin/mvout` qua RoCC, ARM DMA-330 | Độ trễ khởi động cực thấp, CPU xếp hàng được nhiều lệnh | Cần CPU hỗ trợ coprocessor interface (VexRiscv thì phải thêm plugin) |

### 2.2 Theo số chiều của transfer (mid-end)

| Dạng | Mô tả | Ví dụ |
|---|---|---|
| **1D / linear** | Một khối liên tục (addr, len) | Hầu hết DMA nhỏ, alexforencich `axi_dma_rd` |
| **2D strided** | `rows × row_len`, mỗi hàng cách nhau `stride` | AMD AXI VDMA (video), MT-DMA, ARM DMA-330, iDMA `tensor_2D` |
| **3D / ND** | Lồng nhiều vòng stride | CubeDMA (3D), iDMA `tensor_ND` |

Paper iDMA chỉ ra: DMA thường xử lý ND bằng cách phần mềm gọi lặp nhiều lần, rất tốn chu kỳ khi tile nhỏ. Làm ND bằng phần cứng thì CPU chỉ ra 1 lệnh.

### 2.3 Theo kiểu đầu/cuối

- **Memory → Memory** (CDMA): cả 2 phía đều là AXI memory-mapped. Ví dụ AMD AXI CDMA, alexforencich `axi_cdma`.
- **Memory → Stream / Stream → Memory** (MM2S / S2MM): một phía là AXI-Stream đi thẳng vào datapath. Ví dụ AMD AXI DMA, alexforencich `axi_dma_rd` (đọc AXI → xuất AXI-Stream).
- **Memory → BRAM port trực tiếp**: phía đích là cổng BRAM (addr/we/din) thay vì AXI. Đây chính là cái DMA v0 của bồ định làm.

### 2.4 Theo cách tổ chức back-end (quan trọng nhất cho hiệu năng)

| Dạng | Mô tả | Hệ quả |
|---|---|---|
| **Serialized (1 burst một lúc)** | AR → chờ hết R → AR tiếp | Mỗi burst đều phải "trả" nguyên độ trễ bộ nhớ |
| **Decoupled AR/R, nhiều outstanding** | Một FSM phát AR liên tục, một FSM khác nhận R; giới hạn bằng số burst đang bay (NAx) | Che được độ trễ bộ nhớ. iDMA: SRAM nông cần ~8 outstanding, HBM (~100 chu kỳ) cần >64 để gần full bus |
| **Decoupled read/write qua buffer** | Read side và write side nối qua FIFO/buffer | Copy mem→mem không bị nghẽn, cắt đường timing |

Code thật để tham khảo: `axi_dma_rd.v` của alexforencich có **2 FSM tách riêng**: `axi_state` (IDLE/START) chỉ lo cắt burst và phát AR, còn `axis_state` (IDLE/READ) lo nhận R. Cắt burst ở 4 KB nằm ở dòng 365–381 (`13'h1000 - (addr_reg & 12'hfff)`). Lỗi RRESP được báo qua `m_axis_read_desc_status_error` (SLVERR = 4, DECERR = 5).

### 2.5 Theo khả năng biến đổi dữ liệu

DMA không chỉ copy mà sửa dữ liệu trên đường đi:
- Chuyển vị block (MT-DMA), nén/giải nén (cDMA, Rhu et al.), đổi layout / padding.
- iDMA cho phép chèn "in-stream accelerator" vào buffer giữa read và write.

### 2.6 Theo số lượng / phân bố

- **Một DMA chung** cho cả hệ thống.
- **Nhiều kênh / phân tán**: mỗi buffer hoặc mỗi cluster một DMA (MemPool, Manticore trong paper iDMA; iDMA `mp_dist` chia 1 transfer ra nhiều back-end).

## 3. Đối chiếu với bài MHSA của bồ

### 3.1 Đặc điểm bài toán

- Dữ liệu tensor ở DRAM, đưa vào BRAM theo **tile** (sub-matrix). Một tile của ma trận W (hoặc X) **không liên tục** trong DRAM: là `rows` hàng, mỗi hàng `tile_cols × bytes`, cách nhau `stride = d_model × bytes`. → Bản chất là **transfer 2D**.
- Weight/input được stream vào theo tile, Q/K/V giữ trên chip để tái sử dụng. Paper FAMOUS (attention trên U55C) làm đúng kiểu này: chia W_q/W_k/W_v theo cột thành tile `(d_model/h) × TS`, mỗi tile load `d_model/TS` lần, MicroBlaze điều khiển qua AXI-Lite. Họ ghi nhận tile càng nhỏ thì càng load nhiều lần, latency càng tăng.
- CPU (VexRiscv) là CPU nhỏ, dBus một transaction một lúc → mỗi lần ghi thanh ghi qua bridge mất ~5 chu kỳ (theo tb_integration của bồ). Nếu mỗi tile cần 4–5 lần ghi thanh ghi + poll, CPU overhead đáng kể khi tile nhỏ.

### 3.2 Ước lượng độ trễ (tui tự tính, chưa đo)

Utilization của back-end serialized với burst B beat và độ trễ đọc L chu kỳ ≈ `B / (B + L)`.
- B = 16, L = 30 (giả định cho DDR3 qua MIG, cần đo lại khi có MIG) → **~35%** băng thông bus.
- Cùng điều kiện mà cho 4 burst outstanding → gần 100% (giới hạn lúc đó là bus).

Thêm nữa: bus 32-bit @200 MHz = 0,8 GB/s, trong khi DDR3 64-bit trên VC707 lý thuyết cỡ 12,8 GB/s (DDR3-1600, tui ước từ thông số board, cần kiểm lại với MIG config). Bus 32-bit sẽ là nút cổ chai đầu tiên khi lên DRAM thật.

### 3.3 Dạng nào hợp

| Trục | Chọn cho bài của bồ | Lý do |
|---|---|---|
| Front-end | **Register** (v0) → **command FIFO qua AXI-Lite** (sau) | Slave AXI-Lite đã có sẵn; descriptor/SG chưa cần vì số tile mỗi layer biết trước và đều đặn |
| Số chiều | **1D** (v0) → **2D strided** (v2) | Tile là sub-matrix; 2D giúp CPU chỉ ra 1 lệnh mỗi tile |
| Đầu/cuối | **AXI4 read → cổng BRAM** | Đúng kiến trúc đã chốt; không cần AXI-Stream ở giữa |
| Back-end | **Tách AR và R thành 2 process** ngay từ v0, dù chỉ cho 1–2 outstanding | Tránh phải viết lại FSM khi lên DRAM có latency thật |
| Biến đổi | Chưa cần; cân nhắc chuyển vị K sau | QKᵀ cần Kᵀ; có thể giải quyết bằng cách đánh địa chỉ BRAM thay vì DMA |
| Phân bố | **1 DMA** + ping-pong buffer | VC707 dư BRAM (mới dùng 17), chưa cần nhiều kênh |

## 4. Gợi ý cải tiến so với spec DMA v0 trong handoff

Spec v0 hiện tại: read-only, 32-bit, INCR 16 beat, align, chưa xử lý 4 KB, FSM `IDLE → AR → R → next burst / DONE`.

1. **Tách AR và R (quan trọng nhất).** FSM `IDLE→AR→R` là dạng serialized, mỗi burst trả nguyên latency. Đề xuất: 1 FSM phát AR + đếm số burst đang bay, 1 FSM/khối nhận R + ghi BRAM + đếm beat. Tham số `MAX_OUTSTANDING` (v0 cho = 1 vẫn chạy y như spec cũ, sau tăng lên mà không sửa cấu trúc). Cần FIFO nhỏ lưu thông tin từng burst (số beat, địa chỉ BRAM bắt đầu) nếu burst có độ dài khác nhau.
2. **Legalizer 4 KB sớm.** Thay vì "ghi chú ràng buộc", thêm khối tính `beats_this_burst = min(16, beats_left, (4096 − addr[11:0])/4)`. Chỉ là vài dòng tổ hợp, và testbench có thể bắt lỗi ngay. Tham khảo dòng 365–381 của `axi_dma_rd.v`.
3. **Tham số hóa `DATA_WIDTH`.** Viết 32-bit nhưng để `ARSIZE = $clog2(DATA_WIDTH/8)`, đếm theo byte. Sau này nối MIG 512-bit (hoặc qua width converter) không phải sửa logic.
4. **Báo lỗi và trạng thái rõ.** Thanh ghi STATUS có BUSY, DONE, ERR + mã RRESP (giống bảng lỗi của alexforencich). Tùy chọn: timeout counter.
5. **Bộ đếm hiệu năng.** `cycles_busy`, `bytes_moved`, `ar_stall_cycles` (ARVALID && !ARREADY), `r_wait_cycles`. Dùng để vẽ roofline và chứng minh được cải tiến 1 có tác dụng. Rất có giá trị khi viết báo cáo/luận văn.
6. **Lộ trình sau v0:**
   - v1: thêm write channel (BRAM → DRAM, nhớ BRAM đọc trễ 1 chu kỳ).
   - v2: mid-end 2D (`src, rows, row_bytes, src_stride, dst_stride`) → 1 lệnh = 1 tile.
   - v3: ping-pong buffer: DMA nạp tile kế vào buffer B trong khi PE tính trên buffer A; cờ `buf_sel` trong thanh ghi.
   - v4: command FIFO (CPU đẩy nhiều lệnh liên tiếp, DMA tự chạy), ngắt hoặc cờ DONE theo từng lệnh.
   - Sau cùng: MIG DDR3 + CDC giữa UI clock của MIG và clock 200 MHz.

## 5. Hướng có thể "cải tiến" để làm điểm nhấn (tui đề xuất, chưa kiểm chứng bằng paper riêng)

- **DMA hiểu tile của attention**: lệnh mức cao "load tile (head h, tile t) của W_q" thay vì địa chỉ thô, DMA tự tính địa chỉ (AGU). Đây là bước từ 2D mid-end lên AGU/hardware loop mà handoff đã nhắc.
- **Prefetch head kế tiếp** khi đang tính head hiện tại (kết hợp ping-pong + command FIFO), đo bằng performance counter để thấy compute–transfer overlap.
- **Chuyển vị K khi nạp** (transpose-on-load) để QKᵀ đọc BRAM tuần tự; so với cách đánh địa chỉ BRAM để chọn cách tốn ít tài nguyên hơn.
- **So sánh định lượng** với AMD AXI DMA v7.1: paper iDMA báo IP này tốn 2745 LUT, 4738 FF, 216 kb BRAM; DMA tự viết của bồ có thể so được về LUT/FF và utilization ở transfer nhỏ.

## 6. Nguồn

- P. Benz et al., *A High-performance, Energy-efficient Modular DMA Engine Architecture*, IEEE Trans. Computers, 2023. [arXiv 2305.05240](https://arxiv.org/html/2305.05240v2) — phần lớn phân loại ở mục 2, các con số outstanding, area, so sánh AXI DMA v7.1.
- *FAMOUS: Flexible Accelerator for the Attention Mechanism of Transformer on UltraScale+ FPGAs*. [arXiv 2409.14023](https://arxiv.org/html/2409.14023v1) — cách tile W_q/W_k/W_v và điều khiển qua AXI-Lite.
- alexforencich/verilog-axi, [`rtl/axi_dma_rd.v`](https://github.com/alexforencich/verilog-axi) — đọc code trực tiếp (2 FSM tách AR/R, cắt 4 KB, mã lỗi).
- AMD PG021 AXI DMA v7.1 [Product Guide](https://docs.amd.com/r/en-US/pg021_axi_dma) — Direct Register vs Scatter-Gather mode (tui tóm tắt từ kiến thức sẵn có, chưa đọc lại bản 2026).
- Gemmini (`mvin/mvout` qua RoCC) [Chipyard docs](https://chipyard.readthedocs.io/en/1.3.0/Generators/Gemmini.html) — ví dụ front-end dạng lệnh (chưa đọc chi tiết lần này).

Ghi chú: các API tra cứu học thuật (arXiv, OpenAlex, Semantic Scholar, Crossref) bị chặn mạng trong môi trường này, nên tui tìm qua web search và đọc bản HTML của paper.
