const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "experiments", "Experiments.jl"))
using .Experiments: parse_series_spec, curve_points, check_agreement, write_curves, median_ratios,
                    geometric_mean, csv_field, CurvePoint

const USAGE = """
Usage:
  julia --project=. scripts/runtime_curves.jl --out DIR [--ratio NUMERATOR/DENOMINATOR]... SERIES...
  julia --project=. scripts/runtime_curves.jl -h

SERIES is LABEL=RUN_DIR:VARIANT[@STAGE][#MODE]. Each reads the process rows of one
variant from RUN_DIR/runs.csv, so one figure can mix runs. A label may not contain
'/'. The command checks every series, then writes DIR/curves.csv (median and
quartiles per series and threshold, with every timeout, failure, and unverified
sample counted) and, with --ratio, DIR/ratios.csv (a ratio of two series' medians
per threshold). It prints each ratio's geometric mean per dataset and every point
that lost samples. Only exact samples give times.
"""

function parse_arguments(args)
    out = nothing
    ratios = Tuple{String,String}[]
    specs = String[]
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("--out", "--ratio")
            i < length(args) || throw(ArgumentError("$arg needs a value\n$USAGE"))
            value = args[i + 1]
            if arg == "--out"
                out = value
            else
                pair = split(value, '/'; limit=2)
                (length(pair) == 2 && all(!isempty, pair)) ||
                    throw(ArgumentError("--ratio needs NUMERATOR/DENOMINATOR, got $(repr(value))"))
                push!(ratios, (pair[1], pair[2]))
            end
            i += 2
        elseif startswith(arg, '-')
            throw(ArgumentError("unknown option $arg\n$USAGE"))
        else
            push!(specs, arg)
            i += 1
        end
    end
    out === nothing && throw(ArgumentError("--out is required\n$USAGE"))
    isempty(specs) && throw(ArgumentError("give at least one series\n$USAGE"))
    return out, ratios, parse_series_spec.(specs)
end

"""Describe the samples a point lost, or an empty string when every sample is exact."""
function lost_samples(p::CurvePoint)
    parts = String[]
    for (count, name) in ((p.timeouts, "timeout"), (p.correctness_failures, "correctness failure"),
                          (p.unverified, "unverified"), (p.interrupted, "interrupted"),
                          (p.other_incomplete, "incomplete"))
        count > 0 && push!(parts, "$count $name" * (count > 1 && name != "unverified" && name != "incomplete" ? "s" : ""))
    end
    return join(parts, ", ")
end

function main(args)
    if args == ["-h"] || args == ["--help"]
        println(USAGE)
        return 0
    end
    out, ratios, specs = parse_arguments(args)
    labels = [s.label for s in specs]
    allunique(labels) || throw(ArgumentError("series labels must differ, got $labels"))
    for (numerator, denominator) in ratios, label in (numerator, denominator)
        label in labels || throw(ArgumentError("--ratio names $(repr(label)), which is not a series label in $labels"))
    end
    points = reduce(vcat, curve_points.(specs))
    check_agreement(points)
    ratio_rows = [(numerator, denominator, r) for (numerator, denominator) in ratios
                  for r in median_ratios(points, numerator, denominator)]

    mkpath(out)
    write_curves(joinpath(out, "curves.csv"), points)
    if !isempty(ratios)
        open(joinpath(out, "ratios.csv"), "w") do io
            println(io, "numerator,denominator,dataset,minsup_relative,minsup_count,ratio")
            for (numerator, denominator, r) in ratio_rows
                println(io, join(csv_field.((numerator, denominator, r.dataset, r.minsup_relative, r.minsup_count, r.ratio)), ','))
            end
        end
    end

    for (numerator, denominator) in ratios
        println("$numerator/$denominator, ratio of median seconds:")
        mine = [r for (n, d, r) in ratio_rows if n == numerator && d == denominator]
        for dataset in unique(r.dataset for r in mine)
            values = [r.ratio for r in mine if r.dataset == dataset]
            println("  ", dataset, ": geometric mean ", round(geometric_mean(values); digits=2),
                    ", range ", round(minimum(values); digits=2), " to ", round(maximum(values); digits=2),
                    " over ", length(values), " points")
        end
        isempty(mine) && println("  no threshold has a time for both series")
    end
    lost = [(p, lost_samples(p)) for p in points if !isempty(lost_samples(p))]
    isempty(lost) || println("Points that lost samples:")
    for (p, text) in lost
        println("  ", p.series, " ", p.dataset, " ", p.minsup_relative, ": ", text,
                " (", p.exact_samples, " of ", p.total_samples, " exact)")
    end
    println("wrote ", out)
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
