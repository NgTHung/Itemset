"""
Statistics computed from a database file. `total_items` replaces a stored mean
width, so a manifest compares exact integers instead of rounded floats.
"""
Base.@kwdef struct DatasetStats
    transactions::Int
    items::Int
    total_items::Int
    max_width::Int
    min_item::Int
    max_item::Int
end

mean_width(stats::DatasetStats) =
    stats.transactions == 0 ? 0.0 : stats.total_items / stats.transactions

"""One location of a dataset. `format` is `:text` or `:gzip`."""
Base.@kwdef struct DatasetSource
    url::String
    format::Symbol
end

"""
A file identified by its SHA-256. Sources are only locations: any source whose
bytes hash to `sha256` is acceptable. `stats` is `nothing` for a raw file, such
as an application's CSV, that is not an SPMF transaction database.
"""
Base.@kwdef struct DatasetEntry
    name::String
    version::String
    file::String
    sha256::String
    sources::Vector{DatasetSource}
    stats::Union{Nothing,DatasetStats}
end

const STAT_KEYS = ("transactions", "items", "total_items", "max_width", "min_item", "max_item")

"""
    dataset_stats(transactions) -> DatasetStats

Count transactions, distinct items, and widths of canonical transactions, as
returned by `read_transactions`. An empty database reports zero for every field.
"""
function dataset_stats(transactions::AbstractVector{<:AbstractVector{Int}})
    frequencies = item_frequencies(transactions)
    items = keys(frequencies)
    total = 0
    max_width = 0
    for transaction in transactions
        total += length(transaction)
        max_width = max(max_width, length(transaction))
    end
    low, high = isempty(items) ? (0, 0) : extrema(items)
    return DatasetStats(transactions=length(transactions), items=length(items),
                        total_items=total, max_width=max_width, min_item=low, max_item=high)
end

file_sha256(path::AbstractString) = open(io -> bytes2hex(sha256(io)), path)

"""
    load_manifest(path) -> Dict{String,DatasetEntry}

Read a manifest. An entry gives either all statistics or none. Throws
`ArgumentError` naming the dataset and key for a missing or malformed field, so
a typo fails before any download starts.
"""
load_manifest(path::AbstractString) = parse_manifest(read(path, String))

function parse_manifest(text::AbstractString)
    entries = Dict{String,DatasetEntry}()
    for (name, table) in TOML.parse(text)
        table isa AbstractDict || throw(ArgumentError("manifest entry $name must be a table"))
        field(key, type) = begin
            value = get(table, key, nothing)
            value isa type || throw(ArgumentError("dataset $name: $key must be a $type"))
            value
        end
        version, file, sha = field("version", String), field("file", String), field("sha256", String)
        stats = any(in(keys(table)), STAT_KEYS) ?
            DatasetStats(; (Symbol(key) => field(key, Int) for key in STAT_KEYS)...) : nothing
        sources = DatasetSource[]
        for source in field("sources", Vector)
            format = Symbol(get(source, "format", ""))
            format in (:text, :gzip) ||
                throw(ArgumentError("dataset $name: source format must be text or gzip, got $(repr(format))"))
            url = get(source, "url", nothing)
            url isa String || throw(ArgumentError("dataset $name: every source needs a url"))
            push!(sources, DatasetSource(; url, format))
        end
        entries[name] = DatasetEntry(; name, version, file, sha256=sha, sources, stats)
    end
    return entries
end

"""
    prepare_dataset(entry, dir; fetch=Downloads.download) -> path

Return `dir/entry.file` after checking its SHA-256 and any statistics, downloading it
first if it is absent or has the wrong bytes. Sources are tried in order and the
first verified one wins. A file reaches its final name only after both checks
pass, so an interrupted or wrong download never looks prepared. Throws
`ErrorException` listing each source's failure when no source verifies, or when
the verified file's statistics differ from the manifest.
"""
function prepare_dataset(entry::DatasetEntry, dir::AbstractString; fetch=Downloads.download)
    path = joinpath(dir, entry.file)
    isfile(path) && file_sha256(path) == entry.sha256 && return path
    failures = String[]
    for source in entry.sources
        staged = tempname(dir; cleanup=false)
        try
            failure = stage_source(source, staged, entry.sha256; fetch)
            if failure === nothing
                # Verified bytes with the wrong statistics mean the manifest
                # itself is wrong, so this stops the search instead of trying
                # another source.
                if entry.stats !== nothing
                    stats = dataset_stats(read_transactions(staged))
                    stats == entry.stats ||
                        error("dataset $(entry.name): computed $stats differs from manifest $(entry.stats)")
                end
                mv(staged, path; force=true)
                return path
            end
            push!(failures, "$(source.url): $failure")
        finally
            rm(staged; force=true)
            rm(staged * ".download"; force=true)
        end
    end
    error("dataset $(entry.name): no source produced verified bytes\n  " * join(failures, "\n  "))
end

"""Fetch one source into `staged`. Return `nothing` when its bytes verify, else the reason."""
function stage_source(source::DatasetSource, staged::AbstractString, expected::AbstractString; fetch)
    try
        fetch_source(source, staged; fetch)
    catch err
        # A broken mirror rules out only that source, so the caller tries the next.
        return sprint(showerror, err)
    end
    actual = file_sha256(staged)
    return actual == expected ? nothing : "SHA-256 $actual, expected $expected"
end

function fetch_source(source::DatasetSource, staged::AbstractString; fetch)
    if source.format == :text
        fetch(source.url, staged)
    else
        archive = staged * ".download"
        fetch(source.url, archive)
        open(staged, "w") do io
            run(pipeline(`$(p7zip()) e -so -tgzip $archive`; stdout=io, stderr=devnull))
        end
    end
    return staged
end
