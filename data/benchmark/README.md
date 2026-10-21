# Benchmark data

The experiments measure the miner on four standard frequent-itemset databases: Chess, Mushroom, Retail, and T10I4D100K. Every chart and every SPMF comparison must use the same bytes, so each dataset is identified by the SHA-256 of its text file instead of by its name. The files stay out of Git, and [manifest.toml](manifest.toml) records their sources, checksums, statistics, origin, and terms of use.

## Prepare

```sh
julia --startup-file=no --project=. experiments/prepare_benchmarks.jl
```

The script downloads each file, checks its SHA-256, recomputes its statistics with `read_transactions`, and moves it into this folder only when both checks match the manifest. It tries the sources in manifest order, so a dead mirror falls back to the next one. A verified file is reused on the next run. Pass dataset names to prepare a subset.

## Datasets

| Dataset | Transactions | Items | Mean width | Max width | Type |
|---|---|---|---|---|---|
| chess | 3,196 | 75 | 37.00 | 37 | dense |
| mushroom | 8,124 | 119 | 23.00 | 23 | dense |
| retail | 88,162 | 16,470 | 10.31 | 76 | sparse, real receipts |
| T10I4D100K | 100,000 | 870 | 10.10 | 29 | sparse, synthetic |

The statistics are computed from the files. Retail has 16,470 items; the brief's table prints it as "16.47".

## Choice of copies

All four datasets come from the [FIMI repository](http://fimi.uantwerpen.be/data/), which also serves them from its [RPI mirror](https://cs.rpi.edu/~zaki/Workshops/FIMI/data/). SPMF republishes them in its [dataset catalog](https://www.philippe-fournier-viger.com/spmf/index.php?link=datasets.php), but not every copy matches FIMI:

- Chess: the SPMF copy is byte-identical to FIMI's `chess.dat`.
- Retail and T10I4D100K: FIMI uses item 0, which SPMF rejects because it requires positive item IDs. The SPMF copies add 1 to every ID, which leaves every support unchanged, so the experiments use them.
- Mushroom: SPMF's `mushrooms.txt` is a different file, with 8,416 transactions and IDs up to 128. The experiments use FIMI's `mushroom.dat`, the 8,124-transaction version that the brief and most papers report.

The brief asks for public Hugging Face or Kaggle copies, and a search on 2026-10-21 found none of these files there. A team mirror goes first in each entry's sources; the checksum rejects a mirror whose bytes differ.
