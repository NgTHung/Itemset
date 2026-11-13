# Kiểm chứng Application 2 trên Colab, 13/11/2026

Các mẫu thị giác cần truy về được ảnh nguồn và giữ đúng support khi chạy trên môi trường khác. Bản ghi này kiểm chứng ứng dụng Semeion của Phat trên hosted Colab, bao gồm phân tích theo nhãn và biểu diễn đặc trưng itemset. Phạm vi triển khai gồm Application 2 và các phần correctness, memory, tích hợp notebook của Phat.

## Mã nguồn và môi trường

Revision chạy là `5bd69f140f7e2c9562b6b13cbc64bffdfae335a6` trên nhánh `feat/dat-38-week3-notebook`, trong [PR #31](https://github.com/NgTHung/Itemset/pull/31). Runtime CPU Linux được tạo bằng `google-colab-cli 0.8.0`. Runner tải bản Julia 1.13.2 và Java Temurin 25.0.5 chính thức, xác minh SHA-256 trước khi giải nén. Julia chạy một luồng, seed 42. JAR SPMF 2.66 được xác minh theo [giao thức tham chiếu](../tools/spmf/README.md).

Các cell Julia chạy theo đúng thứ tự nguồn trong một tiến trình mới. Repo được clone ở revision cố định, depot Julia và các thư mục dữ liệu được tạo mới. Tải dữ liệu công khai phải qua kiểm tra checksum của manifest. Nguồn HTTPS FIMI cho Mushroom trả đúng bytes đã pin, khắc phục lỗi hostname TLS của nguồn RPI trong lần thử trước.

## Kết quả kiểm tra

| Kiểm tra | Kết quả |
| --- | --- |
| Suite Julia trên Windows 1.13.2 | 5.093/5.093 pass |
| Suite Julia trên Colab 1.13.2 | 5.093/5.093 pass |
| Kiểm thử Python runner | 4/4 pass |
| Code cells trên hosted runtime | 12/12 hoàn tất |
| CI của revision chạy | Ubuntu và Windows, Julia 1.12.6 và 1.13.2, cả bốn job pass |
| Báo cáo chỉnh sửa | Compiler trong editor biên dịch thành công |
| Smoke Chess 90% | Baseline và optimized khớp đầy đủ map SPMF |
| Peak RSS của smoke | Baseline 305.385.472 byte; optimized 285.691.904 byte |

RSS của smoke gồm cả tiến trình con theo [giao thức đo](../experiments/README.md). Hai giá trị này kiểm tra khả năng đo trên Colab, không thay thế chuỗi benchmark đầy đủ trong [hồ sơ Week 3](phat-week-3-results-2026-11-08.md).

## Tái lập kết quả ảnh

Ứng dụng giữ 1.593 ảnh, 18.386 patch, 24 visual word và 11 transaction rỗng. Các map ở minsup 20%, 10% và 5% có lần lượt 6, 18 và 46 itemset. So sánh toàn bộ khóa và support của từng map với hồ sơ Week 3 cho kết quả bằng nhau. Đây là phép so với các map đã kiểm chứng trước đó; smoke SPMF trực tiếp của lượt Colab dùng Chess.

Codebook trên Colab có SHA-256 `391c636199e358743107a181ec3b7d5c2bdf115a3ef84d90d6db83cb99d1f1c4`, trùng bản Windows Julia 1.13.2. Lần thử trước trên Julia 1.12.6 cho 6/20/56 mẫu, nên phiên bản Julia là một phần của cấu hình tái lập seed.

`label_frequencies.tsv` ghi đầy đủ mẫu số, support, tỷ lệ và ID nguồn cho mỗi nhãn của mọi mẫu. Với cặp `{8,13}`, tổng support là 330 và tổng mẫu số là 1.593; chữ số 3 có 69/159 ảnh khớp, chữ số 4 có 9/161 ảnh khớp. Ma trận đặc trưng có kích thước 1.593 × 46. Tổng từng cột bằng support của mẫu tương ứng. Ví dụ `{8,13}` với ba cột `{13}`, `{8,13}`, `{4,8,13}` cho `[1,1,0]`; ảnh rỗng cho `[0,0,0]`.

[Phần ứng dụng trong báo cáo](report/sections/applications.tex) giải thích truy xuất ảnh theo tổ hợp nét, so sánh tần suất theo nhãn, kiểm tra encoder và cách đưa mẫu vào mô hình tiếp theo. Codebook của kết quả này học trên toàn bộ dữ liệu để mô tả. Hướng classifier chỉ được trình bày như một thiết kế mở rộng: chia tập trước, fit codebook và khai thác mẫu trên training, rồi cố định phép biến đổi cho test. Bản ghi không báo accuracy hay macro-F1 chưa được đo.

## Lệnh và bằng chứng

[Quy trình CLI](../notebooks/README.md#run-through-the-colab-cli) mô tả cách tạo runtime, upload runner/JAR, chạy launcher, tải ZIP và dừng runtime. Đặt revision trong launcher bằng SHA nêu trên. Các lệnh kiểm tra cục bộ chạy từ repo root:

```sh
julia --startup-file=no --project=. test/runtests.jl
python tests/colab_runner.py
git diff --check
```

Hồ sơ cục bộ nằm trong `results/raw/colab-cli-2026-11-13/`: `pinned-cleanrun.zip`, `pinned-cli-retry.log`, `pinned-validation.json` và `verify_pinned.py`. ZIP giữ nguồn từng cell, log, manifest, các map đầy đủ, ảnh/patch nguồn, bảng theo nhãn và output so sánh/đo bộ nhớ. Bản ZIP được đính kèm trong Resources của [DAT-25](https://linear.app/nguyen-tuan-hung/issue/DAT-25), với SHA-256 `b6355ef88e827d53e16356673cf93a40477640459281dd652750c14f7beb98c1`. Mọi hash artifact trong ZIP và mining manifest đều được xác minh sau khi tải. Runtime được dừng sau khi kiểm tra.

Hosted CLI xác nhận phần tính toán. Kiểm tra hiển thị tương tác trong frontend Julia của Colab là một bước riêng. DAT-25 giữ In Progress vì còn bàn giao module được chủ sở hữu xác nhận ở DAT-36/DAT-37. Không thay đổi trạng thái các task của Hung hoặc Thien; review của người được phân công giữ ở [DAT-40](https://linear.app/nguyen-tuan-hung/issue/DAT-40).
