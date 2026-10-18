---
title: Khai thác tập phổ biến
short_title: Tập phổ biến
label: dm-project-itemset
description: "Frequent itemset mining project: scratch reimplementation of one SPMF algorithm, experimental evaluation, and two mandatory applications."
---

# Khai thác tập phổ biến

Phạm vi Frequent Itemset Mining, nghiên cứu, cài đặt và đánh giá. Đồ án do các giảng
viên thực hành hướng dẫn và duy trì, với sự đóng góp của Th.S Nguyễn Thị Thu Hằng,
Th.S Nguyễn Ngọc Đức và Th.S Lê Nhựt Nam, thuộc Bộ môn Khoa học máy tính.

## Mục tiêu đồ án

Khai thác tập phổ biến, Frequent Itemset Mining, viết tắt FIM, là nền tảng của nhiều
bài toán khai phá dữ liệu quan trọng, từ luật kết hợp, association rules, phân tích
giỏ hàng, market basket analysis, cho đến phát hiện mẫu trong dữ liệu sinh học và
web. Đồ án này yêu cầu sinh viên chọn một thuật toán FIM cụ thể và tự cài đặt lại từ
đầu dựa trên mô tả gốc của nó, qua đó chứng minh hiểu biết nền tảng và khả năng tối
ưu hóa thực tế. Sau khi hoàn thành, sinh viên đạt được:

- Hiểu sâu thuật toán được chọn, gồm cấu trúc dữ liệu và độ phức tạp của nó, thông qua
  việc cài đặt lại từ mô tả trong bài báo gốc bằng Julia, được ưu tiên, hoặc Python.
- Kỹ năng thiết kế thực nghiệm, đo lường hiệu năng và so sánh với cài đặt tham chiếu
  SPMF.
- Kỹ năng viết báo cáo kỹ thuật theo chuẩn học thuật.

## Lựa chọn thuật toán

### Nguồn tham khảo

Sinh viên truy cập trang thư viện SPMF và chọn một thuật toán trong danh mục Frequent
Itemset Mining:

<https://www.philippe-fournier-viger.com/spmf/index.php?link=algorithms.php>

Các thuật toán hợp lệ bao gồm, nhưng không giới hạn ở, các nhóm sau:

| Nhóm | Thuật toán tiêu biểu | Độ khó |
|---|---|---|
| Tập phổ biến cơ bản | Apriori, Apriori-TID, AprioriClose | Trung bình |
| Tập phổ biến dạng cây | FP-Growth, FP-Growth*, HMine, Relim, SLPGrowth | Khó |
| Tập phổ biến dạng thẳng đứng | Eclat, dEclat, VIPER, Index-BitTableFI | Khó |
| Tập đóng, Closed | Charm, Charm-MFI, LCM, DCI_Closed, Zart | Rất khó |
| Tập tối đại, Maximal | GenMax, MAFIA, FPMFI | Rất khó |
| Tập generator | Apriori-Inverse, Pascal | Khó |

### Quy tắc lựa chọn

```{important}
- Mỗi nhóm chọn một thuật toán duy nhất. Được phép trùng thuật toán giữa các nhóm
  trong cùng lớp.
- Thuật toán phải có bài báo gốc, original paper, mà sinh viên có thể tải được, vì
  đây là tài liệu kỹ thuật chính mà sinh viên phải đọc và cài đặt dựa trên đó.
- Không sao chép mã nguồn từ SPMF viết bằng Java hoặc bất kỳ cài đặt sẵn có nào khác.
  Sinh viên phải tự viết từ đầu dựa trên mô tả trong bài báo.
- Nhóm có thể đề xuất một thuật toán FIM không có trong danh sách trên nếu giảng viên
  đồng ý.
```

## Nội dung báo cáo

Báo cáo được tổ chức thành 3 chương chính, mỗi chương tương ứng với một phần đánh giá
riêng.

### Chương 1: Cài đặt

