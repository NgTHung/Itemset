using ItemsetMining
include(joinpath(@__DIR__, "Experiments.jl"))
using .Experiments: load_manifest, prepare_dataset, prepare_subsets, write_subset_manifest, mean_width

const USAGE = """
Usage:
  julia --project=. experiments/prepare_subsets.jl DATASET... [--fractions F,F,...] [--seed S]

Write seeded nested subsets of each benchmark into data/benchmark/ for the
scalability runs, by default 10, 25, 50, 75, and 100 percent with DEFAULT_SEED.
data/benchmark/subsets.toml records their SHA-256 and statistics. A subset already
recorded there must come out byte-identical, so a rerun proves the inputs match.
"""

function main(args)
    if isempty(args) || args == ["--help"]
        println(USAGE)
        return 0
    end
    fractions, seed, names = [0.1, 0.25, 0.5, 0.75, 1.0], DEFAULT_SEED, String[]
    i = 1
    while i <= length(args)
        if args[i] in ("--fractions", "--seed")
            i < length(args) || throw(ArgumentError("$(args[i]) needs a value\n$USAGE"))
            if args[i] == "--fractions"
                fractions = parse.(Float64, split(args[i+1], ','))
            else
                seed = parse(Int, args[i+1])
            end
            i += 2
        else
            push!(names, args[i])
            i += 1
        end
    end
    dir = joinpath(dirname(@__DIR__), "data", "benchmark")
    manifest = load_manifest(joinpath(dir, "manifest.toml"))
    subsets_path = joinpath(dir, "subsets.toml")
    recorded = isfile(subsets_path) ? load_manifest(subsets_path) : Dict{String,Experiments.DatasetEntry}()
    for name in names
        haskey(manifest, name) || throw(ArgumentError("unknown dataset $(repr(name)); see manifest.toml"))
    end
    println("subset\ttransactions\titems\tmean_width\tsha256")
    for name in names
        entries = prepare_subsets(manifest[name], prepare_dataset(manifest[name], dir), dir, fractions;
                                  seed, recorded)
        for entry in entries
            recorded[entry.name] = entry
            s = entry.stats
            println(join((entry.name, s.transactions, s.items, round(mean_width(s); digits=4), entry.sha256), '\t'))
        end
    end
    write_subset_manifest(subsets_path, sort!(collect(values(recorded)); by=e -> e.name))
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
