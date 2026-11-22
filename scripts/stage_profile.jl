const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "experiments", "Experiments.jl"))
using .Experiments: load_manifest, load_run_config, stage_profile_rows, write_stage_profile

const DATA_DIR = joinpath(ROOT, "data", "benchmark")

const USAGE = """
Usage:
  julia --project=. scripts/stage_profile.jl --out DIR [--repeats N] [--manifest PATH] CONFIG
  julia --project=. scripts/stage_profile.jl -h

Time the read, mine, and write stages of the optimized CLI path at every dataset and minsup
in CONFIG, such as experiments/configs/stage-profile.toml, and write DIR/stage-profile.csv. It
also samples the same passes with the profiler and records the share of each part of the
search, the root layout, and the output. The medians cover N warm passes (default 5), and the
variants and repeats of CONFIG do not apply. It reads the verified files in data/benchmark and
runs on one thread, so run it on a quiet machine. --manifest PATH names another manifest for the
files in data/benchmark, such as experiments/configs/width-manifest.toml.
"""

function main(args; data_dir::AbstractString=DATA_DIR)
    if args == ["-h"] || args == ["--help"]
        println(USAGE)
        return 0
    end
    out = nothing
    config = nothing
    repeats = 5
    manifest_path = joinpath(DATA_DIR, "manifest.toml")
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("--out", "--repeats", "--manifest")
            i < length(args) || throw(ArgumentError("$arg needs a value\n$USAGE"))
            if arg == "--out"
                out = args[i + 1]
            elseif arg == "--manifest"
                manifest_path = args[i + 1]
            else
                repeats = tryparse(Int, args[i + 1])
                (repeats !== nothing && repeats >= 1) ||
                    throw(ArgumentError("--repeats needs an integer of at least 1, got $(repr(args[i + 1]))"))
            end
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
    rows = stage_profile_rows(load_run_config(config), manifest, data_dir; repeats)
    mkpath(out)
    write_stage_profile(joinpath(out, "stage-profile.csv"), rows)
    for r in rows
        total = r.read_seconds + r.mine_seconds + r.write_seconds
        println(r.dataset, " ", r.minsup_relative, ": ", r.itemsets, " itemsets, read ", round(r.read_seconds; digits=3),
                " s, mine ", round(r.mine_seconds; digits=3), " s, write ", round(r.write_seconds; digits=3),
                " s (total ", round(total; digits=3), " s)")
    end
    println("wrote ", joinpath(out, "stage-profile.csv"))
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
