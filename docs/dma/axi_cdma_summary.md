# Tóm tắt AMD AXI CDMA (PG034 v4.1)

Cập nhật 2026-11-13.

**Nguồn đã dùng.** Link bạn gửi (`docs.amd.com/v/u/en-US/ds792_axi_cdma`) là data sheet cũ **DS792, AXI CDMA v3.02.a, ngày 2012-01-17**. Tôi không dùng bản này mà đọc bản mới thay thế nó: **PG034 "AXI Central Direct Memory Access LogiCORE IP Product Guide", v4.1, phát hành 2025-07-11**, bản HTML tại <https://docs.amd.com/r/en-US/pg034-axi-cdma> (đọc từng trang mục: Overview, Features, Feature Summary, Register Module, Scatter/Gather Block, DMA Controller, DataMover, Unaligned Transfers, Register Address Map, CDMACR, CDMASR, BTT, Programming Sequence, Scatter Gather Mode, Cyclic CDMA Mode, Transfer Descriptor Definition/CONTROL/STATUS, Transfer Descriptor Management, Interrupts, SG Interrupt Threshold, SG Delay Interrupt, Error Interrupts, Resets, Clocking, Throughput, CDMA Lite Mode Restrictions, User Parameters).

**Quy ước trong bài**
- Không đánh dấu: nội dung lấy từ PG034 v4.1.
- **[Tôi suy ra]**: nhận xét, giải thích hoặc gợi ý của tôi, tài liệu không nói.
- **[Không thấy trong tài liệu]**: tôi đã tìm ở các trang trên nhưng không có. Các trang tôi **chưa đọc**: Port Descriptions, Performance, IP Facts (bảng tài nguyên), các trang thanh ghi CURDESC/TAILDESC/SA/DA riêng, Example Design. Con số tài nguyên LUT/FF vì vậy không có trong bài.

---

## 1. CDMA là gì?

AXI CDMA là IP của AMD/Xilinx dùng để **copy dữ liệu từ một vùng nhớ sang một vùng nhớ khác** (memory-to-memory) trên AXI4 memory-mapped (AXI4 MM). CPU chỉ cần ghi địa chỉ nguồn (SA), địa chỉ đích (DA) và số byte (BTT); CDMA tự đọc từ nguồn rồi ghi sang đích, CPU không phải tự copy.

Khác với AXI DMA (PG021) là loại chuyển giữa memory và **AXI4-Stream** (MM2S, S2MM), CDMA có **cả hai đầu đều là memory-mapped** và chỉ có **một master AXI4 dữ liệu** dùng chung cho cả đọc lẫn ghi. **[Tôi suy ra]** phần so sánh với AXI DMA; PG034 không so sánh.

Hai chế độ:
- **Simple mode** (tài liệu gọi là "Simple DMA" / "Register Direct Mode"): CPU ghi 1 lệnh vào thanh ghi, CDMA chạy 1 lệnh rồi dừng.
- **Scatter Gather (SG) mode**: CPU dựng sẵn một **descriptor chain** (danh sách các BD, buffer descriptor) trong bộ nhớ; CDMA tự đọc từng BD, thực hiện, ghi trạng thái ngược lại vào BD, đến **tail pointer** thì dừng.

## 2. Tính năng chính

