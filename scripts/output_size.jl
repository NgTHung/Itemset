const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "experiments", "Experiments.jl"))
using .Experiments: read_csv_rows, parse_series_spec, curve_points, check_agreement, check_monotone_counts,
                    itemset_length_counts, check_nested_outputs, csv_field

const USAGE = """
Usage:
  julia --project=. scripts/output_size.jl RUN_DIR --out DIR [--variant VARIANT]

Read the frequent-itemset counts of every threshold in RUN_DIR/runs.csv, which a
timing run already measured, so no mining is repeated. The command checks that all
variants agree on each count, that no count falls when minsup falls, and that each
kept output of VARIANT (default optimized) holds exactly the itemsets and supports of
the next higher threshold's output. It then writes DIR/output-size.csv with the count
and itemset-length profile of every threshold.
"""

function parse_arguments(args)
    run, out, variant = nothing, nothing, "optimized"
    i = 1
    while i <= length(args)
        if args[i] in ("--out", "--variant")
            i < length(args) || throw(ArgumentError("$(args[i]) needs a value\n$USAGE"))
            args[i] == "--out" ? (out = args[i+1]) : (variant = args[i+1])
            i += 2
        elseif run === nothing && !startswith(args[i], '-')
            run = args[i]
            i += 1
        else
            throw(ArgumentError("unexpected argument $(args[i])\n$USAGE"))
        end
    end
    (run === nothing || out === nothing) && throw(ArgumentError("RUN_DIR and --out are required\n$USAGE"))
    return run, out, variant
end

"""The output file of the first exact process row of `variant` at each (dataset, count), keyed by both."""
function kept_outputs(run, variant)
    outputs = Dict{Tuple{String,Int},String}()
    for row in read_csv_rows(joinpath(run, "runs.csv"))
        row["timing_scope"] == "process" && row["variant"] == variant || continue
        row["status"] == "ok" && row["correctness_status"] == "exact" || continue
        key = (row["dataset"], parse(Int, row["minsup_count"]))
        path = joinpath(run, "attempts", row["attempt_id"], "output.txt")
        haskey(outputs, key) || !isfile(path) || (outputs[key] = path)
    end
    return outputs
end

function main(args)
    if args == ["-h"] || args == ["--help"]
        println(USAGE)
        return 0
    end
    run, out, variant = parse_arguments(args)
    variants = unique(r["variant"] for r in read_csv_rows(joinpath(run, "runs.csv")) if r["timing_scope"] == "process")
    points = reduce(vcat, [curve_points(parse_series_spec("$v=$run:$v")) for v in variants])
    check_agreement(points)
    check_monotone_counts(points)
    outputs = kept_outputs(run, variant)
    rows = String[]
    for dataset in unique(p.dataset for p in points)
        mine = sort!([p for p in points if p.dataset == dataset && p.series == variant]; by=p -> -p.minsup_count)
        previous = nothing
        for p in mine
            path = get(outputs, (dataset, p.minsup_count), nothing)
            path === nothing && throw(ArgumentError("$run keeps no exact $variant output for $dataset at count $(p.minsup_count)"))
            lengths = itemset_length_counts(path)
            sum(lengths) == p.output_count || throw(ArgumentError(
                "$path holds $(sum(lengths)) itemsets, but runs.csv reports $(p.output_count)"))
            previous === nothing || check_nested_outputs(previous[2], path, previous[1])
            previous = (p.minsup_count, path)
            mean_length = sum(k * n for (k, n) in enumerate(lengths)) / max(1, sum(lengths))
            fields = (dataset, p.minsup_relative, p.minsup_count, p.output_count, length(lengths),
                      round(mean_length; digits=3), join(("$k:$n" for (k, n) in enumerate(lengths) if n > 0), ';'))
            push!(rows, join((csv_field(f) for f in fields), ','))
        end
        println(dataset, ": ", length(mine), " thresholds, counts agree, never fall, and outputs nest")
    end
    mkpath(out)
    open(joinpath(out, "output-size.csv"), "w") do io
        println(io, "dataset,minsup_relative,minsup_count,output_count,max_length,mean_length,length_counts")
        foreach(row -> println(io, row), rows)
    end
    println("wrote ", joinpath(out, "output-size.csv"))
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
