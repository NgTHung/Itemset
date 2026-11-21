const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "experiments", "Experiments.jl"))
using .Experiments: load_manifest, load_run_config, join_work_rows, write_join_work

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
    out = nothing
    config = nothing
    manifest_path = joinpath(DATA_DIR, "manifest.toml")
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--out" || arg == "--manifest"
            i < length(args) || throw(ArgumentError("$arg needs a value\n$USAGE"))
            arg == "--out" ? (out = args[i + 1]) : (manifest_path = args[i + 1])
            i += 2
        elseif startswith(arg, '-')
            throw(ArgumentError("unknown option $arg\n$USAGE"))
        else
            config === nothing || throw(ArgumentError("give one CONFIG, got $(repr(config)) and $(repr(arg))\n$USAGE"))
            config = arg
            i += 1
        end
    end
    (out === nothing || config === nothing) && throw(ArgumentError("--out and CONFIG are required\n$USAGE"))
    isfile(config) || throw(ArgumentError("CONFIG $config does not exist"))
    isfile(manifest_path) || throw(ArgumentError("manifest $manifest_path does not exist"))
    manifest = load_manifest(manifest_path)
    rows = join_work_rows(load_run_config(config), manifest, data_dir)
    mkpath(out)
    write_join_work(joinpath(out, "join-work.csv"), rows)
    for r in rows
        println(r.dataset, " ", r.minsup_relative, ": ", r.itemsets, " itemsets, ", r.joins, " joins (",
                r.successful_joins, " successful), ", r.merged_elements, " merged elements")
    end
    println("wrote ", joinpath(out, "join-work.csv"))
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