| Tính năng | Chi tiết theo PG034 |
|---|---|
| Interface dữ liệu | 1 AXI4 master (đọc + ghi), rộng **32, 64, 128, 256, 512, 1024 bit** |
| Interface thanh ghi | AXI4-Lite slave, rộng cố định **32 bit** |
| Interface SG | AXI4 master riêng cho SG, rộng cố định **32 bit** (chỉ có khi bật SG) |
| Địa chỉ | 32 đến 64 bit (`C_ADDR_WIDTH`) |
| BTT tối đa / lệnh | **67 108 863 byte** (2^26 − 1, trường 26 bit), trừ khi dùng DataMover Lite |
| Burst | INCR và FIXED (FIXED = **key-hole**). Burst size mặc định 16 beat (`C_M_AXI_MAX_BURST_LEN`) |
| 4 KB | DataMover tự bảo vệ biên 4 KB và tự cắt burst ("4 KB address boundary protection, automatic burst partitioning") |
| Unaligned | Tùy chọn **DRE** (Data Realignment Engine), realign theo byte, tối đa 512 bit. Không bật DRE mà transfer không align thì "unpredictable results" |
| Store and Forward | Có tùy chọn (`C_INCLUDE-SF`). **[Không thấy trong tài liệu]** mô tả độ sâu FIFO hay cách hoạt động |
| Clock | Đồng bộ hoặc bất đồng bộ giữa AXI4-Lite và AXI4 MM |
| Ngắt | 1 đường `cdma_introut`: IOC, Delay (SG), Error; có coalescing theo threshold (SG) |

**[Không thấy trong tài liệu]** (trong các trang đã đọc): AXI ID dùng là gì, số transaction outstanding tối đa, cách xử lý write response B chi tiết, các giá trị cho phép của `C_M_AXI_MAX_BURST_LEN` ở chế độ đầy đủ (chỉ thấy mặc định 16; ở Lite là 16/32/64).

## 3. Kiến trúc khối

PG034 liệt kê 5 khối:

| Khối | Chức năng (theo PG034) |
|---|---|
| **Register Module** | Thanh ghi điều khiển/trạng thái qua AXI4-Lite |
| **Scatter/Gather Block** | Đọc (fetch) và cập nhật (update) descriptor qua AXI4 master SG riêng. Có hàng đợi descriptor nội bộ nên **prefetch descriptor song song với lúc đang chuyển dữ liệu** |
| **DMA Controller** | "manages overall CDMA operation": nạp lệnh cho DataMover, lấy status từ DataMover, cập nhật về Register Module |
| **DataMover** | Phần thực sự chuyển dữ liệu: bảo vệ biên 4 KB, tự chia burst, **xếp hàng được nhiều lệnh**, DRE tùy chọn |
| **Reset Module** | Quản lý reset (xem §8) |

Luồng dữ liệu **[Tôi suy ra từ mô tả khối, tài liệu có hình nhưng tôi không đọc được chữ trong hình]**:

```
          AXI4-Lite                               AXI4 MM (SG, 32-bit)
CPU ───▶ Register Module ◀──▶ Scatter/Gather Block ◀──▶ bộ nhớ chứa BD
                │                     │ (BD → lệnh)
                ▼                     ▼
             DMA Controller ── command ──▶ DataMover ── AXI4 MM (data) ──▶ nguồn/đích
                  ▲                          │
                  └────────── status ────────┘
```

Ở Simple mode, lệnh đi thẳng từ thanh ghi SA/DA/BTT sang DMA Controller; ở SG mode lệnh đến từ BD do SG block đọc về.

## 4. Simple mode

"CDMA executes one programmed DMA command and then stops" (Simple DMA khi SG không được include, hoặc SG được include nhưng `CDMACR.SGMode = 0`).

**Trình tự lập trình** (Programming Sequence):
1. Kiểm tra `CDMASR.Idle = 1`.
2. Ghi `CDMACR`: bật `IOC_IrqEn` (và `Err_IrqEn`) nếu muốn dùng ngắt.
3. Ghi `SA` (thêm `SA_MSB` nếu địa chỉ > 32 bit).
4. Ghi `DA` (thêm `DA_MSB` nếu > 32 bit).
5. Ghi `BTT`. **Ghi BTT là thao tác khởi động transfer**, nên BTT phải ghi cuối cùng.
6. Poll `CDMASR.Idle = 1`, hoặc chờ ngắt (cần `IOC_IrqEn = 1`).
7. Nếu dùng ngắt: xác định nguồn ngắt (xong hay lỗi).
8. Xóa `CDMASR.IOC_Irq` bằng cách ghi 1 vào bit đó.
9. Quay lại bước 1 cho lệnh tiếp.

Ràng buộc: BTT = 0 gây lỗi `DMAIntErr`. Với DataMover Lite, BTT tối đa nhỏ hơn nhiều (xem §10).

