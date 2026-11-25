const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "experiments", "Experiments.jl"))
using .Experiments: load_manifest, load_run_config, join_work_rows, write_join_work, parse_table_args

const DATA_DIR = joinpath(ROOT, "data", "benchmark")

const USAGE = """
Usage:
  julia --project=. scripts/join_work.jl --out DIR [--manifest PATH] CONFIG
  julia --project=. scripts/join_work.jl -h

Count the baseline Eclat's work at every dataset and minsup in CONFIG, a run
configuration such as experiments/configs/runtime.toml, and write
DIR/join-work.csv: frequent itemsets, tid-list joins, successful joins, and
merged tid-list elements per point. It reads the verified files in
data/benchmark and runs one single-threaded search per point, which takes about
as long as the baseline itself. --manifest PATH names another manifest for the
files in data/benchmark, such as experiments/configs/width-manifest.toml.
"""

function main(args; data_dir::AbstractString=DATA_DIR)
    if args == ["-h"] || args == ["--help"]
        println(USAGE)
        return 0
    end
    args = parse_table_args(args, USAGE, data_dir)
    isfile(args.config) || throw(ArgumentError("CONFIG $(args.config) does not exist"))
    isfile(args.manifest) || throw(ArgumentError("manifest $(args.manifest) does not exist"))
    rows = join_work_rows(load_run_config(args.config), load_manifest(args.manifest), data_dir)
    mkpath(args.out)
    write_join_work(joinpath(args.out, "join-work.csv"), rows)
    for r in rows
        println(r.dataset, " ", r.minsup_relative, ": ", r.itemsets, " itemsets, ", r.joins, " joins (",
                r.successful_joins, " successful), ", r.merged_elements, " merged elements")
    end
    println("wrote ", joinpath(args.out, "join-work.csv"))
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
