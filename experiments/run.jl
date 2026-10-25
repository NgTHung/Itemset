using ItemsetMining
using Dates: Dates
using TOML: TOML
include(joinpath(@__DIR__, "Experiments.jl"))
using .Experiments: load_manifest, parse_run_config, run_experiment

const USAGE = """
Usage:
  julia --project=. experiments/run.jl CONFIG [--out DIR] [--project PATH] [--java PATH]

Run the experiment in CONFIG and write runs.csv with its raw evidence to DIR,
by default results/raw/<name>-<UTC time>. --project measures the ItemsetMining
of another checkout; --java selects the Java used for SPMF. Both override CONFIG
and are recorded in DIR/config.toml.
"""

function main(args)
    if isempty(args) || args == ["--help"]
        println(USAGE)
        return 0
    end
    table = TOML.parsefile(first(args))
    out = nothing
    options = args[2:end]
    iseven(length(options)) || throw(ArgumentError("every option needs a value\n$USAGE"))
    for i in 1:2:length(options)
        key, value = options[i], options[i+1]
        if key == "--out"
            out = value
        elseif key in ("--project", "--java")
            table[key[3:end]] = value
        else
            throw(ArgumentError("unknown option $key\n$USAGE"))
        end
    end
    config = parse_run_config(table)
    root = dirname(@__DIR__)
    stamp = Dates.format(Dates.now(Dates.UTC), "yyyymmddTHHMMSSZ")
    out = something(out, joinpath(root, "results", "raw", "$(config.name)-$stamp"))
    isdir(out) && !isempty(readdir(out)) && throw(ArgumentError("output folder $out is not empty"))
    manifest = load_manifest(joinpath(root, "data", "benchmark", "manifest.toml"))
    rows = run_experiment(config, manifest; data_dir=joinpath(root, "data", "benchmark"), out_dir=out)
    println("wrote $(length(rows)) rows to $(joinpath(out, "runs.csv"))")
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