## 5. Scatter Gather mode

### 5.1 Descriptor (BD)

Mỗi BD gồm **8 word 32 bit**, phải **align 16 word (64 byte)** (offset hợp lệ ví dụ 0x00, 0x40, 0x80, 0xC0).

| Offset | Tên | Ý nghĩa |
|---|---|---|
| 00h | `NXTDESC_PNTR` | Địa chỉ BD kế tiếp |
| 04h | `NXTDESC_PNTR_MSB` | 32 bit cao, chỉ dùng khi địa chỉ > 32 bit |
| 08h | `SA` | Địa chỉ nguồn |
| 0Ch | `SA_MSB` | 32 bit cao |
| 10h | `DA` | Địa chỉ đích |
| 14h | `DA_MSB` | 32 bit cao |
| 18h | `CONTROL` | [25:0] = BTT (tối đa 67 108 863, **không được = 0**); [31:26] reserved, phải = 0 |
| 1Ch | `STATUS` | [31] `Cmplt`, [30] `DMADecErr`, [29] `DMASlvErr`, [28] `DMAIntErr`; [27:0] reserved = 0 |

Về `STATUS`:
- Phần mềm phải **ghi 0 vào STATUS** khi dựng BD. SG engine ghi status ngược lại (write-back) đúng vị trí đó khi BD xong.
- `Cmplt = 1`: BD đã xong, phần mềm được dùng lại BD (ở tail pointer mode).
- Nếu engine đọc phải một BD **đã có `Cmplt = 1`** (BD cũ, "stale"): báo `SGIntErr`, engine dừng, BD không được cập nhật. Ở cyclic mode thì bit này bị bỏ qua.
- Lỗi phía SG (`SGDecErr/SGSlvErr/SGIntErr`) **không** ghi vào BD, chỉ có trong `CDMASR`.

**[Tôi suy ra]** BD của CDMA không có cờ SOF/EOF hay trường "last" như AXI DMA: điểm kết thúc chuỗi được xác định bằng **tail pointer** trong thanh ghi, không nằm trong BD.

### 5.2 Trình tự lập trình SG (Scatter Gather Mode)

1. Xóa `CDMACR.SGMode` (= 0).
2. Đặt `CDMACR.SGMode` (= 1). Việc **toggle SGMode** buộc SG engine dùng giá trị CURDESC mới ở bước 3.
3. Ghi `CURDESC_PNTR` (0x08) trỏ BD đầu tiên (thêm `_MSB` nếu > 32 bit).
4. Ghi `CDMACR` (0x00): các bit bật ngắt, key-hole, threshold/delay.
5. Ghi `TAILDESC_PNTR` (0x10) trỏ BD cuối. **Ghi TAILDESC là thao tác khởi động** việc fetch và xử lý BD.
6. Engine chạy đến hết BD tại TAILDESC rồi idle, `CDMASR.Idle = 1`.

### 5.3 Tail pointer (Transfer Descriptor Management)

- Ghi TAILDESC khi engine **đang dừng ở tail** → engine chạy tiếp.
- Ghi TAILDESC khi engine **chưa tới tail** → engine chạy tiếp tới tail mới.
- `TailPntrEn` (CDMACR bit 1) cố định = 1 khi có SG.

**[Tôi suy ra]** Nhờ vậy phần mềm có thể **nối thêm BD vào cuối chuỗi khi DMA đang chạy**: dựng BD mới, sửa `NXTDESC` của BD tail cũ trỏ tới nó, rồi ghi TAILDESC mới. Đây là mô hình producer (CPU) / consumer (DMA) như ring buffer, với Cmplt là cờ "consumer đã dùng xong".

### 5.4 Cyclic mode

