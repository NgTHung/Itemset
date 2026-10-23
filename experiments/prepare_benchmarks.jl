using ItemsetMining
include(joinpath(@__DIR__, "Experiments.jl"))
using .Experiments: load_manifest, prepare_dataset, mean_width

const USAGE = """
Usage:
  julia --project=. experiments/prepare_benchmarks.jl [DATASET ...]

Download, verify, and describe the benchmarks in data/benchmark/manifest.toml.
With no names, prepare every dataset. Verified files are reused, not downloaded again.
"""

function main(args)
    if args == ["--help"]
        println(USAGE)
        return 0
    end
    dir = joinpath(dirname(@__DIR__), "data", "benchmark")
    manifest = load_manifest(joinpath(dir, "manifest.toml"))
    names = isempty(args) ? sort!(collect(keys(manifest))) : args
    for name in names
        haskey(manifest, name) || throw(ArgumentError("unknown dataset $(repr(name)); see manifest.toml"))
    end
    println("dataset\ttransactions\titems\tmean_width\tmax_width\tsha256")
    for name in names
        entry = manifest[name]
        prepare_dataset(entry, dir)
        s = entry.stats
        println(join((name, s.transactions, s.items, round(mean_width(s); digits=4),
                      s.max_width, entry.sha256), '\t'))
    end
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
