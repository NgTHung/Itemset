"""
SplitMix64, a 64-bit generator that uses only integer arithmetic. The width
databases come from it instead of `Random.Xoshiro` because Julia does not promise
one random stream across versions, and a checksum in the manifest must hold on
every platform and Julia version that runs the tests.
"""
mutable struct SplitMix64
    state::UInt64
end

function next!(rng::SplitMix64)
    rng.state += 0x9e3779b97f4a7c15
    z = rng.state
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

"""An integer in 0:n-1. The modulo bias is below n / 2^64, which no database here can detect."""
function below!(rng::SplitMix64, n::Integer)
    n >= 1 || throw(ArgumentError("below! needs n of at least 1, got $n"))
    return Int(next!(rng) % UInt64(n))
end

"""
The synthetic databases of the transaction-width experiment. Every database
holds `transactions` transactions over item IDs 1 to `items`, and its width is
the exact length of each transaction.
"""
Base.@kwdef struct WidthSettings
    transactions::Int = 10_000
    items::Int = 100
    widths::Vector{Int} = [5, 10, 15, 20, 25, 30, 35, 40]
    seed::Int = DEFAULT_SEED
end

"""Throw `ArgumentError` unless the settings describe a valid experiment: positive sizes, increasing widths in 1 to `items`, and a nonnegative seed."""
function check_settings(settings::WidthSettings)
    settings.transactions >= 1 || throw(ArgumentError("transactions must be at least 1, got $(settings.transactions)"))
    settings.items >= 1 || throw(ArgumentError("items must be at least 1, got $(settings.items)"))
    settings.seed >= 0 || throw(ArgumentError("seed must be nonnegative, got $(settings.seed)"))
    isempty(settings.widths) && throw(ArgumentError("widths must not be empty"))
    issorted(settings.widths; lt=<=) ||
        throw(ArgumentError("widths must be strictly increasing, got $(settings.widths)"))
    all(w -> 1 <= w <= settings.items, settings.widths) ||
        throw(ArgumentError("widths must lie in 1 to $(settings.items), got $(settings.widths)"))
    return nothing
end

width_name(width::Integer) = "width-w" * lpad(width, 2, '0')

"""The seed of one width's stream: the experiment seed above the width, so streams never share a start."""
width_seed(settings::WidthSettings, width::Integer) = (UInt64(settings.seed) << 32) | UInt64(width)

"""
    width_database(settings, width) -> Vector{Vector{Int}}

Sampling model: each transaction is a uniformly random subset of exactly `width`
of the `items` item IDs, drawn independently of every other transaction by a
partial Fisher-Yates shuffle, and stored in ascending order. Items are
exchangeable, so no item pair co-occurs more than chance, and every k-itemset has
the expected support given by `expected_support`. Throws `ArgumentError` for a
width outside 1 to `items`.
"""
function width_database(settings::WidthSettings, width::Integer)
    check_settings(settings)
    1 <= width <= settings.items ||
        throw(ArgumentError("width must lie in 1 to $(settings.items), got $width"))
    rng = SplitMix64(width_seed(settings, width))
    pool = collect(1:settings.items)
    transactions = Vector{Vector{Int}}(undef, settings.transactions)
    for t in eachindex(transactions)
        for j in 1:width
            k = j + below!(rng, settings.items - j + 1)
            pool[j], pool[k] = pool[k], pool[j]
        end
        transactions[t] = sort!(pool[1:width])
    end
    return transactions
end

"""Write one width's database as SPMF text, one transaction per line."""
function write_width_database(path::AbstractString, settings::WidthSettings, width::Integer)
    write_transactions(path, width_database(settings, width))
    return nothing
end

"""
    expected_support(items, width, k) -> Float64

The probability that one transaction holds a given k-itemset, which is the
expected relative support of every k-itemset: ∏ (width - j) / (items - j) over
j = 0 to k - 1. It is 0 for k above the width. Throws `ArgumentError` for k below 1.
"""
function expected_support(items::Integer, width::Integer, k::Integer)
    k >= 1 || throw(ArgumentError("k must be at least 1, got $k"))
    k > width && return 0.0
    return prod((width - j) / (items - j) for j in 0:k-1)
end

"""
    density_stats(settings, width, database) -> NamedTuple

Density of the database (width over items), the least and most frequent item's
support, and the expected supports of an item, a pair, and a triple, in
transactions, so a table can set what the generator promises against what the file holds.
"""
function density_stats(settings::WidthSettings, width::Integer, database)
    supports = zeros(Int, settings.items)
    for transaction in database, item in transaction
        supports[item] += 1
    end
    n = length(database)
    return (width=Int(width), density=width / settings.items,
            item_support_min=minimum(supports), item_support_max=maximum(supports),
            expected_item_support=n * expected_support(settings.items, width, 1),
            expected_pair_support=n * expected_support(settings.items, width, 2),
            expected_triple_support=n * expected_support(settings.items, width, 3))
end

function width_entry(width::Integer, path::AbstractString, database)
    return DatasetEntry(name=width_name(width), version="uniform fixed-width v1", file=basename(path),
                        sha256=file_sha256(path), sources=DatasetSource[], stats=dataset_stats(database))
end

