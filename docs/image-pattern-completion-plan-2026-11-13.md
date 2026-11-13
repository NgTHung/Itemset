# Kế hoạch hoàn thiện phần ứng dụng mẫu ảnh, 13/11/2026

Các frequent itemset Semeion đã có ảnh và patch nguồn để kiểm tra. Báo cáo cần nối các kết quả đó với cách dùng chúng để phân tích dữ liệu ảnh và tạo đặc trưng cho mô hình tiếp theo. Kế hoạch này bổ sung phần thảo luận theo đề bài, một ví dụ phân tích có thể tái tạo và quy trình nghiệm thu Colab.

## Phạm vi và điểm xuất phát

Chọn Semeion với 1.593 ảnh nhị phân 16×16. Descriptor là patch 4×4, codebook chuẩn có 24 tâm k-means và seed 42. Mỗi ảnh là một tập word ID riêng biệt. Eclat của nhóm tạo map itemset/support. Các artifact nguồn và phân tích độ nhạy có trong hồ sơ Week 3. [Kết quả Week 3](phat-week-3-results-2026-11-08.md)

Đề bài yêu cầu thảo luận cách dùng mẫu để phân tích ảnh hoặc huấn luyện mô hình khác. Bản giao tối thiểu gồm phần viết có công thức, ví dụ trên dữ liệu thật và các giới hạn. Chạy một classifier là giai đoạn mở rộng sau khi phần bắt buộc và nghiệm thu notebook hoàn tất. [Yêu cầu ứng dụng ảnh](assignment.md)

## Bước 1 · Bổ sung thảo luận ứng dụng vào báo cáo

Thêm đoạn sau phần kết quả và độ nhạy trong `docs/report/sections/applications.tex`. Dùng các mẫu đã có support và ảnh hỗ trợ làm ví dụ. Mỗi hình được dẫn chiếu và giải thích ý nghĩa theo phép mã hóa.

| Cách dùng | Đầu vào | Thao tác và đầu ra | Bằng chứng cần đưa vào báo cáo |
| --- | --- | --- | --- |
| Tìm ảnh có chung nét | Một itemset, ví dụ `{8,13}` | Quét transactions, trả ID và thumbnail các ảnh chứa đủ hai word | Support 330 và danh sách ID nguồn từ run đã kiểm chứng |
| So sánh theo nhãn | Itemset và label 0–9 | Đếm ảnh hỗ trợ trong từng nhãn rồi chia số ảnh của nhãn đó | Bảng số đếm, mẫu số và tần suất, kèm ảnh khớp/không khớp cùng nhãn |
| Kiểm tra encoder | Ảnh không khớp và word còn thiếu | Đối chiếu patch nguồn, assignment và distance cutoff | Ví dụ ảnh 44 và 41 cùng nhãn 2 cho `{4,8,13}` |
| Tạo đặc trưng cho mô hình | Danh sách frequent itemset đã chọn | Mã hóa ảnh thành vector nhị phân hiện diện của từng itemset | Định nghĩa công thức, ví dụ vector và quy trình train/evaluation |

Giải thích một word thiếu bằng điều kiện gán cụm và cutoff. Nêu ảnh hưởng của lưới patch, việc mất vị trí, số lần xuất hiện và việc các word phổ biến có mặt trong nhiều nhãn. Khi so các nhãn, ghi cả số đếm và tỷ lệ để người đọc kiểm tra mẫu số. [Phần ảnh hiện có](report/sections/applications.tex)

Tiêu chí đạt là người đọc lần từ ứng dụng đề xuất về được mẫu thật, support, danh sách ảnh và hình nguồn. Biên dịch `docs/report/main.tex` bằng compiler trong editor sau khi sửa.

## Bước 2 · Thêm ví dụ phân tích vào notebook

Cell dùng lại kết quả `mining_main` và `supporting_images.tsv`. Hiển thị một mẫu, support tổng, số ảnh từng label, tỷ lệ từng label và tối đa vài ảnh đối chiếu có source ID. Chọn mẫu theo quy tắc có sẵn trong ứng dụng để kết quả lặp lại được. Dùng functions đã test trong `applications/image_patterns/`, giữ notebook là điểm điều phối. [Code chọn mẫu](../applications/image_patterns/mining.jl)

Nếu cần thêm hàm đếm theo label hoặc biến đổi đặc trưng, viết test trước trong `tests/`. Fixture phải có một ảnh chứa đủ mẫu, một ảnh chứa một phần mẫu, một ảnh rỗng và ID nguồn khác vị trí hàng. Kiểm tra support trong bảng phải bằng chiều dài danh sách source ID. Chạy các test liên quan và suite repo sau khi triển khai.

