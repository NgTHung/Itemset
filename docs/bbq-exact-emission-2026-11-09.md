# BBQ exact-size emission, 2026-11-09

After the [input and output pass](bbq-io-pass-2026-11-09.md), warm mining on Mushroom 0.05 allocated 1,068 MiB to build a 306 MiB packed result, because the result grew one itemset at a time and was copied on every doubling. Presizing the result to its final length in a throwaway probe cut warm mining from 0.6 s to 0.3 s on the Windows laptop. This record measures the change that makes the size known in advance: the search records nodes, and `expand_nodes` allocates the result once (`62c90ae`, base `026c479`).

## Method

- Host: BBQ, Linux, i7-11800H at a fixed 2.3 GHz, Julia 1.13.2, one thread, pinned to core 2 with `taskset`. `no_turbo` was 1, and the probe session was the only login.
- Warm times call `mine_optimized` on a canonical database, as medians of 5 runs in one process after one warm-up run.
- Cold times run `demo.jl --variant optimized` as a new process, five repeats, with base and candidate interleaved. Each is the median wall time, including Julia start-up.
- First-run mining time, its GC time, and `Sys.maxrss()` come from a fresh process that reads, mines, and writes to `devnull`, three repeats per tree.
- Probes are in `~/.local/share/itemset-benchmark/probes/emission/` on BBQ. These are probe runs, not a scored cohort under the [measurement protocol](../experiments/README.md).

## Correctness

At all seven points the candidate's packed arrays have the same hash as the base's, so it emits the same itemsets in the same storage order. Its CLI output files are byte-identical to the base output, so they match the SPMF results recorded for the base revision.

## Warm mining

| Point | Itemsets | Base s | Candidate s | Base MiB | Candidate MiB |
|---|---:|---:|---:|---:|---:|
| Chess 0.5 | 1,272,932 | 0.169 | 0.145 | 326.2 | 252.9 |
| Mushroom 0.1 | 574,431 | 0.056 | 0.030 | 176.8 | 47.4 |
| Mushroom 0.05 | 3,755,511 | 0.403 | 0.169 | 1,067.6 | 318.4 |
| Retail 0.00025 | 47,448 | 0.219 | 0.216 | 141.9 | 144.4 |
| T10I4D100K 0.00025 | 96,959 | 0.861 | 0.866 | 38.9 | 40.4 |
| Accidents 0.5 | 8,057 | 0.311 | 0.311 | 4.9 | 5.5 |
| Accidents 0.3 | 149,545 | 0.643 | 0.638 | 52.7 | 65.6 |

The gain follows the number of itemsets per node. Mushroom has many perfect extensions, so its node records are small next to the result. On Accidents most nodes stand for one itemset, so the node records about double the bytes the search writes.

## Cold CLI

| Point | Base s | Candidate s | Change |
|---|---:|---:|---:|
| Chess 0.5 | 0.793 | 0.773 | -2.5% |
| Mushroom 0.1 | 0.473 | 0.425 | -10.1% |
| Mushroom 0.05 | 1.792 | 1.501 | -16.2% |
| Retail 0.00025 | 0.578 | 0.577 | -0.1% |
| T10I4D100K 0.00025 | 1.195 | 1.205 | +0.8% |
| Accidents 0.5 | 0.869 | 0.865 | -0.4% |
| Accidents 0.3 | 1.290 | 1.324 | +2.6% |

All five Accidents 0.3 candidate runs were slower than all five base runs, so the 0.03 s loss is real. The fresh-process runs below place it in first-run mining, where GC time rose from 0.045 s to 0.058 to 0.065 s. The extra node records trigger collections while the 151 MiB database is live.

## First run and peak memory

| Point | Base mine s | Candidate mine s | Base GC s | Candidate GC s | Base peak RSS MiB | Candidate peak RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| Mushroom 0.05 | 0.475 | 0.194 | 0.054 | 0.016 | 929.5 | 704.6 |
| Chess 0.5 | 0.219 | 0.194 | 0.031 | 0.030 | 420.2 | 464.7 |
| Accidents 0.3 | 0.701 | 0.730 | 0.045 | 0.064 | 418.9 | 412.9 |

Values are medians of three. Peak RSS on Chess 0.5 rises 10.6%, because its nodes hold about a third as many records as its itemsets, and the node records stay live while `expand_nodes` fills the result. That is inside the plan's 20% memory allowance. Mushroom 0.05 drops 24%.