- Dựng chuỗi BD thành vòng: BD cuối trỏ lại BD đầu.
- Đặt `CDMACR.Cyclic BD Enable` (bit 6) **trước** khi ghi TAILDESC; engine bỏ qua bit Cmplt.
- TAILDESC lúc này "does not serve any purpose and is used only to trigger the CDMA engine": ghi một giá trị **không nằm trong chuỗi** (ví dụ trong tài liệu: 0x50).
- Engine lặp chuỗi mãi cho đến khi bị dừng hoặc reset. **[Không thấy trong tài liệu]** cách dừng mà không reset.

### 5.5 Đổi giữa Simple và SG

- `SGMode` chỉ được đổi khi `CDMASR.Idle = 1`, đổi lúc khác thì "undefined".
- `Dly_IrqEn` phải đặt **sau** khi đã đặt `SGMode`. `Dly_Irq` bị xóa khi `SGMode = 0`.
- Key-hole bit phải giữ nguyên cho đến khi xử lý xong mọi BD.
- **[Không thấy trong tài liệu]** quy trình đổi chế độ chi tiết hơn (có cần reset không).

## 6. Register map

Offset tính từ `C_BASEADDR`. Các thanh ghi `_MSB` chỉ có nghĩa khi địa chỉ > 32 bit.

| Offset | Tên | Ý nghĩa |
|---|---|---|
| 00h | `CDMACR` | Control |
| 04h | `CDMASR` | Status |
| 08h | `CURDESC_PNTR` | Current descriptor pointer (SG) |
| 0Ch | `CURDESC_PNTR_MSB` | |
| 10h | `TAILDESC_PNTR` | Tail descriptor pointer (SG); ghi = start |
| 14h | `TAILDESC_PNTR_MSB` | |
| 18h | `SA` | Source address (Simple) |
| 1Ch | `SA_MSB` | |
| 20h | `DA` | Destination address (Simple) |
| 24h | `DA_MSB` | |
| 28h | `BTT` | Bytes to transfer (Simple); ghi = start. Tối đa 67 108 863 |

### 6.1 CDMACR (00h)

| Bit | Tên | Reset | Truy cập | Ghi chú |
|---|---|---|---|---|
| 31:24 | `IRQDelay` | 00h | R/W | SG. Timeout = 125 × IRQDelay × chu kỳ clock SG. Ghi 0 = tắt delay interrupt |
| 23:16 | `IRQThreshold` | 01h | R/W | SG. Tối thiểu 1; ghi 0 không có tác dụng |
| 15 | reserved | 0 | RO | |
| 14 | `Err_IrqEn` | 0 | R/W | Cho phép ngắt lỗi |
| 13 | `Dly_IrqEn` | 0 | R/W | SG. Phải đặt sau `SGMode` |
| 12 | `IOC_IrqEn` | 0 | R/W | Cho phép ngắt hoàn thành |
| 11:7 | reserved | 0 | RO | |
| 6 | `Cyclic BD Enable` | 0 | R/W | SG. Bỏ qua Cmplt; đặt trước khi ghi TAILDESC |
| 5 | `Key Hole Write` | 0 | R/W | Ghi địa chỉ FIXED; cần MAX BURST LENGTH = 16; không đổi khi đang chạy |
| 4 | `Key Hole Read` | 0 | R/W | Đọc địa chỉ FIXED; cùng ràng buộc |
| 3 | `SGMode` | 0 | R/W | 0 = Simple, 1 = SG. Chỉ đổi khi Idle |
| 2 | `Reset` | 0 | R/W | Soft reset (xem §8) |
| 1 | `TailPntrEn` | 1 (có SG) / 0 (Simple-only) | RO | |
| 0 | reserved | 0 | RO | |

### 6.2 CDMASR (04h)