Tiêu chí đạt là từ runtime sạch, người chạy tái tạo được bảng và ảnh từ input đã xác minh. Các tần suất ở đây mô tả dataset và encoding đã fit.

## Bước 3 · Mô tả cách tạo đặc trưng itemset

Với danh sách mẫu `P = (p₁, …, pₘ)` và transaction của ảnh `Tᵢ`, định nghĩa `zᵢⱼ = 1` khi `pⱼ` là tập con của `Tᵢ`, bằng 0 ở trường hợp còn lại. `i` là chỉ số ảnh, `j` là chỉ số mẫu, `m` là số mẫu trong danh sách cố định. Mỗi ảnh trở thành vector m chiều. Ví dụ với `P = ({13}, {8,13}, {4,8,13})`, transaction `{8,13}` cho vector `[1,1,0]`, còn ảnh rỗng cho `[0,0,0]`.

Vector này đưa các tổ hợp word vào mô hình dưới dạng feature hiện diện. Trình bày cách kết hợp với vector BoVW và cách lựa chọn mẫu theo min count cùng nguồn dữ liệu training. Các mẫu dài hơn có thể hiếm, làm tăng số chiều và tạo feature trùng thông tin. Hiệu quả dự đoán cần được đo trên tập ảnh giữ riêng.

Tiêu chí đạt của phần bắt buộc là công thức, ví dụ tính tay, nơi dùng nhãn và quy trình tránh rò rỉ dữ liệu được viết rõ. Nội dung này đáp ứng yêu cầu thảo luận hướng huấn luyện mô hình khác.

## Bước 4 · Thực nghiệm classifier nếu triển khai mở rộng

1. Chốt trước một stratified train/test split bằng RNG seed 42, lưu source IDs theo từng split. Giữ nhãn chỉ cho bước chia dữ liệu và huấn luyện/evaluation. Semeion thiếu person ID trong input này, nên báo rõ cách chia ảnh và giới hạn kiểm soát người viết.
2. Fit codebook bằng patches của training images. Dùng cùng tâm và cutoff để encode train và test. Khai thác itemset bằng Eclat chỉ trên training transactions. Chốt thứ tự cột feature từ các mẫu training và giữ các ảnh rỗng trong evaluation.
3. So sánh majority-class baseline, vector BoVW presence và vector itemset presence. Có thể dùng cùng một nearest-centroid classifier tự viết bằng Julia standard libraries cho hai vector để giữ phép so thống nhất. Nếu chọn thư viện bổ sung, thực hiện bước phê duyệt dependency của nhóm.
4. Báo accuracy, macro-F1, confusion matrix, số ảnh và số feature. Giữ cùng split và classifier trong phép so. Nếu chọn K, minsup hoặc feature bằng validation, tạo validation từ training rồi giữ test tới lần đánh giá cuối.
5. Lưu split IDs, codebook, danh sách itemset, dự đoán từng ảnh, tham số, revision, hash và kết quả. Phân tích các nhầm lẫn với ảnh nguồn. Viết kết luận theo kết quả đo.

Test cho phần này gồm mapping cột ổn định, ảnh rỗng thành vector 0, phép subset đúng, transform dùng vocabulary cố định và các source ID của train/test không giao nhau. Model fit nhận riêng dữ liệu training. Bàn giao classifier sau khi có đủ bảng và log tái tạo.

## Bước 5 · Nghiệm thu Colab qua CLI

CLI đã cài là `google-colab-cli 0.8.0` trong Python Microsoft Store. Ngày 13/11, `colab sessions` dùng được sau khi người dùng đăng nhập. Một CPU runtime tạm đã thực thi `smoke.py`, trả `ITEMSET_COLAB_SMOKE_OK` và tự dừng. Runtime là Linux x86_64, Python 3.13.18 và có Julia ở `/usr/local/bin/julia`. Log cục bộ ở `results/raw/colab-cli-2026-11-13/smoke.log`.

Runtime có Julia 1.12.6. Khi in log có dấu ✓, CLI trên Windows gặp lỗi encoding cp1252. Trước khi chạy các lệnh CLI trong PowerShell, bật UTF-8 cho tiến trình Python. Nếu CLI mất kết nối trong lúc thực thi, kiểm tra log và trạng thái runtime trước khi gửi lại job để tránh hai lượt chạy chồng nhau.

