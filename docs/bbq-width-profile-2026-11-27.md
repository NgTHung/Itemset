# Transaction width and stage profile on the grading machine, 2026-11-27

The report states every measurement on one machine, but the first width campaign (revision `8afea3d`) and the first stage profile (revision `992c3a7`) ran on Windows laptops. This record reruns both, and the layout prototype of the report's first future direction, on the grading machine. The report's warm `mine` width panel and table, the join counts, the stage-profile table, and the prototype numbers come from this run. The cold width panels come from the [command-line rerun](bbq-width-cli-2026-11-28.md).

## Run

`bbq-width-profile-20261127T044121Z` ran on BBQ: Linux, Intel Core i7-11800H fixed at 2.3 GHz with `no_turbo` 1 at start and end, Julia 1.13.2 with one thread, and SPMF 2.66 on Temurin 25.0.4.1. The code is revision `8c15198`, whose `src/` and `demo.jl` equal revision `ca60f43` of the runtime campaign. The benchmark files and the SPMF JAR are symlinks to the checkout of `bbq-all-variants-cli-5repeat-20261117T041922Z`, and the width databases regenerate from `experiments/configs/width-manifest.toml`.

The run holds the benchmark lock and refuses to start unless turbo is off and every CPU policy caps at 2,300,000 kHz. It runs the three width configurations, `runtime_curves.jl` and `join_work.jl` on the two cold ones, and `stage_profile.jl` with five repeats. All 360 width attempts are `ok` and match SPMF exactly.

The raw folder is `results/raw/bbq-width-profile-20261127T044121Z`, which Git ignores. Its archive, `results/raw/evidence/bbq-width-profile-20261127T044121Z-results.tgz` without the itemset outputs, has SHA-256 `81ec2faaf63904a58407d4e269900046899cee5c11c56d33f5d0ffb12fd45284`. The folder keeps the driver script `bbq_width_profile.sh`, its log, the prototype `layout_proto.jl`, and the prototype log.

## Results

Under matched output, the baseline's warm `mine` time grows 42-fold from width 5 to 40 (0.114 to 4.841 s) at 9.0 to 10.0 ns per merged element. The optimized variant grows 1.8-fold (10.2 to 18.3 ms). The join counts and merged elements equal the laptop campaign's, because they do not depend on the machine. SPMF Eclat's cold time grows 25-fold. Under fixed minsup 0.05, the baseline takes 1.0, 2.9, and 49.4 s at widths 20, 25, and 40.

The profile shares stay within 3 points of the laptop profile. Output takes 83% to 98% of the samples at the three dense points, and the sort alone 35% to 43%. Layout takes 98% to 99% on Accidents and Retail 0.01.

The prototype times the two layout steps three times per point:

| Point | `count_items` + `bitset_tidsets` s | Array-indexed s | Faster | Share of the pass saved |
|---|---:|---:|---:|---:|
| accidents 0.65 | 0.310 | 0.092 | 3.4 times | 35% |
| retail 0.001 | 0.056 | 0.025 | 2.2 times | 22% |
| T10I4D100K 0.00025 | 0.039 | 0.017 | 2.3 times | 3% |

## Reproduce

Copy `bbq_width_profile.sh` and a Git bundle of the revision to `incoming/NAME/` under the benchmark root on BBQ, then run `sh bbq_width_profile.sh NAME REVISION`. Without the driver, these commands run the same steps from the repository root into a new folder `OUT`:

```sh
OUT=results/raw/width-profile-rerun
for p in fixed matched; do
  julia --startup-file=no --project=. scripts/width_experiment.jl run experiments/configs/width-$p.toml --out $OUT/width-$p
  julia --startup-file=no --project=. scripts/runtime_curves.jl --out $OUT/width-$p/curves \
    --ratio baseline/optimized --ratio spmf/baseline \
    "baseline=$OUT/width-$p:baseline#cold" "optimized=$OUT/width-$p:optimized#cold" "spmf=$OUT/width-$p:spmf"
  julia --startup-file=no --project=. scripts/join_work.jl --manifest experiments/configs/width-manifest.toml \
    --out $OUT/width-$p/join-work experiments/configs/width-$p.toml
done
julia --startup-file=no --project=. scripts/width_experiment.jl run experiments/configs/width-matched-warm.toml --out $OUT/width-matched-warm
julia --startup-file=no --project=. scripts/stage_profile.jl --out $OUT/stage-profile --repeats 5 experiments/configs/stage-profile.toml
```

The prototype calls internal functions, so it stays out of the repository's experiments. Save it as `layout_proto.jl` and run `julia --startup-file=no --project=. layout_proto.jl accidents 0.65`:

```julia
using ItemsetMining, Statistics
med(f) = (f(); median([(@elapsed f()) for _ in 1:5]))

function layout_array(db, minsup)
    maxitem = maximum(maximum, filter(!isempty, db))
    counts = zeros(Int32, maxitem + 1)
    for t in db, x in t
        counts[x + 1] += 1
    end
    frequent = [x for x in 0:maxitem if counts[x + 1] >= minsup]
    sort!(frequent; by=x -> (counts[x + 1], x))
    rank = zeros(Int32, maxitem + 1)
    for (k, x) in enumerate(frequent)
        rank[x + 1] = k
    end
    sets = [zeros(UInt64, cld(length(db), 64)) for _ in frequent]
    for (tid, t) in enumerate(db)
        word, bit = divrem(tid - 1, 64)
        for x in t
            k = rank[x + 1]
            k == 0 || (sets[k][word + 1] |= UInt64(1) << bit)
        end
    end
    return sets
end

dataset, relative = ARGS[1], parse(Float64, ARGS[2])
db = read_transactions("data/benchmark/$dataset.txt")
minsup = support_threshold(relative, length(db))
items = first.(ItemsetMining.frequent_items_by_support(db, minsup))
current = med(() -> ItemsetMining.count_items(db)) + med(() -> ItemsetMining.bitset_tidsets(db, items))
array = med(() -> layout_array(db, minsup))
println(dataset, " ", relative, ": current ", round(current; digits=3), " s, array ", round(array; digits=3),
        " s, database ", round(Base.summarysize(db) / 2^20), " MiB")
```

The report's width figure takes its cold panels from the [command-line rerun](bbq-width-cli-2026-11-28.md#reproduce) and its warm panel from `width-matched-warm/summary.csv` in this run's folder.