| Bit | Tên | Reset | Truy cập | Ghi chú |
|---|---|---|---|---|
| 31:24 | `IRQDelaySts` | 00h | RO | Giá trị bộ đếm delay hiện tại |
| 23:16 | `IRQThresholdSts` | 01h | RO | Giá trị bộ đếm threshold hiện tại |
| 14 | `Err_Irq` | 0 | R/WC | Ghi 1 để xóa |
| 13 | `Dly_Irq` | 0 | R/WC | SG. Ghi 1 để xóa |
| 12 | `IOC_Irq` | 0 | R/WC | Ở SG phải đạt threshold. Ghi 1 để xóa |
| 10 | `SGDecErr` | 0 | RO | SG gặp DECERR |
| 9 | `SGSlvErr` | 0 | RO | SG gặp SLVERR |
| 8 | `SGIntErr` | 0 | RO | SG internal error |
| 6 | `DMADecErr` | 0 | RO | DataMover gặp DECERR |
| 5 | `DMASlvErr` | 0 | RO | DataMover gặp SLVERR |
| 4 | `DMAIntErr` | 0 | RO | DataMover internal error (gồm BTT = 0) |
| 3 | `SGIncld` | tùy build | RO | 1 = có SG |
| 1 | `Idle` | 0 | RO | Simple: xong lệnh. SG: đã tới tail và xử lý hết BD |
| 15, 11, 7, 2, 0 | reserved | 0 | RO | |

## 7. Ngắt

Chỉ có 1 output ngắt, **`cdma_introut`**, đồng bộ theo `s_axi_lite_aclk`. Nó lên 1 khi một sự kiện được ghi vào `CDMASR` **và** bit enable tương ứng trong `CDMACR` = 1.

| Nguồn | Chế độ | Khi nào |
|---|---|---|
| IOC (`IOC_Irq`) | Simple, SG | Simple: mỗi lệnh xong. SG: khi bộ đếm threshold về 0 |
| Delay (`Dly_Irq`) | SG | Bộ đếm delay hết hạn |
| Error (`Err_Irq`) | Simple, SG | 3 lỗi DataMover; SG thêm 3 lỗi SG engine |

**Interrupt coalescing** (gộp ngắt, SG):
- Đặt `IRQThreshold` > 1. Lúc bắt đầu SG, giá trị này nạp vào bộ đếm; mỗi BD xong (IOC event) bộ đếm giảm 1; về 0 thì phát `IOC_Irq`. Delay event hoặc phần mềm ghi lại threshold đều nạp lại bộ đếm.
- Mục đích: N BD mới ngắt CPU 1 lần thay vì N lần.

**Delay interrupt** (SG):
- `IRQDelay` ≠ 0. Bộ đếm **chỉ chạy khi `Idle = 1`**, reset và dừng khi `Idle = 0`.
- Mục đích: nếu chuỗi đã xong mà số BD chưa đủ threshold, CPU vẫn nhận được ngắt sau một khoảng chờ.
- Thời gian: 125 × IRQDelay × chu kỳ clock SG. **[Không thấy trong tài liệu]** tham số `C_DLYTMR_RESOLUTION` (có ở AXI DMA) không xuất hiện trong bảng tham số của PG034.

Xóa ngắt: ghi 1 vào `IOC_Irq` / `Dly_Irq` / `Err_Irq`.

## 8. Lỗi và reset

**Khi có lỗi** (Error Interrupts):
- Engine dừng "gracefully": các AXI transfer đã commit vẫn chạy cho xong; `Idle = 1` chỉ khi đã dừng hẳn.
- `CURDESC_PNTR` được cập nhật thành BD bị lỗi. Nếu nhiều lỗi cùng xảy ra chỉ ghi nhận 1.
- **Muốn chạy lại phải reset** (hardware reset hoặc ghi 1 vào `CDMACR.Reset`). Bit lỗi trong CDMASR là RO, chỉ reset mới xóa.

| Lỗi | Nguyên nhân |
|---|---|
| `DMAIntErr` | DataMover nhận BTT = 0 (từ thanh ghi BTT hoặc CONTROL của BD) |
| `DMASlvErr` | Slave trả SLVERR trên đường dữ liệu |
| `DMADecErr` | Địa chỉ dữ liệu không có slave (DECERR) |
| `SGIntErr` | BTT = 0, hoặc đọc phải BD đã có Cmplt = 1 |
| `SGSlvErr` | SLVERR khi fetch/update BD |
| `SGDecErr` | Địa chỉ BD không có slave |

