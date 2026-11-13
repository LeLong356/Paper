# DMA v0 (u_dma, module dma_rd): mô tả chức năng các khối

Cập nhật 2026-11-03 theo block diagram u_dma của bạn (sơ đồ: `dma/v0_diagram/vlsit_rtl_hierarchy.drawio`). Bản cũ 2026-10-28 (có CSR riêng) lưu ở `dma/old/dma_v0_4block_2026-10-28.md`.
Chỉ mô tả chức năng, không có RTL (bạn tự viết). Con số LUT/FF ở cuối là **tôi ước lượng**, chưa synth.

**Thay đổi so với bản 2026-10-28**
- CSR không còn nằm trong DMA: CPU cấu hình qua `u_csr`, còn DMA nhận lệnh từ `u_ctrl` qua bus **REQ** (valid/ready).
- CTRL nhỏ ở top DMA đổi tên thành **Request FSM** (FG of dma_rd, logic riêng của `dma_rd`, không phải module con).
- Block 3 cũ tách thành 3 instance: **u_ar** (ar_fsm), **u_info** (burst_info_fifo), **u_r** (r_fsm).
- Tên bus nội bộ theo hình: LOAD, BST, PUSH, POP, BEAT, RST, ar_done, WLD; bus ngoài: REQ, AXAR, AXR, BWR, CLK.
- Ba chỗ tôi chỉnh để khớp đúng các mũi tên trong hình (cần bạn xác nhận, xem §0 A8–A10):
  `ar_done` thành tín hiệu mức tổ hợp (bỏ state AR_DONE), lệnh hủy khi lỗi đi qua bus LOAD (`leg_abort`), và `wr_ready` của bram_pp đi qua u_wr rồi lên Request FSM qua bus WLD (vì trong hình BWR chỉ nối u_wr).

## 0. Giả định (sửa lại nếu sai)

| # | Giả định | Ghi chú |
|---|---|---|
| A1 | u_dma, u_ctrl, bram_pp cùng **1 clock** | Chỗ nào cần CDC sau này có đánh dấu **[CDC]** |
| A2 | AXI4 read-only, `DATA_W = 32`, `ADDR_W = 32`, INCR, tối đa 16 beat/burst | `ARSIZE = 3'b010`. Bản 512 bit để sau (main.tex §u_dma) |
| A3 | Đích v0 chỉ là cổng ghi bram_pp: `we`, `waddr[12:0]`, `din[255:0]`, vào `wr_ready`, `wr_done` | 1 từ = 256 bit = **8 beat** AXI 32-bit. `dst_sel`/demux/XWR của main.tex là bản sau |
| A4 | `waddr` là địa chỉ **trong 1 bank** (0..6143), bram_pp tự chọn bank | |
| A5 | `wr_ready = 1` nghĩa là có bank trống, DMA kiểm tra **lúc bắt đầu** transfer; trong lúc ghi không bị rớt xuống | Nếu có thể rớt giữa chừng thì writer phải có backpressure, xem §7 |
| A6 | Beat đầu tiên nằm ở bit thấp: beat i → `din[32*i +: 32]` | Phải khớp cách GEMM đọc từ; kiểm lại với Minh |
| A7 | `req_addr` align 4 byte, `req_len` là bội số của 32 byte, `req_len > 0` | Sai thì báo lỗi cấu hình, không chạy |
| A8 | `ar_done = (u_ar ở AR_IDLE) && !bst_valid` (mức) | Thay cho state AR_DONE cũ; Request FSM chỉ nhìn nó trong FLUSH |
| A9 | Khi lỗi, Request FSM gửi `leg_abort` qua LOAD để legalizer xóa `beats_left` → u_ar không phát burst mới | u_ar chỉ lấy `bst_*` ở AR_IDLE, nên hạ `bst_valid` lúc đó không vi phạm handshake |
| A10 | u_wr chuyển `wr_ready` của bram_pp lên Request FSM (`wr_bank_ready` trong WLD) | Giữ đúng hình: BWR chỉ nối u_wr |

Một bank đầy = 6144 từ × 32 B = 196 608 B = 49 152 beat = 3 072 burst 16 beat.

## 1. Bức tranh chung (khớp hình)

