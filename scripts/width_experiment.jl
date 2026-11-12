using ItemsetMining
using Dates: Dates
using TOML: TOML
const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "experiments", "Experiments.jl"))
using .Experiments: WidthSettings, load_manifest, freeze_width_manifest, ensure_width_databases, width_database,
                    pilot_rows, write_pilot, parse_run_config, run_experiment, PILOT_FIELDS

const MANIFEST_PATH = joinpath(ROOT, "experiments", "configs", "width-manifest.toml")
const DATA_DIR = joinpath(ROOT, "data", "benchmark")

const USAGE = """
Usage:
  julia --project=. scripts/width_experiment.jl freeze
  julia --project=. scripts/width_experiment.jl pilot [--fixed-count N] [--target N] [--out DIR]
  julia --project=. scripts/width_experiment.jl run CONFIG [--out DIR] [--java PATH]
  julia --project=. scripts/width_experiment.jl -h

The width experiment times Eclat on synthetic databases of 10,000 transactions over
100 items whose transactions all have one width, 5 to 40 in steps of 5. Each
transaction is a uniformly random subset of that many items, from a seeded
integer generator, so every file is byte-identical on every machine.

freeze   generates the databases into data/benchmark and writes
         experiments/configs/width-manifest.toml with their SHA-256. It refuses to
         replace an existing manifest, because a changed manifest would hide a
         changed generator. Commit the manifest.
pilot    restores the databases from the manifest and prints, per width, the
         density, the item supports, the output at --fixed-count (default 500), and the
         support count that gives about --target itemsets (default 5000). With --out
         it writes DIR/pilot.csv. Use it to choose the thresholds in the configs.
run      restores the databases, then runs CONFIG through the common harness like
         experiments/run.jl, with the width datasets width-w05 to width-w40.
"""

function parse_options(args, names)
    options = Dict{String,String}()
    positional = String[]
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in names
            i < length(args) || throw(ArgumentError("$arg needs a value\n$USAGE"))
            options[arg] = args[i + 1]
            i += 2
        elseif startswith(arg, '-')
            throw(ArgumentError("unknown option $arg\n$USAGE"))
        else
            push!(positional, arg)
            i += 1
        end
    end
    return options, positional
end

function load_frozen(manifest_path)
    isfile(manifest_path) ||
        throw(ArgumentError("$manifest_path does not exist; run `scripts/width_experiment.jl freeze` first"))
    return load_manifest(manifest_path)
end

function main(args; settings::WidthSettings=WidthSettings(), manifest_path::AbstractString=MANIFEST_PATH,
              data_dir::AbstractString=DATA_DIR)
    if args == ["-h"] || args == ["--help"]
        println(USAGE)
        return 0
    end
    isempty(args) && throw(ArgumentError("give a command\n$USAGE"))
    command, rest = first(args), args[2:end]
    if command == "freeze"
        isempty(rest) || throw(ArgumentError("freeze takes no arguments\n$USAGE"))
        isfile(manifest_path) && throw(ArgumentError(
            "$manifest_path already exists; delete it first only if the generator or settings should change"))
        freeze_width_manifest(manifest_path, settings, data_dir)
        println("wrote ", manifest_path, " and ", length(settings.widths), " databases in ", data_dir)
    elseif command == "pilot"
        options, positional = parse_options(rest, ("--fixed-count", "--target", "--out"))
        isempty(positional) || throw(ArgumentError("pilot takes no positional arguments\n$USAGE"))
        fixed = parse(Int, get(options, "--fixed-count", "500"))
        target = parse(Int, get(options, "--target", "5000"))
        manifest = load_frozen(manifest_path)
        ensure_width_databases(data_dir, manifest, settings)
        databases = Dict(w => read_transactions(joinpath(data_dir, manifest[Experiments.width_name(w)].file))
                         for w in settings.widths)
        rows = pilot_rows(settings, databases; fixed_count=fixed, target)
        println(join(PILOT_FIELDS, '\t'))
        foreach(r -> println(join((getfield(r, Symbol(f)) for f in PILOT_FIELDS), '\t')), rows)
        if haskey(options, "--out")
            mkpath(options["--out"])
            write_pilot(joinpath(options["--out"], "pilot.csv"), rows)
            println("wrote ", joinpath(options["--out"], "pilot.csv"))
        end
    elseif command == "run"
        options, positional = parse_options(rest, ("--out", "--java"))
        length(positional) == 1 || throw(ArgumentError("run takes one CONFIG, got $(length(positional))\n$USAGE"))
        config_path = only(positional)
        isfile(config_path) || throw(ArgumentError("CONFIG $config_path does not exist"))
        table = TOML.parsefile(config_path)
        haskey(options, "--java") && (table["java"] = options["--java"])
        config = parse_run_config(table)
        manifest = load_frozen(manifest_path)
        stamp = Dates.format(Dates.now(Dates.UTC), "yyyymmddTHHMMSSZ")
        out = get(options, "--out", joinpath(ROOT, "results", "raw", "$(config.name)-$stamp"))
        isdir(out) && !isempty(readdir(out)) && throw(ArgumentError("output folder $out is not empty"))
        ensure_width_databases(data_dir, manifest, settings)
        rows = run_experiment(config, manifest; data_dir, out_dir=out)
        println("wrote $(length(rows)) rows to $(joinpath(out, "runs.csv"))")
    else
        throw(ArgumentError("unknown command $(repr(command))\n$USAGE"))
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
