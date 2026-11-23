row_value(row::NamedTuple, field::AbstractString, index::Integer) =
    hasproperty(row, Symbol(field)) ? getproperty(row, Symbol(field)) :
    throw(ArgumentError("row $index lacks field $field"))
row_value(row::AbstractDict, field::AbstractString, index::Integer) =
    haskey(row, field) ? row[field] : throw(ArgumentError("row $index lacks field $field"))

"""
    write_rows(path, fields, rows)

Write `rows`, each a `NamedTuple` or a `Dict` keyed by field name, as CSV under the header
`fields`. Every row is checked for every field before the file opens, so a bad row leaves no
partial file. Throws `ArgumentError` naming the row and the field.
"""
function write_rows(path::AbstractString, fields::AbstractVector{<:AbstractString}, rows)
    lines = [join((csv_field(row_value(row, field, index)) for field in fields), ',')
             for (index, row) in enumerate(rows)]
    open(path, "w") do io
        println(io, join(fields, ','))
        foreach(line -> println(io, line), lines)
    end
    return nothing
end

"""
    for_each_point(f, config, manifest, data_dir; keep=false) -> Vector

For every series of `config` and every minsup in it, from the highest down, call `f(point)` and
collect the results. `point` is `(; dataset, path, minsup_relative, minsup_count, transactions)`,
where `path` is the file `prepare_dataset` verifies in `data_dir` and `minsup_count` is
`support_threshold` of the minsup on that file's transaction count. The file is read once per
dataset, and `transactions` holds the database only when `keep` is true, so a caller that times
its own reading does not keep a second copy alive. Throws `ArgumentError` for a dataset the
manifest lacks.
"""
function for_each_point(f, config::RunConfig, manifest::AbstractDict{String,DatasetEntry},
                        data_dir::AbstractString; keep::Bool=false)
    results = []
    for series in config.series
        haskey(manifest, series.dataset) || throw(ArgumentError("unknown dataset $(repr(series.dataset))"))
        path = prepare_dataset(manifest[series.dataset], data_dir)
        transactions = read_transactions(path)
        size = length(transactions)
        kept = keep ? transactions : nothing
        transactions = nothing
        for minsup in sort(series.minsup; rev=true)
            point = (; dataset=series.dataset, path, minsup_relative=string(minsup),
                     minsup_count=support_threshold(minsup, size), transactions=kept)
            push!(results, f(point))
        end
    end
    return identity.(results)
end

"""
    parse_table_args(args, usage, data_dir; repeats=false) -> NamedTuple

Parse the options of a script that writes a table for every point of a run configuration:
`--out DIR`, `--manifest PATH` (default `manifest.toml` in `data_dir`), `--repeats N` when
`repeats` is true, and one `CONFIG` path. Returns `(; out, config, manifest, repeats)`, with
`repeats` set to `nothing` unless the option is given. Throws `ArgumentError` with `usage` for a
missing or unknown argument, a second `CONFIG`, or a `--repeats` value below 1.
"""
function parse_table_args(args, usage::AbstractString, data_dir::AbstractString; repeats::Bool=false)
    out = nothing
    config = nothing
    manifest = joinpath(data_dir, "manifest.toml")
    count = nothing
    options = repeats ? ("--out", "--manifest", "--repeats") : ("--out", "--manifest")
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in options
            i < length(args) || throw(ArgumentError("$arg needs a value\n$usage"))
            value = args[i + 1]
            if arg == "--out"
                out = value
            elseif arg == "--manifest"
                manifest = value
            else
                count = tryparse(Int, value)
                (count !== nothing && count >= 1) ||
                    throw(ArgumentError("--repeats needs an integer of at least 1, got $(repr(value))"))
            end
            i += 2
        elseif startswith(arg, '-')
            throw(ArgumentError("unknown option $arg\n$usage"))
        else
            config === nothing || throw(ArgumentError("give one CONFIG, got $(repr(config)) and $(repr(arg))\n$usage"))
            config = arg
            i += 1
        end
    end
    (out === nothing || config === nothing) && throw(ArgumentError("--out and CONFIG are required\n$usage"))
    return (; out, config, manifest, repeats=count)
end
