# Báo cáo IEEE — Thien điều phối

`main.tex` là khung tiếng Việt dùng IEEEtran conference và XeLaTeX. Đây là bản nháp
cấu trúc, chưa phải báo cáo nộp. Đối chiếu với [mẫu IEEE chính thức](https://www.ieee.org/conferences/publishing/templates)
do giảng viên cung cấp trước khi định dạng cuối cùng. Môi trường LaTeX tách khỏi
môi trường thuật toán Julia; cần IEEEtran, fontspec và polyglossia (tiếng Việt).

Biên dịch từ thư mục này sau khi cài TeX Live/MiKTeX:

```sh
xelatex main.tex
bibtex main
xelatex main.tex
xelatex main.tex
```

Xuất bản hoàn thiện thành `docs/Report.pdf`: 10–15 trang nội dung chính, không tính
tài liệu tham khảo/phụ lục; ba chương theo đề; mọi hình/bảng có caption và dẫn chiếu,
công thức giải thích biến. Trích bài gốc và ít nhất ba tài liệu liên quan khác.
Chưa tạo PDF giả hoặc số liệu giả ở bước setup. Thêm ba nguồn còn thiếu sau khi đọc.

Hung viết cài đặt/scalability/output size; Thien viết basket/runtime/width/đề xuất;
Phat viết image/correctness/memory. Thien ghép các phần đã có bằng chứng, không viết
thay toàn bộ nhóm. Phat ghép notebook; Hung kiểm tra repository cuối cùng.

## Tạo lại biểu đồ độ đúng và bộ nhớ

Chạy từ thư mục gốc trên Julia 1.13.2 với [SPMF 2.66 và Java 25](../../tools/spmf/README.md).
Hai cấu hình đo cả hai biến thể qua CLI và đối chiếu toàn bộ đầu ra với cùng
tham chiếu SPMF ở mỗi ngưỡng. Dùng các thư mục kết quả mới.

```sh
julia --startup-file=no --project=. experiments/prepare_benchmarks.jl
julia --startup-file=no --threads=1 --project=. experiments/run.jl experiments/configs/report-correctness.toml --out results/raw/report-correctness
julia --startup-file=no --threads=1 --project=. experiments/run.jl experiments/configs/report-peak-memory.toml --out results/raw/report-peak-memory
python scripts/plot_report_validation.py results/raw/report-correctness results/raw/report-peak-memory
```

Dùng Python từ 3.11 và Matplotlib để vẽ. Thêm `--project PATH` vào hai lệnh
đo để chọn checkout ở revision được ghi trong báo cáo. Mỗi thư mục kết quả
ghi mã băm và phiên bản trong `environment.toml`, `source-checksums.toml` và
`config.toml`. Tệp `runs.csv` ghi từng phép đo. Các tệp `comparison.toml`
ghi số tập mục thiếu, thừa, lặp và sai support.

Nếu một số lượt cần chạy lại, giữ thư mục gốc và lưu các lượt chạy lại trong
thư mục riêng. Truyền `--correctness-retry` hoặc `--memory-retry` cho trình vẽ.
Trình vẽ đối chiếu mã băm đầu vào, ngưỡng và revision trước khi dùng kết quả
chạy lại cho một lượt lỗi.
