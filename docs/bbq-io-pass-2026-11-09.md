# BBQ input and output runtime, 2026-11-09

After the [sparse kernel](bbq-sparse-kernel-runtime-2026-11-08.md), the optimized CLI spent more time reading input and writing itemsets than mining on the dense points. On Mushroom 0.05, warm mining took 0.43 s, while ordering and printing the 3,755,511 itemsets took 1.47 s. On Accidents, reading the 34 MB file took 0.56 s. This record measures one pass over every reader and writer in the package, from `8b2fd33` to `07f708e`.

## Changes

| Commit | Change |
|---|---|
| `15672e9` | `read_transactions` parses each line into one reused vector and copies it once. |
| `9e96abd` | The itemset writer formats each number from a table of digit words with one 8-byte store. |
| `2a2e1f8` | The radix sort key packs only an itemset's own items. |
| `7fbe508` | `write_itemsets` for a map packs it and uses the packed writer's radix order. |
| `ad1fee2`, `fbb4e83` | `read_itemset_records` parses plain lines from bytes and keeps the line parser for every other line. |
| `07f708e` | `write_transactions` uses the itemset line writer. |

Every change keeps its output and errors. The readers are fuzzed against the line parsers they replace, and the writers are compared byte for byte with reference formatters.

## Method

- Host: BBQ, Linux, i7-11800H at a fixed 2.3 GHz, Julia 1.13.2, one thread, pinned to core 2 with `taskset`. `no_turbo` was 1, and the probe session was the only login.
- Warm stage times are medians of 3 or 5 runs in one process, after one warm-up run. Probes are in `~/.local/share/itemset-benchmark/probes/io/` on BBQ.
- Cold times run `demo.jl --variant optimized` as a new process, five repeats, with base and candidate interleaved. Each is the median wall time, including Julia start-up.
- These are probe runs, not a scored cohort under the [measurement protocol](../experiments/README.md). They do not compare with PrePost+ or SPMF Eclat.

## Warm stage times

| Stage | Point | Before s | After s |
|---|---|---:|---:|
| `read_transactions` | Accidents | 0.565 | 0.293 |
| `read_transactions` | Retail | 0.055 | 0.028 |
| `read_transactions` | T10I4D100K | 0.061 | 0.029 |
| Print packed itemsets | Mushroom 0.05 | 0.921 | 0.510 |
| Print packed itemsets | Chess 0.5 | 0.288 | 0.160 |
| `lexicographic_order` | Mushroom 0.05 | 0.516 | 0.443 |
| `write_itemsets` of a `SupportMap` | Mushroom 0.1 | 3.99 | 0.55 |
| `read_itemset_records` | Mushroom 0.1 output, 20 MB | 2.33 | 0.95 |
| `write_transactions` | Accidents | 1.37 | 0.10 |

`read_transactions` on Accidents allocates 151 MiB instead of 354 MiB. Writing to `devnull` and to a file differ by about 0.07 s on Mushroom 0.05, so printing is bound by formatting, not by the disk.

## Cold CLI times

| Point | Base s | Candidate s | Change |
|---|---:|---:|---:|
| Chess 0.5 | 0.949 | 0.793 | -16.4% |
| Mushroom 0.1 | 0.548 | 0.473 | -13.8% |
| Mushroom 0.05 | 2.276 | 1.786 | -21.5% |
| Retail 0.00025 | 0.609 | 0.574 | -5.8% |
| T10I4D100K 0.00025 | 1.237 | 1.197 | -3.2% |
| Accidents 0.5 | 1.181 | 0.869 | -26.4% |
| Accidents 0.3 | 1.574 | 1.284 | -18.4% |

At all seven points the candidate's output file is byte-identical to the base output, so it matches the SPMF results recorded for the base revision.

## What remains

On Mushroom 0.05 the radix sort in `lexicographic_order` takes 0.30 s of the remaining 0.44 s. A hand-written LSD radix sort was 10% faster than `sort!`, too little for the code it adds. Printing in sorted order costs 0.18 s more than printing in storage order, because the sorted order reads the packed arrays out of sequence; copying them into sorted order first costs 0.22 s, so it does not pay. `read_itemset_records` and `write_itemsets` of a map spend most of their time building `Itemset` tuples, whose length the compiler cannot know.