```{note}
Ngôn ngữ ưu tiên: Julia từ phiên bản 1.9 trở lên. Sinh viên sử dụng Julia nên tận dụng
các đặc trưng ngôn ngữ như multiple dispatch, BitArray, generator expressions và
DataStructures.jl thay vì viết theo phong cách Python hoặc Java. Nếu dùng Python, yêu
cầu Python từ phiên bản 3.9 trở lên và chỉ được sử dụng numpy, pandas, bitarray.
Không được dùng mlxtend, efficient-apriori hay bất kỳ thư viện FIM nào.
```

Cài đặt lại từ đầu đòi hỏi nhóm đọc kỹ bài báo gốc, qua đó nắm chắc cấu trúc dữ liệu
và cách thuật toán sinh ra kết quả. Theo đó, nhóm hoàn thành dần các bậc yêu cầu sau:

- Cài đặt cơ bản: cài đặt đúng thuật toán, xuất ra tất cả frequent itemset và support
  tương ứng. Kết quả phải khớp hoàn toàn với SPMF trên cùng input.
- Tái tạo đúng kết quả: kiểm thử tự động, unit test, trên ít nhất 5 CSDL khác nhau.
  Báo cáo tỉ lệ đúng so với kết quả tham chiếu từ SPMF.
- Tối ưu hóa bộ nhớ và tốc độ: áp dụng ít nhất một kỹ thuật tối ưu phù hợp với thuật
  toán, ví dụ sử dụng bitset hoặc BitArray cho tidset, nén FP-tree, tỉa nhánh sớm. Đo
  lường và báo cáo mức cải thiện so với bản cơ bản.
- Xử lý đầu vào và đầu ra: hỗ trợ đọc file định dạng SPMF dạng `.txt`, mỗi dòng một
  itemset, các item cách nhau dấu cách, và xuất kết quả theo cùng định dạng. Thêm
  tham số dòng lệnh cho minsup và đường dẫn file.

### Chương 2: Thực nghiệm và đánh giá

Tập dữ liệu benchmark: sinh viên phải thực nghiệm trên ít nhất 4 tập dữ liệu benchmark
phổ biến trong cộng đồng FIM. Các tập dữ liệu có thể tải tại trang SPMF Datasets hoặc
FIMI Repository:

| Tập dữ liệu | Số giao dịch | Số items | Chiều rộng trung bình | Đặc điểm |
|---|---|---|---|---|
| Chess | 3.196 | 75 | 37.0 | Dày đặc, dense, itemset dài |
| Mushroom | 8.124 | 119 | 23.0 | Dày đặc, nhiều item |
| Retail | 88.162 | 16.47 | 10.3 | Thưa, sparse, thực tế |
| Accidents | 340.183 | 468 | 33.8 | Rất lớn, dày đặc |
| T10I4D100K | 100.000 | 870 | 10.1 | Tổng hợp, thưa |

Các bản lưu trữ ổn định dùng lâu dài của dữ liệu benchmark được host trên Hugging
Face hoặc Kaggle theo chính sách dữ liệu ở phần Tổ chức đồ án và nộp bài. Khi chuẩn bị
thực nghiệm, ưu tiên dùng các bộ dữ liệu đã có sẵn công khai trên hai nền tảng này
thay vì tự host dữ liệu mới, giúp nhóm giảm nhẹ phần công việc chuẩn bị.

Sinh viên phải thực hiện đầy đủ các thực nghiệm sau và trình bày bằng biểu đồ rõ ràng:

- Kiểm tra tính đúng đắn, Correctness: với mỗi tập dữ liệu, so sánh số lượng frequent
  itemset và support của từng itemset giữa cài đặt của nhóm và SPMF. Báo cáo tỉ lệ
  itemset khớp hoàn toàn. Nếu có sai lệch, phân tích nguyên nhân.
