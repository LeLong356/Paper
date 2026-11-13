# Tóm tắt paper iDMA

**Paper:** T. Benz, M. Rogenmoser, P. Scheffler, S. Riedel, A. Ottaviano, A. Kurth, T. Hoefler, L. Benini, *"A High-performance, Energy-efficient Modular DMA Engine Architecture"*, ETH Zürich (nhóm PULP), arXiv:2305.05240.
**Code:** RTL mã nguồn mở tại `github.com/pulp-platform/iDMA` (tôi chưa mở repo, chỉ đọc paper).

**Cách đọc tài liệu này**

- Phần 1 đến 6 là **điều paper nói**. Số liệu lấy từ bản text của paper trên arXiv; số chỉ nằm trong hình (Fig. 12, 13, 14) thì tôi không đọc được giá trị chính xác nên chỉ ghi nhận xét của tác giả.
- Chỗ nào là **ý của tôi** (suy luận, gợi ý) thì có nhãn **[Tôi suy ra]**.
- Thuật ngữ chuyên ngành giữ nguyên tiếng Anh, giải thích ngắn ở lần đầu xuất hiện. Bảng thuật ngữ ở §8.

---

## 1. Paper giải quyết vấn đề gì?

**DMA engine (DMAE)** là khối chuyển dữ liệu giữa các vùng nhớ thay cho CPU, để CPU (hay accelerator) không phải tự load/store từng word và để **che độ trễ bộ nhớ** (memory latency hiding).

Vấn đề tác giả nêu:

1. Mỗi hệ thống cần một DMA hơi khác nhau, ở **3 chỗ**:
   - **Control plane**: cách PE (processing element, tức CPU/core) ra lệnh cho DMA (ghi thanh ghi, descriptor trong bộ nhớ, hay lệnh ISA riêng).
   - **Khả năng chuyển dữ liệu**: 1D, 2D, N-D, scatter-gather, real-time lặp định kỳ...
   - **Data plane / on-chip protocol**: AXI4, AXI-Lite, AXI-Stream, OBI, TileLink...
2. DMA hiện có thường **cố định lúc thiết kế** (fixed at design time), nên mỗi dự án lại viết DMA mới, khó tích hợp và khó verify.
3. Xu hướng hệ thống lớn hơn, băng thông cao hơn và **độ trễ truy cập dài hơn** (2.5D/3D, HBM) khiến DMA phải giữ được nhiều **outstanding transaction** (giao dịch đã phát request nhưng chưa nhận xong data).

**Đóng góp chính:** một kiến trúc DMA **modular** (ghép khối) và **parametric** (có tham số), chia làm 3 phần có interface chuẩn hóa, để chỉ cần ghép khối phù hợp cho từng hệ thống thay vì viết lại.

---

## 2. Kiến trúc 3 lớp: frontend, midend, backend

```
   PE / CPU                                                      Bộ nhớ / bus
      │  (control plane)                                         (data plane)
      ▼
 ┌───────────┐  N-D desc  ┌──────────┐ ... ┌──────────┐ 1D desc ┌──────────────┐
 │ Frontend  │ ─────────▶ │ Midend 1 │ ──▶ │ Midend k │ ──────▶ │   Backend    │ ◀══▶ AXI/OBI/...
 └───────────┘            └──────────┘     └──────────┘         └──────────────┘
   (bắt buộc 1)            (0 hoặc nhiều, nối chuỗi)            (ít nhất 1)
```

- **Mọi interface giữa các lớp dùng ready-valid handshake** và có thể chèn pipeline register.
- **Backend chỉ hiểu 1D transfer.** Descriptor 1D gồm: *source address, destination address, length, protocol, backend options*.
- **Midend** nhận descriptor nhiều chiều, "bóc" phần cấu hình của riêng nó ra và sinh chuỗi descriptor 1D cho lớp sau.

### 2.1 Frontend (control plane)

Frontend là nơi PE ra lệnh. Paper liệt kê (Table 1):

