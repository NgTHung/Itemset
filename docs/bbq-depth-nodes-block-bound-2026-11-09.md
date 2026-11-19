# BBQ depth-ordered nodes and block-count bound, 2026-11-09

The [exact-size emission](bbq-exact-emission-2026-11-09.md) left three costs. Its node records copied each node's whole core, which slowed Accidents 0.3 by 2.6% through extra GC and raised Chess 0.5 peak RSS by 10.6%. Printing in sorted order cost about 0.2 s more than printing in storage order on Mushroom 0.05. On T10I4D100K 0.00025, 98.7% of 2,076,972 tid-list joins failed after merging up to 126 tids. This record measures one change for each cost, cumulatively over four revisions.

| Tree | Revision | Change |
|---|---|---|
| io | `026c479` | [Input and output pass](bbq-io-pass-2026-11-09.md), the control |
| exact | `a80f6e5` | Result sized once from search nodes |
| depth | `6befa68` | Node records hold depth, added item, added perfect extensions, and support; child class vectors are pooled |
| bound | `f20d6d0` | Block-count bound before tid-list joins, 256 blocks ([design](eclat-optimized.md#block-count-bound)) |

## Method

- Host: BBQ, Linux, i7-11800H at a fixed 2.3 GHz, Julia 1.13.2, one thread, pinned to core 2 with `taskset`. `no_turbo` was 1, and the probe session was the only login.
- Warm times call `mine_optimized` on a canonical database, as medians of 5 runs in one process after one warm-up run.
- Cold times run `demo.jl --variant optimized` as a new process, five repeats, with the four trees interleaved. Each is the median wall time, including Julia start-up.
- First-run mining time, its GC time, and `Sys.maxrss()` come from a fresh process that reads, mines, and writes to `devnull`, as medians of three.
- Probes are in `~/.local/share/itemset-benchmark/probes/emission/` on BBQ. These are probe runs, not a scored cohort under the [measurement protocol](../experiments/README.md).

## Correctness

At all seven points the four trees produce packed arrays with the same hash, so they emit the same itemsets in the same storage order. All 28 CLI output files are byte-identical to the io tree's, so they match the SPMF results recorded for that revision.

## Warm mining

| Point | io s | exact s | depth s | bound s | io MiB | exact MiB | depth MiB | bound MiB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Chess 0.5 | 0.171 | 0.147 | 0.134 | 0.131 | 326.2 | 252.9 | 138.2 | 138.2 |
| Mushroom 0.1 | 0.055 | 0.030 | 0.031 | 0.029 | 176.8 | 47.4 | 45.0 | 45.0 |
| Mushroom 0.05 | 0.402 | 0.175 | 0.171 | 0.166 | 1,067.6 | 318.4 | 310.5 | 310.5 |
| Retail 0.00025 | 0.219 | 0.217 | 0.219 | 0.215 | 141.9 | 144.4 | 138.2 | 138.3 |
| T10I4D100K 0.00025 | 0.860 | 0.861 | 0.855 | 0.669 | 38.9 | 40.4 | 27.1 | 27.9 |
| Accidents 0.5 | 0.306 | 0.312 | 0.311 | 0.311 | 4.9 | 5.5 | 4.1 | 4.1 |
| Accidents 0.3 | 0.634 | 0.639 | 0.638 | 0.633 | 52.7 | 65.6 | 26.6 | 26.6 |

The MiB columns are bytes allocated per run. Depth-ordered records cut Accidents 0.3 allocation from 65.6 to 26.6 MiB and Chess 0.5 from 252.9 to 138.2 MiB, because a record no longer grows with its core. The bound cuts T10I4D100K 0.00025 by 21.8% against the depth tree.

## Cold CLI

| Point | io s | exact s | depth s | bound s | bound against io |
|---|---:|---:|---:|---:|---:|
| Chess 0.5 | 0.793 | 0.766 | 0.748 | 0.738 | -7.0% |
| Mushroom 0.1 | 0.478 | 0.432 | 0.433 | 0.429 | -10.2% |
| Mushroom 0.05 | 1.782 | 1.504 | 1.498 | 1.501 | -15.8% |
| Retail 0.00025 | 0.574 | 0.577 | 0.577 | 0.578 | +0.7% |
| T10I4D100K 0.00025 | 1.196 | 1.201 | 1.178 | 0.982 | -17.9% |
| Accidents 0.5 | 0.858 | 0.868 | 0.873 | 0.864 | +0.7% |
| Accidents 0.3 | 1.285 | 1.312 | 1.287 | 1.277 | -0.7% |

The depth tree removes the Accidents 0.3 loss of the exact tree. The bound saves 0.196 s on T10I4D100K 0.00025. Its 2% warm gain on Retail 0.00025 does not show in the cold time.

## First run and peak memory

| Point | io mine s | exact mine s | depth mine s | bound mine s | io GC s | depth GC s | io RSS MiB | exact RSS MiB | depth RSS MiB | bound RSS MiB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Chess 0.5 | 0.216 | 0.193 | 0.159 | 0.155 | 0.030 | 0.012 | 423.0 | 464.4 | 389.2 | 391.6 |
| Mushroom 0.05 | 0.473 | 0.196 | 0.197 | 0.190 | 0.054 | 0.016 | 928.8 | 706.4 | 704.9 | 704.9 |
| Accidents 0.3 | 0.694 | 0.729 | 0.700 | 0.696 | 0.046 | 0.045 | 419.2 | 414.6 | 413.4 | 413.5 |
| T10I4D100K 0.00025 | 0.919 | | 0.896 | 0.706 | 0.035 | 0.018 | 294.6 | | 294.8 | 296.1 |
| Retail 0.00025 | 0.304 | | 0.306 | 0.305 | 0.045 | 0.047 | 410.9 | | 407.7 | 406.3 |

The exact tree was not rerun on the sparse points. Against the io tree, peak RSS falls 7.4% on Chess 0.5 and 24.1% on Mushroom 0.05, and the bound's counts add 1.3 MiB on T10I4D100K 0.00025.

## Printing from sort keys

The third candidate printed each itemset that fits in its radix sort key straight from the sorted key, so the printer would read the packed items in storage order. On Mushroom 0.05, 99.99% of itemsets fit, at 15 items of 7 bits per key. A probe on the exact tree printed Mushroom 0.05 to `devnull` in 0.483 s from keys against 0.458 s through the packed arrays, and Chess 0.5 in 0.149 s against 0.139 s, as medians of three. Decoding 128-bit keys costs more than the item reads it saves, and offsets and supports are still read in sorted order. The change was not built.
