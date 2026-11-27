# Transaction width and stage profile on the grading machine, 2026-11-27

The report states every measurement on one machine, but the [width record](width-runtime-2026-11-11.md) and the [stage profile](future-optimizations-2026-11-22.md) ran on Windows laptops. This record reruns both, and the layout prototype of Proposal 1, on the grading machine. The report's width table and figure, the profile table, and the prototype numbers come from this run.

## Run

`bbq-width-profile-20261127T044121Z` ran on BBQ: Linux, Intel Core i7-11800H fixed at 2.3 GHz with `no_turbo` 1 at start and end, Julia 1.13.2 with one thread, and SPMF 2.66 on Temurin 25.0.4.1. The code is revision `8c15198`, whose `src/` and `demo.jl` equal revision `ca60f43` of the runtime campaign. The benchmark files and the SPMF JAR are symlinks to the checkout of `bbq-all-variants-cli-5repeat-20261117T041922Z`, and the width databases regenerate from `experiments/configs/width-manifest.toml`.

The run holds the benchmark lock and refuses to start unless turbo is off and every CPU policy caps at 2,300,000 kHz. It runs the three width configurations, `runtime_curves.jl` and `join_work.jl` on the two cold ones, and `stage_profile.jl` with five repeats, with the commands of the two earlier records. All 360 width attempts are `ok` and match SPMF exactly.

The raw folder is `results/raw/bbq-width-profile-20261127T044121Z`, which Git ignores. Its archive, `results/raw/evidence/bbq-width-profile-20261127T044121Z-results.tgz` without the itemset outputs, has SHA-256 `81ec2faaf63904a58407d4e269900046899cee5c11c56d33f5d0ffb12fd45284`. The folder keeps the driver script `bbq_width_profile.sh`, its log, the prototype `layout_proto.jl` from the earlier record, and the prototype log.

## Results

Under matched output, the baseline's warm `mine` time grows 42-fold from width 5 to 40 (0.114 to 4.841 s) at 9.0 to 10.0 ns per merged element. The optimized variant grows 1.8-fold (10.2 to 18.3 ms). The join counts and merged elements equal the earlier record, because they do not depend on the machine. SPMF Eclat's cold time grows 25-fold. Under fixed minsup 0.05, the baseline takes 1.0, 2.9, and 49.4 s at widths 20, 25, and 40.

The profile shares stay within 3 points of the earlier ones. Output takes 83% to 98% of the samples at the three dense points, and the sort alone 35% to 43%. Layout takes 98% to 99% on Accidents and Retail 0.01.

The prototype times the two layout steps three times per point:

| Point | `count_items` + `bitset_tidsets` s | Array-indexed s | Faster | Share of the pass saved |
|---|---:|---:|---:|---:|
| accidents 0.65 | 0.310 | 0.092 | 3.4 times | 35% |
| retail 0.001 | 0.056 | 0.025 | 2.2 times | 22% |
| T10I4D100K 0.00025 | 0.039 | 0.017 | 2.3 times | 3% |

## Reproduce

Copy `bbq_width_profile.sh` and a Git bundle of the revision to `incoming/NAME/` under the benchmark root on BBQ, then run `sh bbq_width_profile.sh NAME REVISION`. The width figure comes from:

```sh
R=results/raw/bbq-width-profile-20261127T044121Z
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_width_curves.py \
  $R/width-fixed/curves/curves.csv $R/width-matched/curves/curves.csv \
  --warm-summary $R/width-matched-warm/summary.csv --out $R/width-figure
```
