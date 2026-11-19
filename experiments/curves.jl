"""
    read_csv_rows(path) -> Vector{Dict{String,String}}

Read a CSV file with a header into one dictionary per record. Fields may be
quoted, with commas, doubled quotes, and line breaks inside, as `csv_field`
writes them. A leading byte-order mark, CRLF line ends, and blank lines are
accepted. Throws `ArgumentError` for a missing or empty file, an unterminated
quote, or a record whose field count differs from the header, naming the line.
"""
function read_csv_rows(path::AbstractString)
    isfile(path) || throw(ArgumentError("$path does not exist"))
    text = read(path, String)
    startswith(text, '﻿') && (text = text[nextind(text, 1):end])
    records = Tuple{Int,Vector{String}}[]
    field = IOBuffer()
    current = String[]
    line, record_line, quoted = 1, 1, false
    blank(fields) = length(fields) == 1 && isempty(only(fields))
    finish_record!() = begin
        push!(current, String(take!(field)))
        blank(current) || push!(records, (record_line, current))
        current = String[]
    end
    i = firstindex(text)
    while i <= lastindex(text)
        c = text[i]
        if quoted
            if c == '"'
                next = nextind(text, i)
                if next <= lastindex(text) && text[next] == '"'
                    print(field, '"')
                    i = next
                else
                    quoted = false
                end
            else
                c == '\n' && (line += 1)
                print(field, c)
            end
        elseif c == '"'
            quoted = true
        elseif c == ','
            push!(current, String(take!(field)))
        elseif c == '\n'
            finish_record!()
            line += 1
            record_line = line
        elseif c != '\r'
            print(field, c)
        end
        i = nextind(text, i)
    end
    quoted && throw(ArgumentError("$path line $record_line: unterminated quoted field"))
    (position(field) > 0 || !isempty(current)) && finish_record!()
    isempty(records) && throw(ArgumentError("$path has no header"))
    header = last(first(records))
    rows = Dict{String,String}[]
    for (number, fields) in records[2:end]
        length(fields) == length(header) ||
            throw(ArgumentError("$path line $number: expected $(length(header)) fields, got $(length(fields))"))
        push!(rows, Dict(zip(header, fields)))
    end
    return rows
end

"""One curve of a figure: the rows of `variant` (and `stage`, `mode`, when named) in a run folder."""
struct SeriesSpec
    label::String
    run::String
    variant::String
    stage::String
    mode::String
end

"""
    parse_series_spec(text) -> SeriesSpec

Parse `LABEL=RUN_DIR:VARIANT[@STAGE][#MODE]`. The run folder may hold colons,
as a Windows drive does, because the variant follows the last one. Throws
`ArgumentError` for a missing label, folder, or variant, or an empty stage or mode.
"""
function parse_series_spec(text::AbstractString)
    label, separator, source = partition(text, '=')
    (isempty(separator) || isempty(label)) &&
        throw(ArgumentError("series $(repr(text)) needs a label: LABEL=RUN_DIR:VARIANT[@STAGE][#MODE]"))
    colon = findlast(':', source)
    colon === nothing && throw(ArgumentError("series $(repr(text)) needs RUN_DIR:VARIANT after the label"))
    run, rest = source[1:prevind(source, colon)], source[nextind(source, colon):end]
    head, hash, mode = partition(rest, '#')
    variant, at, stage = partition(head, '@')
    (isempty(run) || isempty(variant)) && throw(ArgumentError("series $(repr(text)) needs a folder and a variant"))
    (!isempty(at) && isempty(stage) || !isempty(hash) && isempty(mode)) &&
        throw(ArgumentError("series $(repr(text)) has an empty stage or mode"))
    return SeriesSpec(label, run, variant, stage, mode)
end

