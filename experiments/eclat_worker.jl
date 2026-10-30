# Measured child for one mining attempt. It loads the ItemsetMining of the
# active project, so a harness can time any checked-out revision.
using ItemsetMining
using TOML: TOML

const USAGE = """
Usage:
  julia --project=CODE experiments/eclat_worker.jl --variant baseline|optimized
        --minsup FRACTION --output PATH --report PATH INPUT

Warm up, then time reading INPUT, mining it, and writing PATH separately.
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

function main(args)
    length(args) == 9 || throw(ArgumentError("expected four options and an input\n$USAGE"))
    values = Dict(args[i] => args[i+1] for i in 1:2:8)
    keys(values) == Set(["--variant", "--minsup", "--output", "--report"]) ||
        throw(ArgumentError("unexpected options $(collect(keys(values)))\n$USAGE"))
    input = args[9]
    variant = Symbol(values["--variant"])
    minsup = parse(Float64, values["--minsup"])

    warm_up(variant)
    read_seconds = @elapsed transactions = read_transactions(input)
    mined = @timed mine(transactions; minsup, variant)
    patterns = mined.value
    write_seconds = @elapsed write_itemsets(values["--output"], patterns)

    report = Dict{String,Any}(
        "transactions" => length(transactions),
        "minsup_count" => support_threshold(minsup, length(transactions)),
        "output_count" => length(patterns),
        "read_seconds" => read_seconds,
        "mine_seconds" => mined.time,
        "mine_gc_seconds" => mined.gctime,
        "mine_allocated_bytes" => mined.bytes,
        "write_seconds" => write_seconds,
        "julia_version" => string(VERSION),
        "threads" => Threads.nthreads(),
    )
    open(io -> TOML.print(io, report), values["--report"], "w")
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
