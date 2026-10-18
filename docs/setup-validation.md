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

Additional checks: notebook JSON parsed and all three Python code cells compiled
with local Python 3.14; no saved outputs. Mining CLI was invoked and returned the
expected exit 1 for the unimplemented baseline without creating its output file.
Missing-file input inspection also returned exit 1.

These results cover the local foundation only. Eclat implementation, five-database
miner correctness/SPMF comparisons, benchmark evidence, applications, a live clean
Colab run, hosted public links, and final report PDF are outstanding. The notebook
Linux installer was prepared with the official release-feed SHA-256 but was not
executed in Colab here. The IEEE LaTeX skeleton has not been compiled. GitHub CI
configuration is prepared but cannot run until the repository is published.