"""
    freeze_width_manifest(manifest_path, settings, dir)

Generate every width database into `dir` and write `manifest_path`, a manifest
with the SHA-256 and statistics of each file and no download source. Commit the
manifest: `ensure_width_databases` regenerates the files from it and refuses any
bytes it does not list, so the datasets can be rebuilt on any machine.
"""
function freeze_width_manifest(manifest_path::AbstractString, settings::WidthSettings, dir::AbstractString)
    check_settings(settings)
    mkpath(dir)
    tables = Dict{String,Any}()
    for width in settings.widths
        path = joinpath(dir, width_name(width) * ".txt")
        database = width_database(settings, width)
        write_transactions(path, database)
        entry = width_entry(width, path, database)
        stats = entry.stats
        tables[entry.name] = Dict{String,Any}(
            "version" => entry.version, "file" => entry.file, "sha256" => entry.sha256,
            "transactions" => stats.transactions, "items" => stats.items, "total_items" => stats.total_items,
            "max_width" => stats.max_width, "min_item" => stats.min_item, "max_item" => stats.max_item,
            "origin" => "Synthetic: $(settings.transactions) transactions, each a uniformly random subset of " *
                        "$width of $(settings.items) items, SplitMix64 seed $(width_seed(settings, width)); " *
                        "experiments/width.jl regenerates it",
            "terms" => "Generated by the team, no usage restriction",
            "sources" => Any[])
    end
    open(io -> TOML.print(io, tables), manifest_path, "w")
    return nothing
end

"""
    ensure_width_databases(dir, manifest, settings)

Make `dir` hold every width database the manifest lists, regenerating a file
that is missing or whose SHA-256 differs. A regenerated file reaches its final
name only when its bytes match the manifest, so a generator or settings change
throws an `ErrorException` instead of silently producing different data. Throws
`ArgumentError` for a width the manifest lacks.
"""
function ensure_width_databases(dir::AbstractString, manifest::AbstractDict{String,DatasetEntry},
                                settings::WidthSettings)
    check_settings(settings)
    mkpath(dir)
    for width in settings.widths
        entry = get(manifest, width_name(width), nothing)
        entry === nothing && throw(ArgumentError("the manifest has no entry $(width_name(width))"))
        path = joinpath(dir, entry.file)
        isfile(path) && file_sha256(path) == entry.sha256 && continue
        staged = tempname(dir; cleanup=false)
        try
            write_width_database(staged, settings, width)
            actual = file_sha256(staged)
            actual == entry.sha256 || error(
                "dataset $(entry.name): the generator now writes SHA-256 $actual, but the manifest records " *
                "$(entry.sha256); the settings or the generator changed")
            mv(staged, path; force=true)
        finally
            rm(staged; force=true)
        end
    end
    return nothing
end

"""The number of frequent itemsets at the absolute support count `count`, from the optimized miner's packed result."""
output_count(transactions, count::Integer) = length(mine_packed(transactions; minsup=count, variant=:optimized))

"""
    matched_count(transactions, target) -> Int

The largest support count at which `transactions` still has at least `target`
frequent itemsets. The output only falls as the count rises, so the search halves
the count from the top until the target is reached, then bisects the last
interval. It never mines far below the answer, because the output of a wide
database grows combinatorially as the count falls: count 1 on 40-item
transactions holds more itemsets than memory can. Setting each width's minsup this
way gives every width about the same output volume, which removes output size as
a cause of a runtime change. Throws `ArgumentError` for a target below 1 or one
that no count reaches; proving that mines count 1, which can be huge.
"""
function matched_count(transactions, target::Integer)
    target >= 1 || throw(ArgumentError("target must be at least 1, got $target"))
    low, high = 0, length(transactions) + 1    # output(high) < target <= output(low) once low >= 1
    most = 0
    count = length(transactions)
    while count >= 1
        output = output_count(transactions, count)
        count == 1 && (most = output)
        output >= target && (low = count; break)
        high = count
        count ÷= 2
    end
    low >= 1 || throw(ArgumentError("no support count gives $target itemsets; count 1 gives $most"))
    while high - low > 1
        middle = (low + high) ÷ 2
        output_count(transactions, middle) >= target ? (low = middle) : (high = middle)
    end
    return low
end

const PILOT_FIELDS = ["width", "density", "item_support_min", "expected_item_support", "item_support_max",
                      "expected_pair_support", "expected_triple_support", "fixed_count", "fixed_output",
                      "matched_count", "matched_output"]

"""
    pilot_rows(settings, databases; fixed_count, target) -> Vector{NamedTuple}

One row per width of `settings`, from the width's database in `databases` (a dictionary by width):
the density statistics of `density_stats`, the output at the fixed support count,
and the support count that `matched_count` finds for `target` itemsets with the
output it gives. A pilot reads this table to freeze the thresholds of the experiment.
Throws `ArgumentError` for a missing database or a fixed count below 1.
"""
function pilot_rows(settings::WidthSettings, databases::AbstractDict; fixed_count::Integer, target::Integer)
    fixed_count >= 1 || throw(ArgumentError("fixed_count must be at least 1, got $fixed_count"))
    rows = NamedTuple[]
    for width in settings.widths
        haskey(databases, width) || throw(ArgumentError("no database for width $width"))
        database = databases[width]
        count = matched_count(database, target)
        push!(rows, (; density_stats(settings, width, database)..., fixed_count=Int(fixed_count),
                     fixed_output=output_count(database, fixed_count), matched_count=count,
                     matched_output=output_count(database, count)))
    end
    return rows
end

"""Write the rows of `pilot_rows` as CSV."""
function write_pilot(path::AbstractString, rows)
    open(path, "w") do io
        println(io, join(PILOT_FIELDS, ','))
        for row in rows
            println(io, join((csv_field(getfield(row, Symbol(f))) for f in PILOT_FIELDS), ','))
        end
    end
    return nothing
end
