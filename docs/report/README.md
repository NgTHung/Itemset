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

Bản tiếng Anh `main-en.tex` dịch cùng nội dung trong `sections-en/` cho người đọc
không đọc tiếng Việt. Bản nộp chấm điểm vẫn là bản tiếng Việt theo đề. Bản tiếng Anh
dùng chung `references.bib`. Mỗi hình có nhãn chữ có hai bản: bản tiếng Việt trong
`figures/` cho `main.tex` và bản tiếng Anh trong `figures/en/` cho `main-en.tex`. Mỗi kịch
bản vẽ nhận `--language vi` cho bản tiếng Việt và mặc định là tiếng Anh. Khi sửa một mục,
sửa cả hai bản. Biên dịch:

```sh
tectonic -X compile main-en.tex
```

Xuất bản hoàn thiện thành `docs/Report.pdf`: 10–15 trang nội dung chính, không tính
tài liệu tham khảo/phụ lục; ba chương theo đề; mọi hình/bảng có caption và dẫn chiếu,
công thức giải thích biến. Trích bài gốc và ít nhất ba tài liệu liên quan khác.
Chưa tạo PDF giả hoặc số liệu giả ở bước setup. Thêm ba nguồn còn thiếu sau khi đọc.

Hung viết cài đặt/scalability/output size; Thien viết basket/runtime/width/đề xuất;
Phat viết image/correctness/memory. Thien ghép các phần đã có bằng chứng, không viết
thay toàn bộ nhóm. Phat ghép notebook; Hung kiểm tra repository cuối cùng.

## Tạo lại biểu đồ độ đúng và bảng bộ nhớ

Hình lưới độ đúng và bảng peak RSS lấy từ đợt đo thời gian trên máy chấm điểm,
`bbq-all-variants-cli-5repeat-20261117T041922Z`. [Bản ghi đợt đo](../runtime-curves-2026-11-17.md#reproduce)
có mã băm của thư mục kết quả và lệnh tái lập. Mọi lần chạy trong đợt này đã được đối
chiếu toàn bộ đầu ra với SPMF, và kịch bản vẽ từ chối vẽ nếu có lần chạy không khớp.
Bảng peak RSS là trung vị cột `peak_rss_bytes` của `runs.csv` ở minsup thấp nhất của mỗi
CSDL.

```sh
RUN=results/raw/bbq-all-variants-cli-5repeat-20261117T041922Z
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_report_validation.py $RUN --language vi --out docs/report/figures
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_report_validation.py $RUN --out docs/report/figures/en
```

Lệnh thứ nhất tạo hình có nhãn tiếng Việt cho `main.tex`. Lệnh thứ hai tạo bản nhãn
tiếng Anh cho `main-en.tex`.

## Tạo lại hình thời gian chạy và hình độ dài giao dịch

[Bản ghi đợt đo thời gian](../runtime-curves-2026-11-17.md#reproduce) tạo
`results/figures/runtime/curves.csv`. Từ tệp đó, hai lệnh sau vẽ hai bản của hình thời gian
chạy:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.11.2 python scripts/plot_runtime_curves.py results/figures/runtime/curves.csv --language vi --out docs/report/figures
uv run --no-project --python 3.12 --with matplotlib==3.11.2 python scripts/plot_runtime_curves.py results/figures/runtime/curves.csv --out docs/report/figures/en
```

[Bản ghi độ dài giao dịch qua dòng lệnh](../bbq-width-cli-2026-11-28.md#reproduce) có lệnh
vẽ `width-curves.png` với `--language vi` và mặc định tiếng Anh theo cùng cách.

[Hướng dẫn ứng dụng ảnh](../../applications/image_patterns/README.md#reproduce-the-sensitivity-study)
có lệnh tạo bảng độ nhạy và hình đối chiếu Semeion. Thêm `--language vi` vào lệnh
`plot_image_evidence.py` để tạo bản tiếng Việt.
