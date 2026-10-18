# Local setup validation — 2026-10-18

Environment: Windows x86_64; Julia 1.13.2 at
`C:\Users\BBQ\AppData\Local\Programs\Julia-1.13.2\bin\julia.exe`.
Invocations below used that full path, `--startup-file=no`, and repository root.

Executed successfully:

```text
julia --project=. -e 'using Pkg; Pkg.instantiate()'
  ItemsetMining precompiled; Manifest.toml generated.

julia --project=. scripts/check_setup.jl
Setup OK | Julia 1.13.2 | seed=20261018 | toy transactions=4
Eclat implementation and SPMF validation are pending (DAT-8 / DAT-9 / DAT-13).

julia --project=. test/runtests.jl
Test Summary: | Pass  Total  Time
Itemset setup |   71     71  3.9s

julia --project=. -e 'using Pkg; Pkg.test()'
Test Summary: | Pass  Total  Time
Itemset setup |   71     71  3.3s
Testing ItemsetMining tests passed

julia --project=. demo.jl --check-input data/toy/baskets.txt
transactions=4 items=3
```

Initial checks: the original Python-wrapper notebook compiled; it has since been
replaced by the native Julia notebook verified below. Mining CLI returned the
expected exit 1 for the unimplemented baseline without creating its output file.
Missing-file input inspection also returned exit 1.

These results cover the local foundation only. Eclat implementation, five-database
miner correctness/SPMF comparisons, benchmark evidence, applications, a live clean
Colab run, hosted public links, and final report PDF are outstanding.
The IEEE LaTeX skeleton has not been compiled. GitHub CI
configuration is prepared but cannot run until the repository is published.

## Native Julia notebook update — 2026-10-18

Per user correction, `demo.ipynb` now targets Colab's native `julia` kernel. All four
code cells were extracted in order and executed directly in Julia 1.13.2 locally.
Repository activation, environment instantiation, setup check, all 71 tests, and
the direct transaction/support example succeeded. Notebook metadata is Julia and
execution counts/outputs are cleared for delivery.

The local default remains Julia 1.13.2. Package compatibility and the setup guard
now allow Julia 1.12+ within 1.x; CI is configured for 1.12.6 and 1.13.2. This avoids
rejecting Colab's documented 2026.07 native runtime (Julia 1.12.6). The notebook
prints its actual Julia version, thread count, project, and seed for run provenance.
No runtime downloader or Python wrapper is needed. Live hosted Colab execution and
CI on the additional Julia version have not been verified in this local run.
