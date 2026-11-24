const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "experiments", "Experiments.jl"))
using .Experiments: load_manifest, load_run_config, stage_profile_rows, write_stage_profile, parse_table_args

const DATA_DIR = joinpath(ROOT, "data", "benchmark")

const USAGE = """
Usage:
  julia --project=. scripts/stage_profile.jl --out DIR [--repeats N] [--manifest PATH] CONFIG
  julia --project=. scripts/stage_profile.jl -h

Time the read, mine, and write stages of the optimized CLI path at every dataset and minsup
in CONFIG, such as experiments/configs/stage-profile.toml, and write DIR/stage-profile.csv. It
also samples the same passes with the profiler and records the share of each part of the
search, the root layout, and the output. The medians cover N warm passes, where N is --repeats or
else the repeats of CONFIG, and the variants of CONFIG do not apply. It reads the verified files in data/benchmark and
runs on one thread, so run it on a quiet machine. --manifest PATH names another manifest for the
files in data/benchmark, such as experiments/configs/width-manifest.toml.
"""

function main(args; data_dir::AbstractString=DATA_DIR)
    if args == ["-h"] || args == ["--help"]
        println(USAGE)
        return 0
    end
    args = parse_table_args(args, USAGE, data_dir; repeats=true)
    isfile(args.config) || throw(ArgumentError("CONFIG $(args.config) does not exist"))
    isfile(args.manifest) || throw(ArgumentError("manifest $(args.manifest) does not exist"))
    rows = stage_profile_rows(load_run_config(args.config), load_manifest(args.manifest), data_dir;
                              repeats=args.repeats)
    mkpath(args.out)
    write_stage_profile(joinpath(args.out, "stage-profile.csv"), rows)
    for r in rows
        total = r.read_seconds + r.mine_seconds + r.write_seconds
        println(r.dataset, " ", r.minsup_relative, ": ", r.itemsets, " itemsets, read ", round(r.read_seconds; digits=3),
                " s, mine ", round(r.mine_seconds; digits=3), " s, write ", round(r.write_seconds; digits=3),
                " s (total ", round(total; digits=3), " s)")
    end
    println("wrote ", joinpath(args.out, "stage-profile.csv"))
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    code = try
        main(ARGS)
    catch exception
        println(stderr, "ERROR: ", sprint(showerror, exception))
        1
    end
    exit(code)
end
