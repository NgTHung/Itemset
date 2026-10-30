# Measured child for one mining attempt. It loads the ItemsetMining of the
# active project, so a harness can time any checked-out revision.
using ItemsetMining
using TOML: TOML

const USAGE = """
Usage:
  julia --project=CODE experiments/eclat_worker.jl --variant baseline|optimized
        --minsup FRACTION --output PATH --report PATH --mode cold|warm INPUT

Cold mode has no warmup. Warm mode compiles on toy data and runs INPUT once
before measuring reading, mining, and writing. Warmup output goes to devnull.
"""

"""
Compile every timed call on a tiny database first, so the timed calls exclude
JIT compilation. The process wall time measured by the harness still includes it.
"""
function warm_up(variant::Symbol)
    path, io = mktemp()
    try
        println(io, "1 2\n1 2\n2 3")
        close(io)
        transactions = read_transactions(path)
        write_itemsets(devnull, mine(transactions; minsup=0.5, variant))
    finally
        rm(path; force=true)
    end
    return nothing
end

function measured_phases(input, output, minsup, variant)
    read_result = @timed read_transactions(input)
    transactions = read_result.value
    mined = @timed mine(transactions; minsup, variant)
    patterns = mined.value
    written = @timed write_itemsets(output, patterns)
    report = Dict{String,Any}("transactions" => length(transactions),
        "minsup_count" => support_threshold(minsup, length(transactions)),
        "output_count" => length(patterns))
    for (scope, result) in (("read", read_result), ("mine", mined), ("write", written))
        report[scope * "_seconds"] = result.time
        report[scope * "_gc_seconds"] = result.gctime
        report[scope * "_allocated_bytes"] = result.bytes
    end
    return report
end

function main(args)
    length(args) == 11 || throw(ArgumentError("expected five options and an input\n$USAGE"))
    values = Dict(args[i] => args[i+1] for i in 1:2:10)
    keys(values) == Set(["--variant", "--minsup", "--output", "--report", "--mode"]) ||
        throw(ArgumentError("unexpected options $(collect(keys(values)))\n$USAGE"))
    input = args[11]
    variant = Symbol(values["--variant"])
    minsup = parse(Float64, values["--minsup"])

    mode = values["--mode"]
    mode in ("cold", "warm") || throw(ArgumentError("invalid mode $mode"))
    if mode == "warm"
        warm_up(variant)
        measured_phases(input, devnull, minsup, variant)
        GC.gc()
    end
    report = measured_phases(input, values["--output"], minsup, variant)
    merge!(report, Dict{String,Any}(
        "mode" => mode,
        "julia_version" => string(VERSION),
        "threads" => Threads.nthreads(),
    ))
    open(io -> TOML.print(io, report), values["--report"], "w")
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