```
                 CLK (clk, rst) → mọi khối          AXAR ▲ (AXI4 AR tới DRAM)
                                                         │
          ┌──────────────┐   BST    ┌──────┐   PUSH   ┌────────┐
          │   u_legal    │ ───────▶ │ u_ar │ ───────▶ │ u_info │
          └──────────────┘          └──────┘          └────────┘
                 ▲ LOAD       ar_done │                   ▲ POP
REQ  ┌──────────────┐   RST    ┌──────┐   BEAT   ┌────────┐   BWR
───▶ │ Request FSM  │ ◀─────── │ u_r  │ ───────▶ │  u_wr  │ ───────▶ u_bram_pp
     └──────────────┘          └──────┘          └────────┘
            └──────────────── WLD ─────────────────▶ ▲
                                   ▲ AXR (AXI4 R từ DRAM)
```

Mũi tên chỉ từ bên chủ động (initiator) sang bên bị động; tín hiệu chiều ngược (ready, full, empty, done) nằm trong cùng bus.

| Bus | Từ → đến | Tín hiệu | Kiểu |
|---|---|---|---|
| REQ | u_ctrl → Request FSM | `req_valid`, `req_addr[31:0]`, `req_len[31:0]` (byte), `req_dst_waddr[12:0]`; ngược lại `req_ready`, `dma_done` (pulse), `dma_err` (pulse), `dma_err_code[2:0]` | valid/ready |
| LOAD | Request FSM → u_legal | `leg_load` (pulse), `leg_src[31:0]`, `leg_total_beats[29:0]`, `leg_abort` (pulse) | load pulse |
| BST | u_legal → u_ar | `bst_valid`, `bst_addr[31:0]`, `bst_beats[4:0]`, `bst_last`; ngược lại `bst_ready` | valid/ready |
| PUSH | u_ar → u_info | `push`, `push_beats[4:0]`, `push_last`; ngược lại `full` | FIFO push |
| ar_done | u_ar → Request FSM | `ar_done` (mức) | 1 tín hiệu |
| POP | u_r → u_info | `pop`; ngược lại `empty`, `head_beats[4:0]`, `head_last` | FIFO pop |
| RST | u_r → Request FSM | `r_idle` (mức), `r_err` (pulse), `r_err_code[2:0]` | status |
| BEAT | u_r → u_wr | `beat_valid`, `beat_data[31:0]`, `beat_last`; ngược lại `beat_ready` | valid/ready |
| WLD | Request FSM → u_wr | `wr_load` (pulse), `wr_dst[12:0]`, `wr_len_words[12:0]`; ngược lại `wr_bank_ready` (mức), `wr_last_done` (pulse) | load/done |
| AXAR | u_ar → DRAM | `ARADDR[31:0]`, `ARLEN[7:0]`, `ARSIZE[2:0]`, `ARBURST[1:0]`, `ARID`, `ARVALID`; ngược lại `ARREADY` | AXI4 AR |
| AXR | DRAM → u_r | `RDATA[31:0]`, `RRESP[1:0]`, `RLAST`, `RID`, `RVALID`; ngược lại `RREADY` | AXI4 R |
| BWR | u_wr → u_bram_pp | `we`, `waddr[12:0]`, `din[255:0]`; ngược lại `wr_ready` (mức), `wr_done` (pulse) | cổng ghi BRAM |
| CLK | ngoài → mọi khối | `clk`, `rst` | clock/reset |

> Ghi chú tên: hình dùng `RST` cho bus "read status" từ u_r. Dễ nhầm với reset (`rst` trong CLK). Nếu bạn muốn đổi thành `RSTS` hay `RSTAT` thì tôi sửa cả hai file.

---

## 2. Request FSM (FG of dma_rd)

**Mục đích:** nhận 1 lệnh từ u_ctrl, kiểm tra, nạp u_legal và u_wr, chờ xong, báo done/err. Đây là logic riêng nằm trong `dma_rd`, không phải module con.

`IDLE → CHECK → WAIT_RDY → RUN → FLUSH → DONE/ERR → IDLE`