**Reset**
- **Soft reset** (`CDMACR.Reset = 1`): graceful, transfer AXI đã commit chạy xong, phần còn trong hàng đợi bị xóa, mọi thanh ghi về giá trị reset.
- **Hardware reset** (`s_axi_lite_aresetn = 0`): reset toàn bộ core, **không** chờ AXI xong, phải đồng bộ với `s_axi_lite_aclk`, giữ tối thiểu **16 chu kỳ**.

## 9. Tham số cấu hình (User Parameters)

| Tên trên GUI | Tham số | Mặc định | Ghi chú |
|---|---|---|---|
| Enable Asynchronous mode | `C_AXI_LITE_IS_ASYNC` | 0 | 1: `s_axi_lite_aclk` ≤ `m_axi_aclk`, khác nguồn clock |
| Write/Read Data Width | `C_M_AXI_DATA_WIDTH` | 32 | 32 đến 1024 |
| Write/Read burst size | `C_M_AXI_MAX_BURST_LEN` | 16 | |
| Disable 4K Checks | `C_USE_DATAMOVER_LITE` | 0 | Nhãn GUI in như vậy; bật lên là dùng DataMover Lite (§10) |
| Allow unaligned transfer | `C_INCLUDE_DRE` | 0 | |
| Enable Scatter Gather | `C_INCLUDE_SG` | 1 | |
| Address Width (32-64) | `C_ADDR_WIDTH` | 32 | |
| Enable CDMA Store and Forward | `C_INCLUDE-SF` (in đúng như tài liệu) | 0 | |

## 10. CDMA Lite và hiệu năng

**Lite mode** (`C_USE_DATAMOVER_LITE = 1`):
- Data width chỉ 32 hoặc 64 bit; max burst chỉ 16, 32, 64 beat.
- BTT tối đa mỗi lệnh = MAX_BURST_LEN × (AXI_DATA_WIDTH/8). Ví dụ **[Tôi tính]**: 32 bit, burst 16 → 64 byte.
- Không có DRE.
- **Phần mềm tự kiểm tra không vượt biên 4 KB** cho SA, DA và BTT.

**Throughput** (bảng duy nhất trong PG034, % băng thông bus):

| Burst length | Gói test | Tần số AXI4 | Bus utilization |
|---|---|---|---|
| 16 | 9 000 byte | 150 MHz | 70% |
| 64 | | | "up to 99%" |

Tài liệu chỉ nói burst dài hơn thì throughput tốt hơn. **[Tôi suy ra]** Điều này khớp kết luận của paper iDMA: burst ngắn thì overhead mỗi burst và latency lộ ra nhiều hơn.

## 11. So với DMA v0 của Long và iDMA **[Tôi suy ra toàn bộ mục này]**

So với `dma/dma_v0_4block.md` (bản 2026-11-03) và `dma/idma_paper_summary.md`.

### 11.1 Map khối