| Frontend | Kiểu | Số chiều | Ghi chú |
|---|---|---|---|
| `reg_32`, `reg_32_2d`, `reg_32_3d` | Register file 32-bit | 1D / 2D / 3D | Mỗi core có bộ thanh ghi riêng (core-private) |
| `reg_64`, `reg_64_2d` | Register file 64-bit | 1D / 2D | |
| `reg_32_rt_3d` | Register file 32-bit | 3D | Dùng với midend real-time `rt_3D` |
| `desc_64` | **Descriptor-based** | 1D | Tương thích kiểu DMA của Linux, hỗ trợ **descriptor chaining** |
| `inst_64` | **Lệnh ISA mở rộng** RISC-V | 2D | Core Snitch phát được 1 transfer trong **3 cycle** |

- Bộ thanh ghi của frontend kiểu register gồm: `src_address`, `dst_address`, `transfer_length`, `status`, `configuration`, `transfer_id`, và với mỗi chiều thêm: `src_stride`, `dst_stride`, `num_repetitions`.
- **Cách launch:** đọc thanh ghi `transfer_id` sẽ khởi động transfer và trả về ID để sau này hỏi xem xong chưa.
- **Descriptor** (với `desc_64`): một cấu trúc nằm trong bộ nhớ, có `src_address`, `dst_address`, `transfer_length`, `backend_configuration` và con trỏ tới descriptor kế tiếp. **Descriptor chaining** = DMA tự đi theo chuỗi con trỏ, CPU chỉ cần đưa địa chỉ descriptor đầu. Đây là nền của **scatter-gather** (gom/rải dữ liệu từ nhiều vùng không liên tục).

### 2.2 Midend (biến đổi transfer)

Midend là tùy chọn, có thể nối nhiều cái thành chuỗi. Paper liệt kê (Table 2):

| Midend | Chức năng |
|---|---|
| `tensor_2D` | Tách 2D transfer thành chuỗi 1D (mỗi hàng 1 transfer, nhảy theo stride) |
| `tensor_ND` | Như trên nhưng **N chiều**, N chọn lúc compile |
| `mp_split` | Cắt transfer tại biên địa chỉ có tham số (ví dụ biên giữa các bank/vùng nhớ) |
| `mp_dist` | Phân phối transfer cho **nhiều backend** (mặc định 2 ngõ ra), chọn theo address offset |
| `rt_3D` | Lặp lại 1 transfer 3D theo **chu kỳ cấu hình được** (real-time, ví dụ đọc cảm biến định kỳ); transfer khác đi bypass |
| Arbitration midend | Gộp nhiều frontend về 1 backend, round-robin hoặc theo địa chỉ |

**N-D transfer** nghĩa là: chép một khối nhiều chiều (ví dụ một tile 2D trong ma trận lớn) bằng cách lặp `num_repetitions` lần một đoạn 1D, mỗi lần cộng `src_stride` và `dst_stride` vào địa chỉ.

### 2.3 Backend (data plane)

Backend có 3 phần, **chỉ transport layer là bắt buộc**:

```
1D desc ─▶ [Error handler] ─▶ [Transfer legalizer] ─▶ ┌──────────── Transport layer ────────────┐
           (tùy chọn)          (tùy chọn)              │ Read mgr ─▶ src shifter ─▶ Dataflow    │
                                                       │                           element      │
                                                       │ Write mgr ◀─ dst shifter ◀─(FIFO/buf)  │
                                                       └────────────────────────────────────────┘
```

**a) Error handler (tùy chọn)**
Khi bus trả lỗi, backend tạm dừng và báo **địa chỉ gốc của burst đã legalize** lên frontend. Có 3 cách xử lý: **continue** (bỏ qua, chạy tiếp), **abort** (hủy transfer), **replay** (phát lại).