- Thời gian chạy theo minsup: với mỗi tập dữ liệu, vẽ đồ thị thời gian chạy theo
  minsup giảm dần với ít nhất 5 đến 7 điểm minsup khác nhau từ cao xuống thấp. So
  sánh đường cong của cài đặt nhóm với SPMF trên cùng đồ thị.
- Số lượng frequent itemset theo minsup: vẽ đồ thị số lượng frequent itemset được
  sinh ra theo minsup. Nhận xét mối quan hệ giữa minsup và output size, so sánh trên
  các tập dữ liệu dày và thưa.
- Sử dụng bộ nhớ: đo và báo cáo mức sử dụng RAM tối đa, peak memory, cho mỗi tập dữ
  liệu tại minsup trung bình. So sánh giữa bản cơ bản và bản tối ưu của nhóm.
- Khả năng mở rộng, Scalability: chọn một tập dữ liệu lớn như Retail hoặc Accidents.
  Tạo các tập con có kích thước 10%, 25%, 50%, 75%, 100% giao dịch. Vẽ đồ thị thời
  gian chạy theo kích thước CSDL. Nhận xét xu hướng tuyến tính hay phi tuyến.
- Ảnh hưởng của độ dài giao dịch trung bình: nếu thuật toán bị ảnh hưởng bởi độ dài
  giao dịch, thiết kế thực nghiệm minh chứng điều này bằng cách tạo CSDL tổng hợp với
  độ dài giao dịch tăng dần.

Với mỗi thực nghiệm, sinh viên trình bày số liệu kèm giải thích kết quả dựa trên
mô tả thuật toán trong bài báo gốc và phân tích độ phức tạp của nhóm, để từ đó hiểu
rõ hành vi của thuật toán trên từng loại dữ liệu, xác định điểm mạnh và điểm yếu của
cài đặt so với SPMF, và đề xuất ít nhất 2 hướng tối ưu hóa cụ thể có thể áp dụng
tiếp theo.

### Chương 3: Ứng dụng thực tế

Sinh viên thực hiện hai ứng dụng, trong mỗi ứng dụng nhóm chọn 1 trong 2 hướng được
cung cấp để thực hiện. Tất cả kết quả của hai ứng dụng đều phải thu được bằng chính
cài đặt của nhóm, không dùng kết quả từ thư viện FIM có sẵn.

Mỗi ứng dụng bắt đầu từ quyết định biến đổi dữ liệu ban đầu thành giao dịch, một
quyết định đòi hỏi nhóm phân tích xem cách trích xuất nào phù hợp nhất với thuật toán
đã chọn. Phần chuyển đổi này được cài đặt cùng mã chuẩn bị dữ liệu trong notebook.

**Ứng dụng 1, chọn 1 trong 2 hướng:**

- Hướng phân tích giỏ hàng, Market Basket Analysis: dùng tập dữ liệu bán lẻ thực như
  Retail, Groceries, hoặc tự tìm. Từ frequent itemset, sinh luật kết hợp, association
  rules, với support của $X$ đạt ngưỡng minsup và confidence của luật đạt ngưỡng
  minconf. Trình bày top-10 luật theo lift và giải thích ý nghĩa kinh doanh.
- Hướng phát hiện mẫu trong log hệ thống: áp dụng cho tập log sự kiện, event log. Tìm
  các tổ hợp sự kiện xuất hiện cùng nhau thường xuyên. Thảo luận khả năng phát hiện
  lỗi hay hành vi bất thường.

**Ứng dụng 2, chọn 1 trong 2 hướng:**

- Hướng phân tích dữ liệu sinh học: áp dụng cho dữ liệu genome hoặc protein sequence
  đã mã hóa thành dạng transaction. Thảo luận ý nghĩa sinh học của các pattern được
  tìm thấy.
