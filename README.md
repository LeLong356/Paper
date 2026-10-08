# Hardware Implementation of Vector Exponential (`vexp`)
## Cấu trúc thư mục

* `vexp.sv`: Module thiết kế chính thực hiện phép tính hàm mũ (exponential) sử dụng định dạng 16-bit và biểu diễn Q-format (`LOG2E`), tích hợp cơ chế kiểm tra tràn số (`is_overflow` / `overflow_flag`) cùng các khối xử lý con (`exps_stage`, `px`).
* `tb.sv`: Testbench dùng để mô phỏng, cấp tín hiệu kiểm thử và đánh giá độ chính xác của module `vexp`.