"""`partition` of `text` at its first `separator`: before, the separator or empty, and after."""
function partition(text::AbstractString, separator::Char)
    index = findfirst(separator, text)
    index === nothing && return (String(text), "", "")
    return (text[1:prevind(text, index)], string(separator), text[nextind(text, index):end])
end

"""
Median and quartiles of one contender at one threshold, with every sample that
did not count. `exact_samples` hold the statistics; the other counts partition
the remaining samples, so a timeout or a wrong output stays visible. Times are
NaN and `output_count` is `nothing` when no sample is exact.
"""
struct CurvePoint
    series::String
    dataset::String
    minsup_relative::String
    minsup_count::Int
    output_count::Union{Int,Nothing}
    exact_samples::Int
    total_samples::Int
    timeouts::Int
    correctness_failures::Int
    unverified::Int
    interrupted::Int
    other_incomplete::Int
    q1::Float64
    median::Float64
    q3::Float64
end

const CURVE_COLUMNS = ["dataset", "minsup_relative", "minsup_count", "variant", "stage", "mode",
                       "timing_scope", "status", "correctness_status", "elapsed_seconds", "output_count"]

"""Process rows of the spec's variant, refusing a selection that spans several stages or modes."""
function series_rows(spec::SeriesSpec)
    path = joinpath(spec.run, "runs.csv")
    rows = read_csv_rows(path)
    missing_columns = isempty(rows) ? String[] : filter(c -> !haskey(first(rows), c), CURVE_COLUMNS)
    isempty(missing_columns) || throw(ArgumentError("$path lacks the columns $(join(missing_columns, ", "))"))
    selected = filter(rows) do r
        r["timing_scope"] == "process" && r["variant"] == spec.variant &&
            (isempty(spec.stage) || r["stage"] == spec.stage) && (isempty(spec.mode) || r["mode"] == spec.mode)
    end
    isempty(selected) && throw(ArgumentError(
        "$path has no process rows for $(spec.variant)" *
        (isempty(spec.stage) ? "" : "@" * spec.stage) * (isempty(spec.mode) ? "" : "#" * spec.mode)))
    stages = sort!(unique(r["stage"] for r in selected))
    length(stages) > 1 && throw(ArgumentError(
        "$(spec.variant) in $path has stages $stages; name one as $(spec.variant)@STAGE"))
    modes = sort!(unique(r["mode"] for r in selected))
    length(modes) > 1 && throw(ArgumentError(
        "$(spec.variant) in $path has modes $modes; name one as $(spec.variant)#MODE"))
    return selected
end

"""
    curve_points(spec) -> Vector{CurvePoint}

One point per threshold of the spec's rows, in file order. Only exact,
successful samples give times, with quartiles interpolated as in `summary.csv`.
Throws `ArgumentError` when exact samples at a threshold report different
output counts, because exact outputs are one map.
"""
function curve_points(spec::SeriesSpec)
    groups = Dict{Tuple{String,String},Vector{Dict{String,String}}}()
    order = Tuple{String,String}[]
    for row in series_rows(spec)
        key = (row["dataset"], row["minsup_count"])
        haskey(groups, key) || push!(order, key)
        push!(get!(groups, key, Dict{String,String}[]), row)
    end
    return [curve_point(spec.label, groups[key]) for key in order]
end