| State | Làm gì | Chuyển |
|---|---|---|
| IDLE | `req_ready = 1` | `req_valid && req_ready`: chụp `req_addr/len/dst_waddr` vào thanh ghi → CHECK |
| CHECK | Kiểm A7 và `dst_waddr + len/32 ≤ 6144` | Sai → ERR (mã 1 = CFG); đúng → WAIT_RDY |
| WAIT_RDY | Chờ `wr_bank_ready = 1` | → phát `leg_load` và `wr_load` cùng 1 chu kỳ → RUN |
| RUN | u_ar và u_r chạy song song | `wr_last_done` → FLUSH; `r_err` → phát `leg_abort`, lưu mã lỗi → FLUSH |
| FLUSH | Chờ `ar_done && r_idle` (đã có lỗi) hoặc `ar_done && r_idle && đã thấy wr_last_done` | → DONE hoặc ERR |
| DONE / ERR | Phát `dma_done` hoặc `dma_err` 1 chu kỳ, `dma_err_code` giữ đến lệnh sau | → IDLE |

Mã lỗi: 1 = cấu hình sai, 2 = SLVERR, 3 = DECERR, 4 = RLAST sai (giống main.tex).

### Tín hiệu

| Tên | Hướng | Rộng | Bus |
|---|---|---|---|
| `req_valid`, `req_ready` | in, out | 1, 1 | REQ |
| `req_addr`, `req_len`, `req_dst_waddr` | in | 32, 32, 13 | REQ |
| `dma_done`, `dma_err` | out | 1, 1 (pulse) | REQ |
| `dma_err_code` | out | 3 | REQ |
| `leg_load`, `leg_abort` | out | 1, 1 (pulse) | LOAD |
| `leg_src`, `leg_total_beats` | out | 32, 30 | LOAD |
| `ar_done` | in | 1 | ar_done |
| `r_idle`, `r_err`, `r_err_code` | in | 1, 1, 3 | RST |
| `wr_load`, `wr_dst`, `wr_len_words` | out | 1, 13, 13 | WLD |
| `wr_bank_ready`, `wr_last_done` | in | 1, 1 | WLD |

### Lỗi hay gặp
1. `req_ready` để 1 cả khi đang chạy → u_ctrl gửi lệnh thứ 2 đè lệnh đang chạy.
2. Không chụp lệnh vào thanh ghi lúc handshake, dùng thẳng `req_*` (u_ctrl được phép đổi sau handshake).
3. `dma_done` là mức chứ không pulse → u_ctrl đếm 2 lần.
4. FLUSH chỉ chờ `wr_last_done` mà không chờ `ar_done && r_idle`: với lỗi, còn burst đang bay mà đã báo xong.
5. `len/32` tính bằng chia thay vì `>> 5`; `dst_waddr + len/32` thiếu bit nên tràn và qua CHECK sai.

### Cách test riêng
Thay u_legal, u_ar, u_r, u_wr bằng mô hình giả: `ar_done` lên sau N chu kỳ, `wr_last_done` pulse sau M chu kỳ, có thể chèn `r_err`. Kiểm: lệnh sai bị từ chối với mã 1; `req_ready = 0` khi bận; done/err đúng 1 chu kỳ; FLUSH chờ đủ ba điều kiện.

---

## 3. u_legal (burst_legalizer)

**Mục đích:** biến 1 lệnh (addr, total_beats) thành chuỗi burst hợp luật: mỗi burst ≤ 16 beat và **không vượt biên 4 KB**.

### Công thức mỗi burst
```
to_4k     = (4096 - addr[11:0]) >> 2        // 1..1024 beat, cần 11 bit
beats     = min(16, beats_left, to_4k)
bst_last  = (beats == beats_left)
sau handshake:  addr += beats*4 ;  beats_left -= beats
leg_abort:      beats_left = 0  (bst_valid rớt ngay)
```
Ví dụ: addr = 0x0FF8, còn 100 beat → to_4k = 2 → burst 2 beat, burst sau bắt đầu 0x1000 với 16 beat.

### Tín hiệu

| Tên | Hướng | Rộng | Bus |
|---|---|---|---|
| `leg_load`, `leg_abort` | in | 1, 1 | LOAD |
| `leg_src` | in | 32 | LOAD |
| `leg_total_beats` | in | 30 (= len >> 2) | LOAD |
| `bst_valid` | out | 1 | BST |
| `bst_ready` | in | 1 | BST |
| `bst_addr` | out | 32 | BST |
| `bst_beats` | out | 5 (1..16) | BST |
| `bst_last` | out | 1 | BST |