**b) Transfer legalizer (tùy chọn)**
Cắt 1D transfer thành các **burst hợp luật** với protocol:
- không vượt **biên trang** (page boundary, với AXI là 4 KB),
- không vượt **độ dài burst tối đa** của protocol (AXI4: 256 beat hoặc 4 KB, cái nào đến trước),
- hoặc giới hạn do người dùng đặt.
Có thể bỏ legalizer nếu phần mềm đảm bảo transfer đã hợp lệ (tiết kiệm area, giảm 1 cycle latency). Transfer độ dài 0 có thể bị từ chối.

**c) Transport layer (bắt buộc)**
- **Read manager(s)**: phát request đọc theo protocol nguồn, đẩy dữ liệu ra thành **byte stream**.
- **Source shifter / destination shifter**: dịch byte để **căn chỉnh** (alignment) dữ liệu theo biên bus, vì địa chỉ nguồn và đích có thể lệch nhau trong một word.
- **Dataflow element**: một FIFO nhỏ giữa đọc và ghi, có 3 vai trò: **decouple** đọc với ghi, **gộp** (coalesce) các mảnh transfer, và **cắt đường timing dài**. Có thể thay bằng SRAM buffer để chứa cả transfer. Có thể gắn **in-stream accelerator** (xử lý dữ liệu ngay trên đường đi).
- **Write manager(s)**: ghi byte stream ra protocol đích.
- Đọc và ghi được **tách rời bằng FIFO**; số **outstanding transfer** là tham số.

**Multi-protocol, multi-channel**
- Một backend có thể có nhiều read/write manager cho nhiều protocol khác nhau (ví dụ đọc AXI4, ghi OBI).
- **Multichannel**: nhiều backend đứng sau 1 frontend/midend, có arbitration.

**Init pseudo-protocol**
Một "protocol giả" chỉ có read manager: sinh ra **giá trị lặp lại, giá trị tăng dần, hoặc chuỗi giả ngẫu nhiên**. Dùng để khởi tạo bộ nhớ (ví dụ xóa 0) mà không cần đọc nguồn.

### 2.4 Protocol hỗ trợ (Table 3)

| Protocol | Burst |
|---|---|
| AXI4 (+ATOP) | Có, tối đa 256 beat hoặc 4 KB |
| AXI4-Lite | Không burst |
| AXI4-Stream | Không giới hạn, RX/TX đối xứng |
| OpenHW OBI v1.5.0 | Không burst |
| SiFive TileLink v1.8.1 (TL-UL, TL-UH) | UH: burst độ dài lũy thừa 2 |
| Init | Không áp dụng |

Mọi protocol đều **byte-addressable** và dùng **ready-valid**. Theo tác giả, thêm protocol mới cần **tối đa 3 module, mỗi module vài trăm GE**.
(Lưu ý: text nói "hiện có 5 protocol" nhưng Table 5 lại liệt kê cả Wishbone; paper hơi không thống nhất chỗ này.)

### 2.5 Tham số chính

| Tham số | Ý nghĩa |
|---|---|
| `AW` | Address width |
| `DW` | Data width |
| `NAx` | Số outstanding transaction (số request đã phát mà chưa xong) |

Tác giả khuyên chọn `NAx` **đủ lớn để bão hòa bộ nhớ** với transfer nhỏ nhất, nhưng không quá lớn làm ngập target.

---

## 3. Kết quả

Tất cả synth ở **GlobalFoundries GF12LP+** (12 nm), corner typical, Synopsys Design Compiler 2022.12 topological mode, mục tiêu **1 GHz**.
Cấu hình base: `AW = 32`, `DW = 32`. (Paper không thống nhất số outstanding của base: text nói 2, chú thích Table 4 nói 16.)

### 3.1 Area

**Đơn vị GE (gate equivalent)** = diện tích quy đổi ra số cổng NAND2. 1 kGE = 1000 GE.

Phân rã area của backend (Table 4, DW = AW = 32-bit), giá trị đọc / ghi theo từng protocol:

| Phần | Base | AXI4 | AXI-Lite | AXI-Stream | OBI | TileLink | Init |
|---|---|---|---|---|---|---|---|
| Decoupling (FIFO outstanding), O(NAx) | 3.7 kGE | 1.4 kGE | 310 GE | 310 GE | 310 GE | 310 GE | 0 |
| State (thanh ghi địa chỉ, đếm), O(AW) | 1.5 kGE | 710 GE | 200 GE | 180 GE | 180 GE | 215 GE | 21 GE |
| Page split (legalizer) đọc/ghi | 0 | 95 / 105 | 7 / 8 | 0 | 5 / 5 | 0 | 0 |
| Pow2 split | 0 | 0 | 0 | 0 | 0 | 20 / 20 | 0 |
| Dataflow element | 1.3 kGE | | | | | | |
| Read / write manager | 70 GE | 190 / 30 | 60 / 60 | 60 / 60 | 60 / 35 | 230 / 150 | 55 |
| Shifter / mux | 120 GE | 250 / 250 | 75 / 75 | 180 / 180 | 170 / 170 | 65 / 65 | 0 |

(Cột decoupling và state tính chung cho đọc và ghi. Khi dùng nhiều protocol thì phần dùng chung lấy theo protocol lớn nhất.)

Các con số tổng kết:

- **iDMA nhỏ nhất: dưới 2 kGE** (text; Table 5 ghi "≥ 2 kGE", paper không thống nhất). Nhỏ hơn cả µDMA của Pullini et al. (15.4 kGE).
- **Mỗi outstanding transfer thêm vào tốn khoảng 400 GE** (dưới 400 GE theo phần kết luận).
- Cấu hình base 32-bit với **32 outstanding transfer vẫn dưới 25 kGE**.
- Init protocol thường **dưới 100 GE**.
- Midend real-time `rt_3D`: khoảng **11 kGE**.
- **Area model** (công thức ước lượng area theo tham số, fit bằng non-negative least squares): sai số trung bình **< 4%** theo protocol, **< 9%** theo AW/DW/NAx; model cho ra cận trên (overestimate).

### 3.2 Timing

- Có **timing model** dạng nghịch đảo theo critical path, sai số trung bình **< 4%** trên 6 cấu hình.
- OBI và AXI-Lite nhanh nhất; cấu hình nhiều protocol / nhiều port chậm hơn.
- **DW ảnh hưởng timing mạnh nhất** (do shifter và routing congestion); AW ảnh hưởng ít; NAx làm chậm nhưng dưới tuyến tính.
- Các cấu hình lớn vẫn chạy **trên 1 GHz** ở 12 nm. (Tần số chính xác từng cấu hình nằm trong Fig. 13, tôi không đọc được giá trị.)

### 3.3 Latency

- **Backend: cố định 2 cycle** từ lúc nhận 1D transfer đến lúc phát read request ra bus, không phụ thuộc protocol, số port, AW/DW/NAx.
- Backend **không có legalizer: 1 cycle**.
- **Mỗi midend: +1 cycle** (`tensor_ND` có thể cấu hình 0 cycle).
- Frontend `inst_64`: launch trong 3 cycle. Trên Manticore, launch 1D cần 3 lệnh, 2D tối đa 6 lệnh.

### 3.4 Bus utilization (Fig. 14)

Thí nghiệm: chép 64 KiB, chia thành các transfer nhỏ từ 1 B đến 1 KiB, với 3 loại bộ nhớ:

| Bộ nhớ | Latency | Outstanding của bộ nhớ |
|---|---|---|
| SRAM (L2 của PULP-open) | 3 cycle | 8 |
| RPC-DRAM (controller AXI4 mã nguồn mở, 933 MHz) | khoảng 13 cycle | 16 |
| HBM | khoảng 100 cycle | trên 64 |

Nhận xét của tác giả:

- Bộ nhớ nông (SRAM): **gần như full utilization với transfer bằng độ rộng bus, chỉ cần 8 outstanding**.
- Bộ nhớ sâu (latency lớn) **cần nhiều outstanding hơn**.
- Transfer **nhỏ hơn độ rộng bus thì utilization giảm mạnh**.
- Transfer **gấp 4 lần độ rộng bus** đạt gần full utilization ngay cả khi latency hàng trăm cycle.
- Câu chốt: trên hệ 32-bit, latency 100 cycle, **transfer chỉ 16 B đã đạt gần full bus utilization**.

### 3.5 Năng lượng

Paper **chỉ bàn định tính**: area nhỏ thì static power thấp; transfer chạy đến hết (run-to-completion) cho phép clock gating DMA và interconnect khi rảnh. **Không có số đo năng lượng.**

---

## 4. Các hệ thống đã tích hợp (case study)

| Hệ thống | Cấu hình iDMA | Kết quả paper báo |
|---|---|---|
| **PULP-open** (cluster 8 core, edge AI) | Frontend `reg_32_3d` mỗi core, midend `tensor_ND` (3D) + arbitration round-robin, backend AXI4 64-bit về host và OBI về TCDM | Thay MCHAN cũ. Chép 8 KiB TCDM→L2 mất **1107 cycle**, trong đó 1024 cycle là data (bus 64-bit). MobileNetV1 (Dory): **7.9 → 8.3 MAC/cycle**. Giảm **10% area** cluster. iDMA ≈ 50 kGE |
| **ControlPULP** (vi điều khiển quản lý nguồn/nhiệt cho CPU HPC) | DMA thứ hai với midend `rt_3D` | Tiết kiệm khoảng **2200 cycle mỗi chu kỳ lập lịch** (đo trên FPGA). DMA ≈ 11 kGE (8 event, 16 outstanding) |
| **Cheshire** (SoC Linux, CVA6 64-bit) | Frontend `desc_64`, AW/DW 64-bit, 8 outstanding | So với **Xilinx AXI DMA v7.1** trên FPGA Genesys II: utilization **cao gần 6×** với transfer 64 B; **LUT giảm > 10%, FF giảm > 23%, BRAM từ 216 Kib xuống 0** |
| **MemPool** (256 core, L1 1 MiB / 1024 bank) | Phân tán: `mp_split` + cây nhị phân `mp_dist` ra nhiều backend | Chép 512 KiB L2→L1: utilization **99%**, nhanh **15.8×** so với core tự chép. Kernel double-buffered: matmul 1.4×, conv 9.5×, DCT 7.2×, vector add 15.7×, dot product 15.8×. Area **< 1%** |
| **Manticore-0432x2** (432 core Snitch, HBM 16 GiB) | DW 512-bit, AW 48-bit, **32 outstanding**, frontend `inst_64`, midend `tensor_ND`, 1 port AXI4 + 1 port OBI | GEMM **1.37× đến 1.52×** (băng thông HBM đọc đỉnh 17 → 26 GB/s). SpMV **5.9× đến 8.4×**. SpMM **2.9× đến 4.9×**. Area thêm **2.1%** cluster |

Ghi chú: abstract nói "cải thiện ML inference 23%" ở hệ edge AI, nhưng phần thân chỉ có số 7.9 → 8.3 MAC/cycle (khoảng 5%). Tôi không tìm ra số 23% đến từ đâu trong text, bạn nên xem lại bản PDF nếu cần trích số này.

---

## 5. So sánh với các DMA khác (Table 5, area)

| DMA | Area / tài nguyên |
|---|---|
| **iDMA (paper này)** | từ < 2 kGE (nhỏ nhất), khoảng 45 đến 75 kGE trong các case study |
| µDMA (Pullini et al.) | 15.4 kGE |
| Morales et al. | 3.2 kGE |
| Rossi et al. | ≈ 82 kGE |
| cDMA (Rhu et al.) | 420 kGE |
| MT-DMA (Ma et al.) | 1.5 MGE |
| AMD/Xilinx AXI DMA v7.1 | 2745 LUT, 4738 FF, 216 kb BRAM (FPGA) |
| CubeDMA | 2162 LUT, 1796 FF (FPGA) |
| FastVDMA (Antmicro) | 455 slice (FPGA) |

