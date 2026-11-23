# Kết quả thực nghiệm Week 3 của Phat, 08/11/2026

So sánh bộ nhớ giữa hai biến thể Eclat cần chứng minh chúng tạo cùng tập mục và support. Hồ sơ này ghi lại phép so với SPMF, phép đo peak RSS và khảo sát độ nhạy Semeion trên dữ liệu đã xác minh. Các bảng, hình và lệnh tương ứng nằm trong báo cáo và notebook của nhóm.

## Dữ liệu và môi trường

Miner baseline và optimized đều lấy từ `8c043fb9ca7cc4ee18ea191c55161c56cd22d0f4`. Lần đo RAM chạy khi các file ứng dụng và tài liệu đang sửa. `source-checksums.toml` ghi hash miner và harness để đối chiếu với run correctness. Môi trường là Windows 11, AMD Ryzen 5 6600H, khoảng 15,2 GiB RAM, Julia 1.13.2 một luồng, Java Temurin 25.0.4.1 và SPMF 2.66. JAR có SHA-256 `4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a`. Manifest và log thực nghiệm là nguồn của các phiên bản và hash đầu vào. [Giao thức benchmark](../experiments/README.md)

## Độ đúng của hai biến thể

Ma trận có 33 điểm và một lần chạy mỗi biến thể tại mỗi điểm. Cả 66 lần khớp hoàn toàn với SPMF. Chess, Mushroom và Accidents mỗi bộ có bảy ngưỡng. Retail và T10I4D100K mỗi bộ có sáu ngưỡng. Đầu ra SPMF có từ 15 đến 574.431 itemset sau khi bỏ các dòng metadata. Tổng hợp ghi số khóa tham chiếu, số khóa đầu ra Julia, tử số và mẫu số match rate, số tập thiếu, thừa, lặp và sai support. SPMF chạy riêng cho mỗi điểm và cả hai biến thể dùng cùng reference. [Cấu hình](../experiments/configs/correctness.toml)

## Bộ nhớ đỉnh

Mỗi biến thể chạy năm lần tại một ngưỡng giữa trên mỗi bộ dữ liệu. Cả 50 đầu ra đo RAM khớp SPMF. Peak RSS là `PeakWorkingSetSize` do Windows ghi cho tiến trình mới, gồm khởi động, đọc input, mining và ghi output. Kiểm chứng SPMF chạy ngoài ranh giới đo. Tỷ lệ lấy trung vị baseline chia trung vị optimized. [Cấu hình](../experiments/configs/peak-memory.toml)

| Dataset | Minsup | Baseline median MiB | Optimized median MiB | Tỷ lệ |
| --- | ---: | ---: | ---: | ---: |
| Chess | 0,75 | 217,5 | 193,7 | 1,123 |
| Mushroom | 0,25 | 216,8 | 188,4 | 1,151 |
| Retail | 0,0025 | 229,2 | 215,1 | 1,065 |
| T10I4D100K | 0,001 | 253,4 | 218,4 | 1,160 |
| Accidents | 0,8 | 582,2 | 466,9 | 1,247 |

## Độ nhạy của ứng dụng ảnh

Ba cấu hình từ điển 16, 24 và 32 từ dùng cùng seed, 25 vòng tối đa, patch 4×4, min ink 2 và cutoff bình phương 1,0. Mỗi cấu hình có năm ngưỡng. K=24 tạo 6, 18, 35, 43 và 46 mẫu theo thứ tự minsup giảm từ 20% xuống 5%. Bộ ba `{4,8,13}` có support 90, vượt ngưỡng đếm 88 và thấp hơn ngưỡng 96. Khi so giữa các từ điển, đọc hình và tọa độ patch trong từng run vì ID phụ thuộc tâm cụm. Hình đối chiếu tái tạo từ pixel nguồn, dùng ảnh 44 có đủ ba từ và ảnh 41 cùng nhãn thiếu từ 4. [Phần ảnh trong báo cáo](report/sections/applications.tex)

## Tái tạo kết quả

Chạy từ repository root. Dùng Java 25 và JAR đã xác minh theo quy trình SPMF. Các thư mục kết quả trong lệnh phải mới. [Quy trình SPMF](../tools/spmf/README.md)

```sh
julia --startup-file=no --project=. experiments/prepare_benchmarks.jl
julia --startup-file=no --project=. experiments/run.jl experiments/configs/correctness.toml --out results/raw/week3-correctness
julia --startup-file=no --project=. experiments/run.jl experiments/configs/peak-memory.toml --out results/raw/week3-memory
julia --startup-file=no --project=. scripts/mine_image_patterns.jl data/raw/semeion/semeion.data results/raw/week3-k24 --vocabulary-size 24 --minsup 0.2,0.1,0.06,0.055,0.05
```

Đổi K và đường dẫn output cho các run K=16 và 32. Hai script Python đọc artifact có sẵn. Dùng Python 3.11 trở lên và Matplotlib khi tạo hình.

```sh
python scripts/summarize_validation.py correctness results/raw/week3-correctness --out results/raw/week3-correctness.tsv
python scripts/summarize_validation.py memory results/raw/week3-memory --out results/raw/week3-memory.tsv --figure results/figures/peak-memory.png
python scripts/plot_image_evidence.py data/raw/semeion/semeion.data results/raw/week3-k24 results/figures/semeion-source-contrast.png
```

Run ngày 08/11 nằm ở `results/raw/week3/`. Hai thư mục `correctness/` và `memory/` giữ config, environment, source checksums, log và các kết quả so sánh theo lần chạy. `correctness/` giữ đủ file itemset của Julia và SPMF. `memory/` giữ log đo, reference và diff TOML, rồi xóa file Julia đã qua so khớp để giảm dung lượng. Các thư mục `sensitivity-k16/`, `sensitivity-k24/`, `sensitivity-k32/` giữ đủ transaction, map, ảnh, patch và manifest.

## Notebook và báo cáo

Tất cả cell code của `demo.ipynb` chạy tuần tự trong một tiến trình Julia mới trên Windows với dữ liệu đã cache và xác minh. Suite đạt 5.074/5.074. Pipeline giỏ hàng tạo 39.516 giỏ và 455 luật tại cấu hình mặc định. Pipeline Semeion tạo 6, 18 và 46 mẫu ở ba ngưỡng mặc định. Smoke Chess 90% khớp hoàn toàn với SPMF và đọc được peak RSS dương của cả hai biến thể. Log là `results/raw/week3/notebook-local.log`. Báo cáo biên dịch thành công với editor. [Notebook](../notebooks/demo.ipynb) · [Báo cáo](report/main.tex)

Lần chạy này dùng cache và tiến trình cục bộ. Bước nghiệm thu của DAT-25 là chạy hosted Colab từ runtime sạch sau khi nhận hai module đã kiểm thử của Hung và Thien, rồi xác nhận quyền đọc link. Trạng thái phát hành baseline và optimized được theo dõi trên các issue của Hung. [DAT-25](https://linear.app/nguyen-tuan-hung/issue/DAT-25) · [DAT-13](https://linear.app/nguyen-tuan-hung/issue/DAT-13) · [DAT-17](https://linear.app/nguyen-tuan-hung/issue/DAT-17)