State: chỉ 2 thanh ghi `addr`, `beats_left` + `bst_valid = (beats_left != 0)`. Không cần FSM.

### Lỗi hay gặp
1. Hằng 4096 cần **13 bit**; viết `12'h1000` là tràn thành 0.
2. `beats_left` hẹp quá (49 152 beat cần ≥ 16 bit).
3. Cập nhật addr/beats_left trước handshake → mất burst khi ARREADY đến trễ.
4. Nhầm `ARLEN = beats` (đúng là `beats - 1`; việc trừ 1 để ở u_ar).
5. `bst_beats` 4 bit không chứa được 16.

### Cách test riêng
Không cần AXI. TB phát `leg_load` với (addr, len) ngẫu nhiên + các góc (addr = 0xFFC, 0xFC0, 0xFF8; len = 1, 15, 16, 17, 1024 beat), giữ `bst_ready` ngẫu nhiên. Kiểm mỗi burst: `1 ≤ beats ≤ 16`; `addr[11:0] + beats*4 ≤ 4096`; địa chỉ nối tiếp nhau; tổng beat = total_beats; `bst_last` chỉ ở burst cuối; `leg_abort` làm `bst_valid` rớt ngay.

---

## 4. u_ar (ar_fsm)

**Mục đích:** phát burst lên kênh AR, ghi thông tin burst vào u_info. Tham số `MAX_OUT` = độ sâu u_info (số burst đang bay); **v0 = 1** (y hệt `AR → R → AR`), sau tăng 2–8 không sửa cấu trúc.

| State | Làm gì | Chuyển |
|---|---|---|
| AR_IDLE | `ARVALID=0`; `ar_done = !bst_valid` | `bst_valid && !full` → chụp `bst_*` vào thanh ghi → AR_REQ |
| AR_REQ | `ARVALID=1`, `ARADDR`, `ARLEN = beats-1` từ thanh ghi, **giữ nguyên** | `ARREADY=1`: `push=1`, `bst_ready=1` → AR_IDLE |

Hằng: `ARSIZE=3'b010`, `ARBURST=2'b01`, `ARID=0`, `ARLOCK=0`, `ARCACHE=4'b0011`, `ARPROT=3'b000`, `ARQOS=0`.

### Tín hiệu

| Tên | Hướng | Rộng | Bus |
|---|---|---|---|
| `bst_valid`, `bst_ready` | in, out | 1, 1 | BST |
| `bst_addr`, `bst_beats`, `bst_last` | in | 32, 5, 1 | BST |
| `push`, `push_beats`, `push_last` | out | 1, 5, 1 | PUSH |
| `full` | in | 1 | PUSH |
| `ar_done` | out | 1 | ar_done |
| `M_AXI_ARADDR`, `ARLEN`, `ARSIZE`, `ARBURST`, `ARID` | out | 32, 8, 3, 2, 1 | AXAR |
| `M_AXI_ARVALID`, `ARREADY` | out, in | 1, 1 | AXAR |

### Lỗi hay gặp
1. Đổi ARADDR/ARLEN khi ARVALID=1 mà chưa có ARREADY (vi phạm AXI).
2. Hạ ARVALID khi chưa có ARREADY.
3. ARVALID reset về 1, hoặc ARVALID phụ thuộc tổ hợp vào ARREADY.
4. Push FIFO ở chu kỳ khác `ARVALID && ARREADY` → u_r chờ sai burst.

---

## 5. u_info (burst_info_fifo)

FIFO nhỏ độ sâu `MAX_OUT`, mỗi entry `{beats[4:0], last}` (6 bit). Với MAX_OUT = 1 chỉ là 1 thanh ghi + cờ valid. Số entry = số burst đang bay, nên không cần bộ đếm `out_cnt` riêng.

| Tên | Hướng | Rộng | Bus |
|---|---|---|---|
| `push`, `push_beats`, `push_last` | in | 1, 5, 1 | PUSH |
| `full` | out | 1 | PUSH |
| `pop` | in | 1 | POP |
| `empty`, `head_beats`, `head_last` | out | 1, 5, 1 | POP |

