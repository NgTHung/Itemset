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