| DMA v0 của bạn | AXI CDMA | iDMA | Nhận xét |
|---|---|---|---|
| `u_csr` + `u_ctrl`, bus REQ `{addr, len, dst_waddr}` | Register Module (SA, DA, BTT) | Frontend register | Cùng ý: 1 lệnh = (nguồn, đích, số byte). CDMA "start khi ghi BTT", bạn dùng `req_valid/ready`, tương đương nhưng sạch hơn cho phần cứng |
| *(chưa có)* | **Scatter/Gather Block** + BD + tail pointer | Frontend `desc_64` | Đây là phần bạn chưa có, xem §11.3 |
| **Request FSM** | **DMA Controller** | Phần nhận descriptor + error handler | Cả hai: nạp lệnh cho khối dưới, gom status, báo done/err. Request FSM kiểm tra cấu hình ở CHECK; CDMA cũng chặn BTT = 0 nhưng bằng cách báo `DMAIntErr` |
| **u_legal** | Phần "automatic burst partitioning / 4 KB protection" của **DataMover** | Transfer legalizer | Giống nhau. CDMA Lite bỏ phần này và đẩy việc kiểm 4 KB cho phần mềm; v0 của bạn giữ legalizer trong phần cứng là đúng hướng của bản CDMA đầy đủ |
| **u_ar** + **u_info** (`MAX_OUT`) + **u_r** | Phía đọc của **DataMover** (MM2S) | Read manager + decoupling FIFO (NAx) | DataMover "can queue multiple transfer requests" ứng với ý `MAX_OUT > 1`. PG034 không nói con số outstanding |
| **u_wr** (packer 32 → 256, ghi BRAM) | Phía ghi của **DataMover** (S2MM, ghi AXI4 MM) | Write manager + dataflow element | Khác lớn nhất: đích của CDMA là AXI4 MM nên phải lo AW/W/B; đích của bạn là cổng BRAM nên đơn giản hơn nhiều |
| Giả định A7 (align 4 B, len bội 32 B) | DRE tùy chọn; không DRE thì unaligned "unpredictable" | Shifter | Cùng triết lý: không có realign thì bắt buộc align |
| Mã lỗi 1–4 (CFG, SLVERR, DECERR, RLAST), drain rồi báo | `DMAIntErr/SlvErr/DecErr`, halt gracefully | Error handler kiểu abort | Giống nhau: không hủy được burst đang bay nên chờ cho xong rồi dừng. CDMA bắt **reset** mới chạy lại; v0 của bạn quay về IDLE luôn, nhẹ hơn và vẫn hợp lý vì u_ctrl là người ra lệnh |
| `dma_done` / `dma_err` pulse | `Idle` + `IOC_Irq` / `Err_Irq` (W1C) | | Với CPU, cờ "sticky + write-1-to-clear" an toàn hơn pulse. Nếu sau này CPU đọc trực tiếp trạng thái DMA thì `u_csr` nên chốt pulse thành bit W1C |
| Async FIFO cho CDC (để sau) | `C_AXI_LITE_IS_ASYNC` | | CDMA chỉ tách clock giữa phần thanh ghi và phần dữ liệu |

Tóm lại: v0 của bạn gần tương đương **DataMover phía đọc + DMA Controller** của CDMA, đích là BRAM thay vì AXI. Phần CDMA có mà bạn chưa có là **SG engine** và **cơ chế ngắt/coalescing**.

### 11.2 Khác biệt về mục đích

- CDMA là IP đa năng, CPU điều khiển từng lệnh hoặc dựng chuỗi BD. Hệ MHSA của bạn có `u_ctrl` sinh chuỗi request theo chunk (Wq, Wk, Wv, Wo, X, bias), nên `u_ctrl` **đang đóng vai một SG engine bằng phần cứng cố định**.
- Vì vậy chưa cần SG cho v0. SG chỉ đáng làm khi bạn muốn CPU (VexRiscv) tự quyết danh sách transfer mà không phải sửa RTL `u_ctrl`.

### 11.3 Điều nên học từ CDMA cho descriptor chain (khi làm)

1. **BD align và kích thước cố định** (CDMA: 8 word, align 64 B). Fetch 1 BD = đúng 1 burst ngắn, không bao giờ vượt 4 KB, dễ parse. Với v0 32 bit: BD 8 word = 1 burst 8 beat qua chính kênh AR/R.
2. **Kết thúc chuỗi bằng tail pointer thay vì cờ "last" trong BD.** Ghi TAILDESC vừa là "start" vừa là "nối thêm việc". CPU có thể thêm BD khi DMA đang chạy mà không có race. Paper iDMA dùng `next_ptr = 0` (đơn giản hơn nhưng không nối thêm được khi đang chạy); bạn chọn một trong hai, tôi nghiêng về `next_ptr = 0` cho bản đầu vì ít thanh ghi hơn.
3. **Status write-back + bit Cmplt** để phần mềm biết BD nào xong và để phát hiện BD cũ (đọc phải Cmplt = 1 thì báo lỗi). Đây là cơ chế an toàn rẻ, đáng chép.
4. **Lỗi SG tách khỏi lỗi dữ liệu** (SGxxxErr vs DMAxxxErr) và **CURDESC trỏ vào BD lỗi**. Debug dễ hơn nhiều.
5. **Prefetch BD song song với data**: SG block có hàng đợi BD riêng nên không tạo khoảng trống giữa hai BD. Với bạn, tương đương một **request FIFO trước Request FSM** (đã gợi ý ở iDMA §9.2 mục 4).
6. **Coalescing ngắt** (threshold + delay timer) chỉ cần khi CPU nhận ngắt theo BD. Hệ của bạn CPU chỉ poll DONE cuối cùng, nên bỏ qua.
7. **Đổi chế độ chỉ khi Idle**, và "toggle SGMode để nạp lại CURDESC". Quy tắc kiểu này nên viết thẳng vào spec để tránh trạng thái undefined.
8. **Không nên chép**: bắt reset sau mỗi lỗi (bất tiện), cyclic mode (MHSA không cần lặp vô hạn), key-hole (chỉ dùng cho FIFO ngoại vi), DRE (đã có giả định A7).