Tác giả tự nhận đây là **kiến trúc DMA đầu tiên vừa modular hoàn toàn vừa đa dụng**, và phần lớn DMA khác là closed-source.

---

## 6. Kết luận của paper

- Kiến trúc 3 phần, modular, parametric; 5 hệ thống tích hợp thật.
- Area/timing model sai số **< 9%**.
- Dải cấu hình từ **< 2 kGE** đến **> 1 GHz** ở 12 nm.
- Backend latency **2 cycle**, mỗi outstanding transfer **< 400 GE**.
- Che được latency bộ nhớ sâu; transfer 16 B đạt gần full utilization ở latency 100 cycle (32-bit).

---

## 7. Điểm đáng học [Tôi suy ra]

1. **Tách "ra lệnh" khỏi "chuyển dữ liệu".** Backend chỉ biết 1D (src, dst, len). Mọi thứ phức tạp (2D, chain, lặp) đẩy lên midend/frontend. Nhờ vậy backend nhỏ, dễ verify riêng.
2. **Interface giữa các khối đều là ready-valid.** Muốn chèn khối mới hay thêm pipeline register chỉ cần cắm vào giữa.
3. **Outstanding transaction là thứ quyết định băng thông** khi bộ nhớ có latency lớn. Mỗi outstanding chỉ tốn một entry FIFO (khoảng 400 GE ở ASIC), nên rẻ hơn nhiều so với tăng data width.
4. **Legalizer là khối riêng, test riêng**, và có thể bỏ nếu phần mềm đảm bảo hợp lệ.
5. **Tách read và write bằng FIFO** (dataflow element) để phía đọc không bị phía ghi chặn và để cắt đường timing.
6. **Đo bằng transfer nhỏ.** Transfer lớn thì DMA nào cũng đạt full băng thông; khác biệt nằm ở transfer cỡ vài lần bus width.

---

## 8. Bảng thuật ngữ

| Thuật ngữ | Nghĩa ngắn |
|---|---|
| Frontend | Lớp nhận lệnh từ CPU/PE (thanh ghi, descriptor, lệnh ISA) |
| Midend | Lớp biến đổi transfer nhiều chiều thành chuỗi transfer 1D |
| Backend | Lớp thực sự đọc/ghi bus |
| Descriptor | Cấu trúc mô tả 1 transfer (src, dst, len, cấu hình) |
| Descriptor chaining | Descriptor chứa con trỏ tới descriptor kế, DMA tự chạy hết chuỗi |
| Scatter-gather | Gom dữ liệu từ nhiều vùng rời rạc hoặc rải ra nhiều vùng |
| N-D transfer | Transfer N chiều, mỗi chiều có stride và số lần lặp |
| Stride | Khoảng cách địa chỉ giữa 2 hàng liên tiếp |
| Burst | Một request bus chở nhiều beat dữ liệu |
| Beat | Một lần truyền dữ liệu bằng độ rộng bus |
| Outstanding transaction | Request đã phát nhưng chưa nhận xong dữ liệu |
| Legalizer | Khối cắt transfer thành burst hợp luật (biên 4 KB, độ dài tối đa) |
| Protocol manager (read/write manager) | Khối nói chuyện với 1 protocol bus cụ thể |
| Dataflow element | FIFO/buffer giữa đọc và ghi |
| Shifter | Khối dịch byte để căn chỉnh dữ liệu theo biên bus |
| Error handler | Khối xử lý lỗi bus: continue / abort / replay |
| Init pseudo-protocol | Nguồn dữ liệu giả để khởi tạo bộ nhớ |
| Bus utilization | Tỉ lệ cycle bus có data hữu ích |
| GE / kGE | Gate equivalent, đơn vị area quy về cổng NAND2 |

