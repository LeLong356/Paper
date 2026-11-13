# So sánh 5 kiến trúc DMA: PPA, timing, throughput

Viết ngày 2026-10-19, đi kèm [dma_architectures.drawio](dma_architectures.drawio) và [kien_truc_dma.md](kien_truc_dma.md). Số thứ tự 01–05 trùng với các trang trong file draw.io.

**Đọc trước khi dùng số:** bồ chưa có RTL DMA nào, nên con số LUT/FF/công suất của 5 kiến trúc là **tui ước lượng**. Số có nguồn thật được đánh dấu [iDMA] (paper Benz et al., IEEE TC 2023) hoặc [đo] (control plane của bồ trên VC707). Throughput tính bằng mô hình giải tích ở mục 3 nên ra số cụ thể, nhưng giả định về độ trễ DRAM vẫn cần đo lại khi có MIG.

Điều kiện chung: bus 32-bit, clock 200 MHz → băng thông đỉnh **800 MB/s**; burst 16 beat; FPGA VC707 (Virtex-7).

---

## 1. Bảng tổng hợp

| | 01 Generic (iDMA) | 02 Register, tuần tự | 03 Scatter-gather | 04 v0 tách AR/R | 05 2D + ping-pong |
|---|---|---|---|---|---|
| **CPU ra lệnh bằng** | tùy front-end | 4–5 lần ghi thanh ghi / transfer | danh sách descriptor trong RAM | 4–5 lần ghi thanh ghi / transfer | 6 lần ghi / tile, xếp hàng trong FIFO |
| **Burst đang bay** | NAx (2–64) | 1 | 4 (giả định) | N = 4 (tham số) | N = 4 |
| **LUT (ước lượng)** | AXI DMA v7.1: 2745 [iDMA] | ~150–300 | ~1000–2000 | ~250–400 | ~500–800 |
| **FF (ước lượng)** | AXI DMA v7.1: 4738 [iDMA] | ~200–300 | ~1200–2500 | ~300–450 | ~600–900 |
| **BRAM** | AXI DMA v7.1: 216 kb; iDMA: 0 [iDMA] | 0 | 0–1 (queue) | 0 (FIFO trong LUTRAM) | 0–1 cho DMA, **gấp đôi BRAM tile** do ping-pong |
| **Diện tích ASIC (tham khảo)** | back-end ~3.7 kGE, 32-bit 32 outstanding < 25 kGE [iDMA] | — | — | — | mid-end 3D +11 kGE [iDMA] |
| **Công suất động** | — | thấp nhất | trung bình (thêm master đọc/ghi descriptor) | thấp | cao nhất, chủ yếu do BRAM tile ×2 |
| **Đường găng dự kiến** | — | cộng địa chỉ 32-bit | cộng địa chỉ + mux descriptor | legalizer 4 KB (trừ 12-bit, so sánh 3 ngả) | 2 bộ cộng 32-bit nối tiếp (base + stride) |
| **Đạt 200 MHz?** | >1 GHz trên GF12 [iDMA] | dễ | được | được | được nếu pipeline bộ cộng 2D |
| **Trễ tới AR đầu tiên** | 2 chu kỳ sau khi nhận lệnh [iDMA] | ~30 chu kỳ (CPU ghi thanh ghi) + 1–2 | 1 lần đọc descriptor ≈ L + 8 | ~30 + 1–2 | ~40 (lệnh đầu); các lệnh sau bị che |
| **Utilization, L = 30** | ≈ 1.0 nếu NAx ≥ 3 | **0.33** | ≈ 1.0 | **1.0** | ≈ 1.0 |
| **Tile 64×64 B có stride (mục 3.3)** | — | 5568 chu kỳ, **147 MB/s** | 1092 chu kỳ, 750 MB/s | ≈ như 02 (xem ghi chú) | **1103 chu kỳ, 743 MB/s** |
| **Chạy được trên SoC hiện tại?** | — | có | **không** (mục 4) | có | có |
| **Độ khó RTL** | — | thấp | cao | trung bình | trung bình–cao |