- Hướng khai thác mẫu trực quan trên dữ liệu hình ảnh: chọn một tập dữ liệu hình ảnh
  phù hợp. Mỗi ảnh được chuyển thành một giao dịch trên bộ đặc trưng trực quan qua
  các kỹ thuật như bag of visual words, tức trích descriptors, dựng codebook bằng
  k-means, sao cho mỗi ảnh trở thành một giao dịch các visual words. Chạy chính cài
  đặt
  của nhóm để khai thác các itemset trực quan phổ biến. Thảo luận cách ứng dụng các
  mẫu trực quan phổ biến tìm được để phân tích dữ liệu hình ảnh hoặc để huấn luyện
  thêm các mô hình khác.

## Yêu cầu kỹ thuật

Về mã nguồn:

- Ngôn ngữ và thư viện: theo quy định ở Chương 1.
- Reproducibility: đặt seed ngẫu nhiên cố định. Mọi kết quả phải tái sản xuất được
  khi chạy lại.
- Kiểm thử: có bộ unit test tự động. Chạy `julia --project test/runtests.jl` hoặc
  `pytest` phải pass toàn bộ.
- Hiệu năng: cài đặt Julia phải tránh các performance anti-patterns: không dùng global
  variables không định kiểu, không dùng abstract type trong hot loop, tận dụng
  `@inbounds` và `@simd` khi phù hợp.
- Tài liệu: README phải có hướng dẫn cài đặt môi trường, cách chạy, ví dụ sử dụng cụ
  thể, và link công khai đến demo notebook trên Google Colab.

Về báo cáo:

- Viết bằng tiếng Việt. Thuật ngữ kỹ thuật tiếng Anh giữ nguyên lần đầu, có chú
  thích.
- Định dạng: từ 10 đến 15 trang theo mẫu **IEEE conference format** được cung cấp tại
  <https://www.ieee.org/conferences/publishing/templates>, không kể tài liệu tham
  khảo và phụ lục. Báo cáo file `Report.pdf` đặt trong thư mục `docs/`.
- Mọi công thức toán phải dùng ký hiệu chuẩn và được giải thích biến.
- Mọi hình vẽ, bảng biểu phải có chú thích, caption, và được tham chiếu trong văn
  bản.
- Mục Tài liệu tham khảo phải bao gồm bài báo gốc của thuật toán và ít nhất 3 tài
  liệu liên quan khác.

## Tổ chức đồ án và nộp bài

Nhóm nộp **duy nhất một link trên Moodle**: link trỏ đến public GitHub repository của
nhóm. Repository tổ chức theo cấu trúc gợi ý dưới đây, với thư mục `Group_ID` chính
là repo root:

- Repository công khai: repo duy trì lịch sử commit minh bạch, grader truy xuất quy
  trình làm việc qua commit history.
- Demo notebook chạy trên Google Colab: public link đặt trong README. Notebook phải
  chạy sạch trước khi nộp, phần thực nghiệm nào lỗi runtime sẽ không được chấm phần
  tương ứng.

:::{note}
Chạy Julia trên Google Colab: Colab chính thức chỉ hỗ trợ kernel Python theo trang FAQ
của Google, nên nhóm viết Julia dựng notebook demo trên kernel Python. Ô khởi tạo tải
bản Julia chính thức, các ô sau gọi Julia qua lệnh shell:

```
!curl -fsSL https://julialang-s3.julialang.org/bin/linux/x64/1.11/julia-1.11.4-linux-x86_64.tar.gz -o julia.tar.gz
!tar -xzf julia.tar.gz -C /usr --strip-components 1
!julia --version
!julia --project=. demo.jl --minsup 0.01 data/benchmark.txt
```

Phiên bản mới nhất được cập nhật tại <https://julialang.org/downloads/>.
:::

- Kiểm thử phải pass: chạy bộ test và đính kèm output của lần chạy cuối vào README.
- Dữ liệu benchmark vượt kích thước repository: host trên Hugging Face hoặc Kaggle,
  link công khai trong README. Mã chuẩn bị dữ liệu nằm trong demo notebook trên
  Colab, viết trực tiếp hoặc import từ file phụ trợ trong repo.