---

## 9. Áp dụng cho DMA v0 của Long [Tôi suy ra toàn bộ mục này]

So với tài liệu `dma/dma_v0_4block.md` (bản 2026-11-03).

### 9.1 Map khối v0 vào kiến trúc iDMA

| Khối v0 | Tương ứng trong iDMA | Nhận xét |
|---|---|---|
| `u_csr` + `u_ctrl` (ngoài DMA) | **Frontend** | Ở hệ của bạn, CPU không ra lệnh trực tiếp cho DMA. `u_ctrl` sinh request thay CPU, nên đóng vai frontend kiểu "register" nội bộ |
| Bus **REQ** (`req_addr`, `req_len`, `req_dst_waddr`) | **1D transfer descriptor** của backend | Đúng dạng (src, dst, len) của paper. Thiếu trường "protocol/options"; v0 chỉ có 1 đích nên chưa cần |
| **Request FSM** | Phần nhận descriptor + **error handler** kiểu **abort** | CHECK (A7) giống việc legalizer từ chối transfer sai. Khi lỗi: `leg_abort` + drain = chính sách abort |
| **u_legal** | **Transfer legalizer** | Giống hệt: cắt tại biên 4 KB và độ dài burst tối đa. iDMA dùng max 256 beat của AXI4; v0 tự giới hạn 16 beat (paper gọi là "user limit") |
| **u_ar** | **Read manager** (phần AR) | |
| **u_info** + tham số `MAX_OUT` | **Decoupling FIFO**, `MAX_OUT` chính là **NAx** | Paper chứng minh đây là tham số quan trọng nhất cho băng thông khi latency lớn |
| **u_r** | **Read manager** (phần R) | Drain khi lỗi là cách đúng, iDMA cũng không thể hủy burst AXI đang bay |
| **u_wr** (packer 32→256) | **Write manager** + **dataflow element** | Cổng BRAM của bram_pp giống một protocol đơn giản không burst (gần OBI). v0 không cần **shifter** vì giả định A7 (địa chỉ align, len bội 32 B) |
| *(chưa có)* | **Midend** | v0 không có midend. Đây là chỗ để thêm 2D và chain (§9.3) |

Kết luận ngắn: v0 của bạn đã là một **iDMA backend tối giản** (1 protocol đọc AXI4, 1 protocol ghi BRAM, legalizer, NAx = 1, error handler abort). Hướng phát triển của paper khớp với hướng bạn đang đi.

### 9.2 Cải tiến nhỏ, không đổi cấu trúc

1. **Tăng `MAX_OUT` lên 2 đến 4.** Với `MAX_OUT = 1`, mỗi burst 16 beat phải chờ hết latency đọc DRAM trước khi phát burst sau. Nếu latency MIG cỡ L cycle (tôi chưa đo trên VC707), utilization xấp xỉ 16 / (16 + L). Theo paper, đủ outstanding để che latency thì gần 100%. Cấu trúc u_ar/u_info/u_r đã chừa sẵn tham số này. Cần nhớ: R của AXI cùng ID trả theo thứ tự, nên với `ARID = 0` không cần reorder.
2. **Thêm FIFO giữa u_r và u_wr** (dataflow element). Hiện u_wr giả định `beat_ready = 1` (A5). Một FIFO nhỏ ở bus BEAT giúp u_r không bị chặn khi bram_pp tạm bận, và cũng là chỗ đặt **async FIFO** cho CDC sau này (§9 của file v0).
3. **Cân nhắc tăng giới hạn burst từ 16 lên 64 hoặc 256 beat** khi lên AXI 512-bit. Burst dài hơn thì ít request hơn, cần ít outstanding hơn. Legalizer chỉ đổi hằng số.
4. **Request queue** trước Request FSM (FIFO vài entry trên bus REQ). `u_ctrl` có thể đẩy request chunk sau khi chunk trước còn đang chạy, tránh khoảng trống giữa 2 request. Paper đạt được điều này nhờ handshake ready-valid và pipeline giữa các lớp.