Ghi chú cột 04: với tile có stride, mỗi hàng chỉ có 1 burst, nên tách AR/R không giúp được trong một hàng. CPU vẫn phải ra 64 lệnh, và overhead của CPU mới là thứ chiếm thời gian. Kiến trúc 04 chỉ lời lớn khi dữ liệu nằm liên tục (mục 3.2).

## 2. PPA chi tiết

### 2.1 Area

- Mốc so sánh có thật: control plane của bồ (VexRiscv + bridge + slave) tốn **1061 LUT, 1241 FF, 17 BRAM** [đo]. AMD AXI DMA v7.1 tốn **2745 LUT, 4738 FF, 216 kb BRAM** [iDMA, Table 5].
- 02 → 04 chỉ thêm một FIFO nhỏ (4 entry × ~20 bit), một bộ đếm outstanding và FSM thứ hai, tức khoảng +100 LUT. Chi phí rất nhỏ so với lợi ích ở mục 3.
- 03 đắt nhất vì phải có thêm một master AXI để đọc và ghi descriptor, cộng với bộ giải mã descriptor.
- 05 tăng thêm phần cứng của bộ đếm 2D (rows, 2 stride, 2 bộ cộng 32-bit) và command FIFO. Ping-pong làm **số BRAM chứa tile tăng gấp đôi**. Đây là chi phí lớn nhất của 05, nhưng VC707 còn dư (17/1030 BRAM36 đang dùng [đo]).

### 2.2 Power

Phần logic DMA rất nhỏ so với VexRiscv và BRAM, nên công suất bị chi phối bởi (1) số BRAM bật và (2) độ hoạt động của bus. Cùng lượng dữ liệu cần chuyển, kiến trúc nhanh hơn chạy ít chu kỳ hơn, nên **năng lượng trên mỗi byte** của 04/05 thấp hơn 02 dù công suất tức thời cao hơn. Paper iDMA cũng đánh giá theo năng lượng trên mỗi transfer chứ không theo công suất. Muốn có số thật thì chạy `report_power` sau implement với file SAIF từ simulation, đừng dùng chế độ vectorless.

### 2.3 Timing

- Control plane hiện có WNS +0.548 ns ở 200 MHz, Fmax ≈ 224 MHz [đo]. Biên này hẹp nên DMA không được thêm đường tổ hợp dài vào cùng clock.
- Chỗ dễ fail nhất là **legalizer 4 KB**: `min(16, beats_left, (4096 − addr[11:0]) >> 2)` gồm 1 phép trừ 12-bit, rồi 2 bộ so sánh nối tiếp. Nên đăng ký kết quả (register) trước khi đưa ra ARLEN.
- 05 có `addr_row = base + row × stride`. Không dùng nhân: cộng dồn `addr += stride` mỗi hàng là đủ, chỉ còn 1 bộ cộng 32-bit trên mỗi đường.
- Độ trễ khởi động của 02/04 chủ yếu nằm ở **phía CPU**: mỗi lần ghi thanh ghi qua bridge mất 5 chu kỳ [đo, tb_integration], và firmware phải ghi 4–5 thanh ghi rồi poll.

## 3. Throughput: mô hình và số liệu

### 3.1 Utilization của bus theo độ trễ bộ nhớ L

- Tuần tự (02): `U = B / (B + L + 2)`, trong đó 2 là số chu kỳ chuyển trạng thái của FSM.
- Tách AR/R với N burst đang bay (04, 05): `U = min(1, N·B / (B + L))`. Cần `N ≥ ⌈(B + L) / B⌉` để đạt 100%.

| L (chu kỳ) | Ví dụ | 02 tuần tự | 04, N = 2 | 04, N = 4 | 04, N = 8 | N tối thiểu |
|---|---|---|---|---|---|---|
| 4 | BRAM model trong testbench | 0.73 (582 MB/s) | 1.00 | 1.00 | 1.00 | 2 |
| 30 | DDR3 qua MIG (**giả định**, phải đo) | 0.33 (267 MB/s) | 0.70 | 1.00 | 1.00 | 3 |
| 100 | bộ nhớ trễ cao, như HBM trong [iDMA] | 0.14 (108 MB/s) | 0.28 | 0.55 | 1.00 | 8 |

Kết luận: với N = 4, kiến trúc 04 đạt full bus tới L ≈ 48 chu kỳ. Nên để `MAX_OUTSTANDING` là tham số và chỉnh lại sau khi đo L thật của MIG.

