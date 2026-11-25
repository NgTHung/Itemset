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

Tectonic tự chạy XeTeX, BibTeX và số lần biên dịch lại cần thiết trong một lệnh:

```sh
tectonic -X compile main.tex
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
Mỗi cấu hình chạy JVM với heap tối đa 3 GiB và bộ thu gom Serial GC.

```sh
julia --startup-file=no --project=. experiments/prepare_benchmarks.jl
julia --startup-file=no --threads=1 --heap-size-hint=512M --project=. experiments/run.jl experiments/configs/report-correctness.toml --out results/raw/report-correctness
julia --startup-file=no --threads=1 --heap-size-hint=512M --project=. experiments/run.jl experiments/configs/report-peak-memory.toml --out results/raw/report-peak-memory
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_report_validation.py results/raw/report-correctness results/raw/report-peak-memory
```

Thêm `--project PATH` vào hai lệnh đo để chọn checkout ở revision được
ghi trong báo cáo. Mỗi thư mục kết quả
ghi mã băm và phiên bản trong `environment.toml`, `source-checksums.toml` và
`config.toml`. Tệp `runs.csv` ghi từng phép đo. Các tệp `comparison.toml`
ghi số tập mục thiếu, thừa, lặp và sai support.

[Hướng dẫn ứng dụng ảnh](../../applications/image_patterns/README.md#reproduce-the-sensitivity-study)
có lệnh tạo bảng độ nhạy và hình đối chiếu Semeion.
