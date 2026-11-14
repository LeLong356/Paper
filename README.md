# FPGA Softmax

| Thư mục | Nội dung |
|---|---|
| [rtl/](rtl/) | RTL tổng hợp. Module top là `softmax`. |
| [tb/](tb/) | Testbench SystemVerilog cho lõi và các khối con. |
| [sim/](sim/) | Script kiểm tra VEXP với Icarus Verilog. |
| [docs/softmax/](docs/softmax/) | [Đặc tả RTL](docs/softmax/SOFTMAX_SPEC.md) và [báo cáo PPA](docs/softmax/PPA_Report.md). |
| [docs/vexp/](docs/vexp/) | Hình kiến trúc VEXP và kết quả mô phỏng. |

## Khối VEXP

* `rtl/vexp.sv`: Khối exp tổ hợp với đầu vào/đầu ra BF16, gồm `exps_stage` và `px`. Nhánh âm trong `exps_stage` dùng phép đổi dấu `−q`; khối `px` giữ nguyên.
* `tb/tb.sv`: Testbench tự kiểm tra các trường hợp đặc biệt và toàn bộ 65.536 mẫu BF16 bằng mô hình số nguyên theo bit.
* `sim/verify_vexp.py`: Chạy Icarus Verilog, kiểm tra tính đơn điệu, hành vi đặc biệt và đo sai số so với `math.exp` của giá trị BF16 đầu vào.

## Quy ước số học

* Cả hai dấu của zero và subnormal đầu vào đều trả `0x3F80` (1).
* NaN trả canonical NaN `0x7FC0`; `+Inf` trả `+Inf`; `−Inf` trả zero.
* Kết quả quá nhỏ được flush về zero; overflow trả `+Inf`.
* Đây là exp xấp xỉ, không bảo đảm kết quả được làm tròn đúng cho mọi đầu vào theo hàm exp lý tưởng.

## Kiểm chứng

Trong môi trường có Python 3, `iverilog` và `vvp`:

```sh
python3 sim/verify_vexp.py
```

Script chỉ tạo sản phẩm mô phỏng trong thư mục tạm. Có thể chạy `tb/tb.sv` trực tiếp trong Vivado; giữ top `tb_vexp_vivado`. Plusarg tùy chọn `+DUMP=/path/outputs.txt` xuất toàn bộ mẫu.

Ngưỡng hồi quy hiện dùng: sai số tương đối lớn nhất dưới 1% trên từng miền `[-8, 0]`, `[-16, 0]`, `[-80, 80]`. Đây là mục tiêu kiểm tra của phiên bản này, không phải chứng nhận tái lập sai số của bài nghiên cứu. Miền underflow/overflow được kiểm tra hành vi riêng, không tính vào các thống kê sai số này. Sai số trung bình tính đều theo mẫu bit BF16 (bao gồm hai mã zero), không phải lấy mẫu đều theo giá trị thực hay phân bố đầu vào mô hình học máy. So khớp mô hình bit không thay thế phép đo sai số toán học.