### 3.2 Một khối 4 KB nằm liên tục (256 beat = 16 burst), L = 30

- 02: 807 chu kỳ, gồm 30 chu kỳ CPU setup, 16 × 48 chu kỳ truyền và 9 chu kỳ poll.
- 04 (N = 4): khoảng 325 chu kỳ.
- Lý tưởng: 256 chu kỳ.

Vậy 04 nhanh gấp khoảng **2.5 lần** 02 với cùng lệnh từ CPU.

### 3.3 Một tile MHSA có stride: 64 hàng × 64 B (ví dụ một tile 64×64 INT8 của W_q), L = 30

Giả định: mỗi lần CPU ghi thanh ghi mất 5 chu kỳ [đo], vòng lặp firmware mất 10 chu kỳ cho mỗi lần launch, poll mất 9 chu kỳ (hai số sau là giả định).

| Kiến trúc | Cách chạy | Chu kỳ | Hiệu suất so với lý tưởng (1024) | Băng thông |
|---|---|---|---|---|
| 02 / 04 | 64 lần launch 1D, mỗi hàng 1 burst | 5568 | 0.18 | 147 MB/s |
| 03 (descriptor đã dựng sẵn) | 64 descriptor, fetch chồng lên truyền dữ liệu | 1092 | 0.94 | 750 MB/s |
| 05 | 1 lệnh 2D, N = 4 | 1103 | 0.93 | 743 MB/s |

Với tile có stride, mid-end 2D và scatter-gather cho hiệu năng gần như nhau, đều nhanh hơn 02/04 khoảng **5 lần**. Tuy nhiên 05 rẻ hơn nhiều về area và không cần CPU dựng descriptor. Ping-pong của 05 còn cho phép **che toàn bộ thời gian nạp tile** sau compute, miễn là thời gian tính một tile ≥ khoảng 1100 chu kỳ.

## 4. Ràng buộc riêng của SoC của bồ

- **Scatter-gather (03) chưa chạy được:** descriptor phải nằm ở bộ nhớ mà DMA đọc được, tức DRAM. Nhưng VexRiscv trong SoC hiện tại chỉ nối tới DMEM và AXI-Lite, không có đường ghi vào DRAM, nên CPU không dựng descriptor được. Muốn làm SG thì phải cho DMA đọc DMEM, hoặc cho CPU một cổng ra DRAM.
- **DMEM/IMEM không chứa tensor** (kiến trúc bồ đã chốt), nên mọi so sánh ở trên chỉ tính DRAM → BRAM.
- **Bus 32-bit là trần:** kể cả utilization đạt 1.0 cũng chỉ được 800 MB/s, trong khi DDR3 64-bit trên VC707 có trần lý thuyết cỡ 12.8 GB/s (tui ước, cần kiểm lại theo cấu hình MIG). Tăng `DATA_WIDTH` lên 128–512 bit là bước nhân throughput lớn nhất sau khi đã tách AR/R.

## 5. Khuyến nghị thứ tự làm

1. **04 trước, với `MAX_OUTSTANDING = 1`:** chạy đúng như 02, dễ debug. Sau đó tăng lên 4 mà không phải sửa cấu trúc.
2. **Thêm bộ đếm hiệu năng ngay từ 04,** để kiểm chứng các con số ở mục 3 bằng simulation (testbench có tham số L) và sau đó trên board.
3. **Lên 05 (2D, rồi command FIFO, rồi ping-pong)** khi đã chốt kích thước tile của MHSA.
4. **Bỏ qua 03** cho tới khi CPU có đường vào DRAM; 05 đã đạt throughput tương đương với chi phí thấp hơn.

## 6. Cách kiểm chứng các số ước lượng

- Area/timing: synth từng phiên bản ở chế độ out-of-context (`-mode out_of_context`) ở 200 MHz, ghi LUT/FF/BRAM/WNS vào bảng này.
- Throughput: testbench có AXI memory model với độ trễ L tham số hóa, đọc bộ đếm `cycles_busy` và `bytes_moved` để vẽ đường utilization theo L, rồi so với bảng 3.1.
- Power: `report_power` với SAIF từ cùng testbench.