Lỗi hay gặp: push và pop cùng chu kỳ khi đầy/rỗng (với MAX_OUT = 1: push lúc đang có entry và pop cùng chu kỳ phải được phép, nếu không mất 1 chu kỳ mỗi burst; hoặc chấp nhận và ghi chú).

---

## 6. u_r (r_fsm)

**Mục đích:** nhận dữ liệu kênh R, kiểm RLAST/RRESP, đẩy beat sang u_wr, pop u_info ở cuối mỗi burst.

| State | Làm gì | Chuyển |
|---|---|---|
| R_IDLE | `RREADY=0`; `r_idle = empty` | `!empty` → nạp `exp_beats = head_beats` → R_RECV |
| R_RECV | `RREADY = beat_ready`; `beat_valid = RVALID`; đếm beat mỗi handshake | Beat cuối (`cnt == exp_beats-1`): kiểm `RLAST==1`, `pop=1`; → R_IDLE |
| R_DRAIN | lỗi: `RREADY=1`, `beat_valid=0` (**vứt** data), vẫn đếm beat và pop | u_info rỗng → R_IDLE (`r_idle` lên lại) |

Kiểm tra trong R_RECV:
- `RRESP != OKAY` → `r_err` pulse + `r_err_code` (2 hoặc 3), sang R_DRAIN.
- `RLAST` đến sớm hoặc không đến ở beat cuối → `r_err` mã 4, R_DRAIN.
- `RID` phải = 0 (v0 chỉ 1 ID nên chỉ là sanity check).
- `beat_last = head_last && (beat cuối của burst)`.

| Tên | Hướng | Rộng | Bus |
|---|---|---|---|
| `M_AXI_RDATA` | in | 32 | AXR |
| `M_AXI_RRESP` | in | 2 | AXR |
| `M_AXI_RLAST`, `RID` | in | 1, 1 | AXR |
| `M_AXI_RVALID`, `RREADY` | in, out | 1, 1 | AXR |
| `pop` | out | 1 | POP |
| `empty`, `head_beats`, `head_last` | in | 1, 5, 1 | POP |
| `beat_valid`, `beat_ready` | out, in | 1, 1 | BEAT |
| `beat_data`, `beat_last` | out | 32, 1 | BEAT |
| `r_idle`, `r_err`, `r_err_code` | out | 1, 1, 3 | RST |

### Lỗi hay gặp
1. Gặp lỗi RRESP là dừng nhận R luôn → slave treo vì còn beat chưa nhận. AXI không cho hủy burst, phải **drain**.
2. Tin RLAST tuyệt đối mà không đếm beat → slave lỗi làm writer lệch.
3. RREADY reset về 1.
4. Vẫn đẩy `beat_valid` khi đang drain → u_wr ghi rác vào bram_pp.

### Cách test riêng (u_ar + u_info + u_r chung)
Thay u_legal bằng TB đẩy burst cố định, thay u_wr bằng sink có `beat_ready` ngẫu nhiên. Nối **AXI4 burst memory model** (handoff §7): ARREADY trễ ngẫu nhiên, độ trễ beat đầu 5–30 chu kỳ, RVALID có khoảng hở. Data = địa chỉ. Bơm lỗi: SLVERR ở 1 beat giữa burst; RLAST sớm 1 beat. Assertion: payload AR ổn định khi `ARVALID && !ARREADY`; số entry u_info ≤ MAX_OUT; tổng beat ra = tổng beat yêu cầu.

---

## 7. u_wr (bram_writer, packer 32 → 256)

**Mục đích:** gom 8 beat 32-bit thành 1 từ 256-bit, ghi vào bram_pp, tăng waddr. Writer **không quan tâm biên burst**: nó chỉ đếm beat, nên burst 2 beat do cắt 4 KB vẫn gom đúng.

- `wr_bank_ready = wr_ready` (đi thẳng từ bram_pp lên Request FSM, A10).
- `idx` đếm 0..7. Beat `idx < 7`: lưu vào `buf[32*idx +: 32]`.
- Beat `idx == 7`: `we=1`, `din = {beat_data, buf[223:0]}`, `waddr = cur_waddr`, rồi `cur_waddr++`, `idx=0`.
- `cur_waddr` bắt đầu ở `wr_dst`. Đếm `words_written`, so với `wr_len_words`.
- `beat_ready = 1` (giả định A5).
- `wr_done` của bram_pp: khi transfer đúng 6144 từ thì nó pulse ngay sau từ cuối. Dùng làm cross-check.