function curve_point(label::String, samples::Vector{Dict{String,String}})
    exact(r) = r["status"] == "ok" && r["correctness_status"] == "exact"
    valid = filter(exact, samples)
    times = sort!([parse(Float64, r["elapsed_seconds"]) for r in valid])
    counts = unique(r["output_count"] for r in valid)
    first_row = first(samples)
    # The count identifies a threshold; two spellings of it would mix their samples.
    spellings = sort!(unique(r["minsup_relative"] for r in samples))
    length(spellings) > 1 && throw(ArgumentError(
        "$label at $(first_row["dataset"]) count $(first_row["minsup_count"]) has minsup $spellings; " *
        "two thresholds with one count would share a point"))
    length(counts) > 1 && throw(ArgumentError(
        "$label at $(first_row["dataset"]) $(first_row["minsup_relative"]) reports output counts $(sort!(counts)) in exact samples"))
    failures = count(r -> r["correctness_status"] == "failed", samples)
    timeouts = count(r -> r["status"] == "timeout" && r["correctness_status"] != "failed", samples)
    interrupted = count(r -> r["status"] == "interrupted" && r["correctness_status"] != "failed", samples)
    unverified = count(r -> r["status"] == "ok" && !(r["correctness_status"] in ("exact", "failed")), samples)
    other = length(samples) - length(valid) - failures - timeouts - interrupted - unverified
    quantile(fraction) = isempty(times) ? NaN : sample_quantile(times, fraction)
    return CurvePoint(label, first_row["dataset"], first_row["minsup_relative"], parse(Int, first_row["minsup_count"]),
        isempty(counts) ? nothing : parse(Int, only(counts)), length(valid), length(samples), timeouts,
        failures, unverified, interrupted, other, quantile(0.25), quantile(0.5), quantile(0.75))
end

"""
    check_agreement(points)

Throw `ArgumentError` when contenders at one dataset and threshold report
different output counts. Exact outputs are the same map, so their counts must match.
"""
function check_agreement(points::AbstractVector{CurvePoint})
    seen = Dict{Tuple{String,Int},Tuple{Int,String}}()
    for p in points
        p.output_count === nothing && continue
        key = (p.dataset, p.minsup_count)
        known = get!(seen, key, (p.output_count, p.series))
        known[1] == p.output_count || throw(ArgumentError(
            "$(p.dataset) at count $(p.minsup_count): $(known[2]) reports $(known[1]) itemsets, $(p.series) reports $(p.output_count)"))
    end
    return nothing
end

"""Ratio of `numerator`'s median to `denominator`'s at every point where both have a time, in the numerator's order."""
function median_ratios(points::AbstractVector{CurvePoint}, numerator::AbstractString, denominator::AbstractString)
    bottom = Dict((p.dataset, p.minsup_count) => p for p in points if p.series == denominator && !isnan(p.median))
    return [(dataset=p.dataset, minsup_relative=p.minsup_relative, minsup_count=p.minsup_count,
             ratio=p.median / bottom[p.dataset, p.minsup_count].median)
            for p in points if p.series == numerator && !isnan(p.median) && haskey(bottom, (p.dataset, p.minsup_count))]
end

"""Geometric mean of positive values. Throws `ArgumentError` for an empty list or a value that is not positive."""
function geometric_mean(values::AbstractVector{<:Real})
    isempty(values) && throw(ArgumentError("a geometric mean needs at least one value"))
    all(>(0), values) || throw(ArgumentError("a geometric mean needs positive values, got $(collect(values))"))
    return exp(sum(log, values) / length(values))
end

const CURVE_FIELDS = ["dataset", "minsup_relative", "minsup_count", "series", "output_count", "exact_samples",
                      "total_samples", "timeouts", "correctness_failures", "unverified", "interrupted",
                      "other_incomplete", "median_seconds", "q1_seconds", "q3_seconds"]

"""Write the tidy table behind a figure: one row per series and threshold, blank where nothing is known."""
function write_curves(path::AbstractString, points::AbstractVector{CurvePoint})
    number(x) = isnan(x) ? "" : string(x)
    open(path, "w") do io
        println(io, join(CURVE_FIELDS, ','))
        for p in points
            fields = (p.dataset, p.minsup_relative, p.minsup_count, p.series, something(p.output_count, ""),
                      p.exact_samples, p.total_samples, p.timeouts, p.correctness_failures, p.unverified,
                      p.interrupted, p.other_incomplete, number(p.median), number(p.q1), number(p.q3))
            println(io, join((csv_field(f) for f in fields), ','))
        end
    end
    return nothing
end