### 9.3 Hướng mở rộng theo paper

**a) Midend 2D (giống `tensor_2D`)**

Ví dụ trong project: W là ma trận 768×768 INT8 lưu row-major trong DRAM, mỗi chunk là **768 hàng × 256 cột** (1 bank). Nếu W lưu nguyên dạng row-major thì chunk này **không liên tục** trong DRAM: mỗi hàng chỉ lấy 256 byte, rồi nhảy 768 byte. Đó đúng là một 2D transfer:

```
src_addr   = W_BASE + chunk_idx * 256
len        = 256 byte        (1 hàng của chunk = 8 từ 256-bit)
src_stride = 768 byte
dst_stride = 8 từ (256 B)
num_reps   = 768
```

Một midend 2D đặt giữa REQ và Request FSM sẽ sinh 768 request 1D liên tiếp; backend v0 giữ nguyên. Khi đó không cần sắp xếp lại W trong DRAM trước (hiện kiến trúc chọn "1D, không stride", tức là W phải được lưu sẵn theo chunk). Tôi chưa xác nhận bạn lưu W thế nào trong DRAM, nên đây chỉ là gợi ý.

Lưu ý: mỗi hàng chỉ 256 B = 64 beat 32-bit, legalizer cắt thành 4 burst 16 beat. Với `MAX_OUT = 1` và latency DRAM thì overhead mỗi hàng sẽ rõ hơn, nên 2D đi kèm tăng `MAX_OUT`.

**b) Descriptor chain (giống `desc_64`)**

Ở hệ của bạn, `u_ctrl` đã tự sinh chuỗi request (Wq, Wk, Wv, Wo, X, bias...) nên **chưa cần** DMA tự đọc descriptor từ DRAM. Descriptor chain có ích khi muốn CPU (VexRiscv) chuẩn bị sẵn toàn bộ danh sách transfer trong bộ nhớ rồi chỉ bấm START, khi đó `u_ctrl` đơn giản đi. Cách làm theo paper:
- Thêm 1 frontend đọc descriptor `{src, dst, len, cfg, next_ptr}` qua chính kênh AXI đọc (hoặc một port AXI-Lite riêng).
- Đưa descriptor ra bus REQ như hiện nay; `next_ptr = 0` là hết chuỗi.
- Backend v0 không phải sửa.

Tôi đề xuất làm 2D trước, chain sau, vì 2D giải ngay bài toán chunk W.

**c) Init pseudo-protocol**

Một nguồn "giả" sinh toàn 0 hoặc giá trị cố định, ghi thẳng vào buffer on-chip (ví dụ xóa accumulator/buffer giữa các head) mà không tốn băng thông DRAM. Rất rẻ (paper: dưới 100 GE ở ASIC). Ưu tiên thấp.

**d) `mp_split` / `mp_dist`**

Khi lên 512-bit hoặc có nhiều đích (dst demux ra A_buf, bias_buf, bram_pp trong spec MHSA), ý tưởng "midend phân phối transfer theo địa chỉ cho nhiều backend/đích" của paper khớp với khối dst demux trong `u_dma` bản sau.

### 9.4 Những gì **không nên** lấy từ paper ở giai đoạn này

- **Shifter cho địa chỉ không align**: v0 đã ép align bằng giả định A7, giữ vậy cho đơn giản.
- **Multi-protocol**: hệ chỉ có AXI4 (MIG) và cổng BRAM, không cần.
- **Replay error handler**: abort + báo lỗi lên CPU là đủ cho bring-up.

Số area của paper là ASIC 12 nm (GE), **không quy đổi trực tiếp ra LUT/FF trên VC707** được. Số duy nhất ở dạng FPGA là phần so với Xilinx AXI DMA v7.1 trong case study Cheshire.