- Đồ án này nằm trong phạm vi phần thi vấn đáp cuối kỳ, trong đó nhóm trình bày và
  trả lời câu hỏi về các đồ án đã thực hiện trong học kỳ.

Cấu trúc thư mục gợi ý:

```
Group_ID/
├── README.md                 # thanh vien, huong dan chay, link Colab va tai nguyen
├── Project.toml              # Julia, hoac requirements.txt cho Python
├── src/
│   ├── algorithm/            # cai dat chinh
│   ├── structures.jl         # cau truc du lieu
│   └── utils.jl              # tien ich
├── tests/
│   ├── test_correctness.jl
│   └── test_benchmark.jl
├── data/
│   ├── toy/                  # CSDL nho de kiem thu nhanh
│   └── benchmark/            # CSDL benchmark, ban lon host tren Hugging Face hoac Kaggle
├── notebooks/
│   └── demo.ipynb            # demo notebook chay tren Google Colab
└── docs/
    └── Report.pdf            # bao cao, quy cach o muc Ve bao cao
```

## Tiêu chí chấm điểm

| Tiêu chí | Điểm |
|---|---|
| **Chương 1: Cài đặt** | **25% đến 30%** |
| Kết quả đúng so với SPMF | 10% |
| Unit tests tự động đầy đủ | 5% |
| Tối ưu hóa có đo lường | 10% với Julia, 5% với Python |
| I/O chuẩn SPMF và tham số dòng lệnh | 5% |
| **Chương 2: Thực nghiệm và đánh giá** | **20%** |
| Kiểm tra correctness trên benchmark | 5% |
| Biểu đồ thời gian, bộ nhớ, scalability | 10% |
| Phân tích và đề xuất tối ưu hóa | 5% |
| **Chương 3: Ứng dụng thực tế** | **50%** |
| Ứng dụng 1, chọn 1 trong 2 hướng: giỏ hàng hoặc log hệ thống | 25% |
| Ứng dụng 2, chọn 1 trong 2 hướng: sinh học hoặc mẫu trực quan hình ảnh | 25% |
| **Tổng tối đa** | **95% đến 100%** |

Rubric chấm điểm Chương 1:

- Xuất sắc: kết quả khớp SPMF 100%, code bằng Julia, tối ưu hóa rõ ràng và đo lường
  chứng minh cải thiện.
- Tốt: kết quả khớp SPMF từ 95% trở lên, có tối ưu nhưng chưa đo lường. Code bằng
  Python hoặc Julia.
- Đạt: kết quả khớp SPMF từ 80% trở lên trên các CSDL nhỏ. Code bằng Python hoặc
  Julia.
- Chưa đạt: kết quả chưa đúng, hoặc phát hiện sao chép mã nguồn từ cài đặt có sẵn.

Rubric chấm điểm Chương 3:

- Xuất sắc: cả hai ứng dụng chạy bằng chính cài đặt của nhóm trên dữ liệu thực, kết
  quả
  tái thực hiện được qua notebook demo, diễn giải ý nghĩa sâu.
- Tốt: ứng dụng chạy đúng nhưng diễn giải còn nông.
- Đạt: ứng dụng chạy một phần hoặc thiếu bằng chứng tái thực hiện.
- Chưa đạt: dùng kết quả từ thư viện FIM có sẵn, hoặc ứng dụng không chạy được.

```{note}
Lưu ý quan trọng:

- Liêm chính học thuật: sao chép mã nguồn từ bất kỳ nguồn nào như SPMF, GitHub,
  ChatGPT, dẫn đến điểm 0 toàn bộ đồ án.
- Sử dụng AI: cho phép sinh viên dùng bất kỳ AI hỗ trợ viết code nào như Claude,
  Copilot, Codex, Cursor, nhưng sinh viên phải hiểu và có khả năng giải thích được
  bài làm.
```