### 11.4 Thứ tự gợi ý

Giữ đề xuất ở iDMA summary: **2D midend trước** (giải ngay bài chunk W 768 × 256), **descriptor chain sau**, và khi làm chain thì lấy định dạng BD + status write-back + cách báo lỗi của CDMA làm mẫu.

## 12. Bảng thuật ngữ

| Thuật ngữ | Giải thích ngắn |
|---|---|
| CDMA | Central DMA: DMA copy memory → memory trên AXI4 MM |
| AXI4 MM | AXI4 memory-mapped: giao tiếp có địa chỉ (AR/R/AW/W/B) |
| AXI4-Lite | AXI4 rút gọn, không burst, dùng cho thanh ghi |
| Simple mode / Register Direct Mode | CPU ghi SA, DA, BTT; chạy 1 lệnh rồi dừng |
| Scatter Gather (SG) mode | DMA tự đọc chuỗi descriptor trong bộ nhớ và thực hiện lần lượt |
| BD (Buffer/Transfer Descriptor) | Cấu trúc 8 word mô tả 1 transfer: next, SA, DA, BTT, status |
| Descriptor chain | Chuỗi BD nối nhau bằng `NXTDESC_PNTR` |
| CURDESC | Thanh ghi trỏ BD đang/sắp xử lý; khi lỗi trỏ BD lỗi |
| Tail pointer (TAILDESC) | Thanh ghi trỏ BD cuối; ghi vào = start / chạy tiếp |
| SG engine | Khối fetch và update BD |
| DataMover | Khối chuyển dữ liệu thật: chia burst, 4 KB, hàng đợi lệnh, DRE |
| DataMover Lite | Bản rút gọn: không 4 KB check, không DRE, BTT nhỏ |
| BTT | Bytes To Transfer, số byte của 1 lệnh |
| Burst | Một giao dịch AXI nhiều beat với một địa chỉ |
| Key-hole | Đọc/ghi với địa chỉ cố định (AXI FIXED burst), dùng cho FIFO ngoại vi |
| DRE | Data Realignment Engine: dịch byte để hỗ trợ địa chỉ không align |
| Store and Forward | Đệm dữ liệu trước khi phát phía ghi (PG034 không mô tả chi tiết) |
| Cyclic mode | Chuỗi BD vòng, lặp mãi, bỏ qua bit Cmplt |
| Cmplt | Bit "đã xong" trong STATUS của BD |
| IOC | Interrupt On Complete |
| Interrupt coalescing / threshold | Gộp N lần hoàn thành thành 1 ngắt |
| Delay interrupt | Ngắt sau một khoảng chờ khi DMA idle, để không bỏ sót khi chưa đủ threshold |
| W1C / R/WC | Write-1-to-clear: ghi 1 để xóa bit |
| SLVERR / DECERR | Mã RESP lỗi của AXI: slave lỗi / không có slave ở địa chỉ đó |
| Graceful halt | Dừng sau khi các transfer AXI đã phát hoàn tất |
| Register map | Bảng offset và ý nghĩa các thanh ghi |
