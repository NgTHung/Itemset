# Common measurement protocol — DAT-12 draft, Thien

Use the same pilot-approved 5–7 decreasing relative minsup points for each of Chess,
Mushroom, Retail, and T10I4D100K. Compute file statistics instead of copying counts
from the assignment (some catalog values may be typos). Freeze input SHA-256,
SPMF JAR SHA/version/Java, Git revision, Julia/OS/CPU/threads, seed, and parameters.

`result-fields.txt` is the proposed CSV header, not fabricated results. Record one
row per attempt, retain timeout/error status, preserve stdout/stderr and commands.
Choose and record repeat count/timeouts after pilots. Do not compare Julia JIT-free
mining time against Java startup-inclusive process time: record timing boundaries,
warmup policy, materialization/serialization, and I/O inclusion for each series.
Report repeat variation. Separate end-to-end timing from any mining-only series.

Peak memory means OS-measured process peak RSS in bytes, not Julia allocations;
record platform/tool and baseline/optimized variants at the same medium minsup.
Perform exact itemset/support comparisons, not count-only checks. Reference fixtures
and runs are Phat's independent responsibility; no source copying is required.

Scalability uses seeded nested subsets at 10/25/50/75/100%, fixed relative minsup,
and actual transaction counts. Width experiments hold N, universe, and sampling
model fixed. Reuse raw timing counts for output-size plots instead of rerunning.
Owners execute/interpret their charts: Hung scalability/counts; Thien time/width;
Phat correctness/memory. Store raw runs in `results/raw/` and figures in
`results/figures/`; curate small final evidence into the report with provenance.