| State | Chuyển |
|---|---|
| W_IDLE | `wr_load` → nạp `cur_waddr = wr_dst`, `idx = 0` → W_PACK |
| W_PACK | ghi như trên; từ cuối ghi xong → `wr_last_done=1` → W_IDLE |

| Tên | Hướng | Rộng | Bus |
|---|---|---|---|
| `wr_load`, `wr_dst`, `wr_len_words` | in | 1, 13, 13 | WLD |
| `wr_bank_ready`, `wr_last_done` | out | 1, 1 | WLD |
| `beat_valid`, `beat_ready` | in, out | 1, 1 | BEAT |
| `beat_data`, `beat_last` | in | 32, 1 | BEAT |
| `we`, `waddr`, `din` | out | 1, 13, 256 | BWR |
| `wr_ready`, `wr_done` | in | 1, 1 | BWR |

### Lỗi hay gặp
1. Ghi `din = buf` ở beat thứ 8 mà quên ghép beat hiện tại → thiếu 32 bit cao (hoặc lệch 1 beat).
2. Thứ tự beat ngược với cách GEMM hiểu (A6).
3. `waddr` tăng trước khi ghi → bỏ trống từ 0.
4. Reset `idx` mỗi burst → sai khi burst không phải bội số 8 beat.
5. `we` giữ 2 chu kỳ → ghi lặp.
6. Nếu sau này `wr_ready` có thể rớt giữa chừng: phải hạ `beat_ready` (→ RREADY = 0) chứ không được bỏ beat.

### Cách test riêng
TB đẩy beat với `beat_valid` ngẫu nhiên, data = số thứ tự beat. Mô hình BRAM trong TB chép lại mọi lần `we`. Kiểm: từ k = {beat 8k+7, …, beat 8k}; `waddr` tăng đều từ `wr_dst`; số lần `we` = `wr_len_words`; không có `we` khi `beat_valid=0`. Sau đó nối bram_pp thật để kiểm `wr_done` đến đúng sau từ 6143.

---

## 8. Thứ tự làm và tích hợp

1. **u_legal** (không phụ thuộc ai, test riêng).
2. **u_info**, rồi **u_ar** (chỉ cần BST và PUSH).
3. **u_r** + **u_wr**, test chung u_ar/u_info/u_r/u_wr với AXI slave model.
4. **Request FSM** cuối cùng, ráp thành `dma_rd`.

Test tích hợp: DRAM model nạp pattern, TB đóng vai u_ctrl gửi REQ với `req_addr = 0x0000_0FC0` (để có cắt 4 KB), `req_len = 196 608`. Kiểm 6144 từ trong bram_pp khớp pattern, `wr_done` pulse, `dma_done` đúng 1 chu kỳ.

## 9. Chỗ cần CDC sau này
1. **u_r ↔ u_wr** nếu AXI (MIG `ui_clk`) khác clock accelerator: chèn **async FIFO** ở bus BEAT (32 bit + last), `beat_ready = !fifo_full`. Đây cũng là chỗ sau này đổi sang AXI-Stream.
2. **REQ** nếu u_ctrl khác clock u_dma: req/ack 4 pha hoặc async FIFO 1 entry.
3. `wr_ready`/`wr_done` của bram_pp nếu bram_pp ở clock khác: 2-FF cho mức, toggle-sync cho pulse.

## 10. Ước lượng tài nguyên (ƯỚC LƯỢNG, chưa synth)

| Khối | LUT | FF |
|---|---|---|
| Request FSM (chụp lệnh + kiểm tra) | ~60 | ~90 |
| u_legal | ~60 | ~50 |
| u_ar + u_info + u_r (MAX_OUT = 1) | ~80 | ~60 |
| u_wr (buf 224 bit + đếm) | ~40 | ~240 |
| **Tổng** | **~240** | **~440** |

Để so: AMD AXI DMA v7.1 theo paper iDMA ~2745 LUT / 4738 FF (có cả write channel và SG, nên không so ngang được).