```powershell
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
```

CLI thực thi Python, còn các cell trong notebook dự án là Julia. Lần thử đầy đủ dùng một Python runner để clone revision `33def44`, chuẩn bị Java/SPMF đã xác minh, gọi một tiến trình Julia mới và thực thi các cell Julia theo đúng thứ tự nguồn. Thu log cell, Julia/Java versions, checksum notebook và artifacts rồi tải về. Cách chạy này tạo bằng chứng hosted computation trên Colab. Kiểm tra hiển thị tương tác của notebook Julia trong trình duyệt là một bước nghiệm thu riêng.

Lần thử đầy đủ đã qua 5.074/5.074 tests trên Julia 1.12.6, rồi dừng ở cell chuẩn bị benchmark vì nguồn Mushroom `cs.rpi.edu` có chứng chỉ không khớp hostname. Trước lần clean-run toàn notebook tiếp theo, thêm một nguồn HTTPS có chứng chỉ hợp lệ và bytes khớp SHA-256 đã pin vào manifest Mushroom. Kiểm tra tải mới trên Colab, rồi chạy lại toàn bộ cell. Giữ nguyên checksum đầu vào trong phép so với bằng chứng cũ. Log gốc và lỗi được giữ trong `results/raw/colab-cli-2026-11-13/`.

Lần chạy riêng ba cell Semeion và SPMF/RSS hoàn tất trên Colab. Tải `image-module.zip` về và xác minh hash của từng artifact theo manifest. Kết quả encoding trên Julia 1.12.6 khác lần chạy Julia 1.13.2, nên bước tái lập bảng cũ cần pin Julia 1.13.2 trên runtime. Dùng bản phân phối Linux x86_64 chính thức, xác minh SHA-256, đặt đường dẫn Julia cố định cho runner, rồi so map và hash codebook với bằng chứng đã công bố. Ghi riêng kết quả kiểm tra khả năng chạy trên 1.12.6 và kết quả tái lập trên 1.13.2.

| Môi trường | Ảnh rỗng | Itemset tại 20% / 10% / 5% |
| --- | ---: | --- |
| Windows, Julia 1.13.2, bằng chứng Week 3 | 11 | 6 / 18 / 46 |
| Colab Linux, Julia 1.12.6, lần thử CLI | 8 | 6 / 20 / 56 |

Hai lần dùng cùng source revision cho ứng dụng và cùng tham số nhưng môi trường thực thi khác nhau. Cả hai lần giữ 1.593 ảnh, 18.386 patch và 24 word được sử dụng. Smoke Chess trên Colab khớp SPMF cho cả hai biến thể và có peak RSS dương. Hồ sơ đã tải nằm trong `image-module.zip`, SHA-256 `670fea6d817f072752601fddd3792f13cb3580a081bf797d0a13bf0099e7af49`. Hai runtime CPU do lần thử tạo đã được dừng sau khi thu output.

| Điểm kiểm tra | Điều kiện đạt |
| --- | --- |
| Runtime | Có output từ Colab, ghi OS và Julia version, source revision đúng |
| Tests | Suite hoàn tất với exit code 0 và tổng pass được ghi |
| Ứng dụng ảnh | Mã hóa 1.593 ảnh, có maps cùng source-image evidence |
| Giỏ hàng | Input được lấy từ nguồn công khai, checksum đúng và chạy Eclat nhóm |
| SPMF/RSS smoke | Cả hai biến thể khớp reference, RSS dương, ranh giới đo rõ |
| Log và artifacts | Có `result.json`, log từng cell, ZIP tải về và hash kiểm tra |
| Notebook hợp nhất | Nhận module DAT-36/DAT-37 đã kiểm thử, kiểm tra thứ tự cell và link đọc công khai |

Sau khi đủ các tiêu chí DAT-25, cập nhật README với link notebook và hồ sơ clean-run, đính kèm bằng chứng vào Linear và yêu cầu review theo phân công. [DAT-25](https://linear.app/nguyen-tuan-hung/issue/DAT-25)

## Thứ tự bàn giao

Hoàn tất phần viết và ví dụ phân tích ở bước 1–3, đồng thời xử lý hosted run ở bước 5. Bàn giao revision, lệnh, bảng và hình cho Thien tích hợp báo cáo. Ghi rõ phạm vi chạy thực tế trong Linear. Bước classifier có thể triển khai sau khi phần bắt buộc và notebook đã nghiệm thu.
