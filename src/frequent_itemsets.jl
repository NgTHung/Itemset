"""
    FrequentItemsets(items, offsets, supports)
    FrequentItemsets()

Frequent itemsets stored back to back in one flat `items` vector. Itemset `k` is
`items[offsets[k]:offsets[k+1]-1]` and has support `supports[k]`, so a miner adds
an itemset with three appends and never builds a per-itemset key.

Iterating yields `itemset => support` pairs, where `itemset` is a view into
`items`. Throws `ArgumentError` when `offsets` does not start at 1, decrease, or
end one past `items`, or when it does not hold one more entry than `supports`.
"""
struct FrequentItemsets
    items::Vector{Int}
    offsets::Vector{Int}
    supports::Vector{Int}

    function FrequentItemsets(items::Vector{Int}, offsets::Vector{Int}, supports::Vector{Int})
        length(offsets) == length(supports) + 1 ||
            throw(ArgumentError("offsets must have one more entry than supports, got $(length(offsets)) and $(length(supports))"))
        first(offsets) == 1 && last(offsets) == length(items) + 1 && issorted(offsets) ||
            throw(ArgumentError("offsets must rise from 1 to $(length(items) + 1), got $offsets"))
        return new(items, offsets, supports)
    end
end

FrequentItemsets() = FrequentItemsets(Int[], [1], Int[])

Base.length(packed::FrequentItemsets) = length(packed.supports)
Base.eltype(::Type{FrequentItemsets}) = Pair{SubArray{Int, 1, Vector{Int}, Tuple{UnitRange{Int}}, true}, Int}

itemset_view(packed::FrequentItemsets, k::Int) = view(packed.items, packed.offsets[k]:packed.offsets[k+1]-1)

function Base.iterate(packed::FrequentItemsets, k::Int=1)
    k > length(packed) && return nothing
    return itemset_view(packed, k) => packed.supports[k], k + 1
end

"""Append one itemset, copied from `items`, with its support."""
function push_itemset!(packed::FrequentItemsets, items, support::Integer)
    append!(packed.items, items)
    push!(packed.offsets, length(packed.items) + 1)
    push!(packed.supports, support)
    return packed
end

"""
    support_map(packed::FrequentItemsets) -> SupportMap

Convert packed itemsets to the tuple-keyed map that applications read. A repeated
itemset keeps its last support, so callers that must detect repeats compare
`length(packed)` with the length of the map.
"""
function support_map(packed::FrequentItemsets)
    patterns = SupportMap()
    sizehint!(patterns, length(packed))
    for (items, support) in packed
        patterns[Tuple(items)] = support
    end
    return patterns
end

"""
    write_itemsets(io_or_path, packed::FrequentItemsets)

Write packed itemsets in the same format and order as a `SupportMap`, so both
forms give byte-identical files. Validates every itemset before opening the
output and throws `ArgumentError` naming the first empty, unsorted, negative,
or repeated itemset, or a support below 1.
"""
function write_itemsets(io::IO, packed::FrequentItemsets)
    order = checked_order(packed)
    print_packed(io, packed, order)
end

function write_itemsets(path::AbstractString, packed::FrequentItemsets)
    order = checked_order(packed)
    open(io -> print_packed(io, packed, order), path, "w")
end

"""Validate every itemset, then return the numeric lexicographic write order."""
function checked_order(packed::FrequentItemsets)
    for (k, (items, support)) in enumerate(packed)
        !isempty(items) && first(items) >= 0 && all(items[i] < items[i+1] for i in 1:length(items)-1) ||
            throw(ArgumentError("itemset $k must hold ascending nonnegative item IDs, got $(collect(items))"))
        support >= 1 || throw(ArgumentError("itemset $k has support $support; supports must be at least 1"))
    end
    order = collect(1:length(packed))
    precedes(a, b) = itemset_isless(packed, a, b)
    # A depth-first search over ascending items already emits this order, so sorting is usually skipped.
    issorted(order; lt=precedes) || sort!(order; lt=precedes)
    for i in 2:length(order)
        precedes(order[i-1], order[i]) ||
            throw(ArgumentError("itemset $(collect(itemset_view(packed, order[i]))) appears more than once"))
    end
    return order
end

"""Compare itemsets `a` and `b` as numbers, item by item; a prefix sorts first."""
function itemset_isless(packed::FrequentItemsets, a::Int, b::Int)
    offsets, items = packed.offsets, packed.items
    i, j = offsets[a], offsets[b]
    while i < offsets[a+1] && j < offsets[b+1]
        items[i] == items[j] || return items[i] < items[j]
        i += 1
        j += 1
    end
    return i == offsets[a+1] && j < offsets[b+1]
end

const SUPPORT_TAG = codeunits(" #SUP: ")
const WRITE_CHUNK = 1 << 16

function print_packed(io::IO, packed::FrequentItemsets, order::Vector{Int})
    buffer = UInt8[]
    sizehint!(buffer, WRITE_CHUNK)
    for k in order
        for position in packed.offsets[k]:packed.offsets[k+1]-1
            position == packed.offsets[k] || push!(buffer, UInt8(' '))
            append_digits!(buffer, packed.items[position])
        end
        append!(buffer, SUPPORT_TAG)
        append_digits!(buffer, packed.supports[k])
        push!(buffer, UInt8('\n'))
        if length(buffer) >= WRITE_CHUNK
            write(io, buffer)
            empty!(buffer)
        end
    end
    write(io, buffer)
    return nothing
end

"""Append the decimal digits of a nonnegative `value`, without building a string."""
function append_digits!(buffer::Vector{UInt8}, value::Int)
    start = length(buffer) + 1
    while true
        push!(buffer, UInt8('0') + UInt8(value % 10))
        value ÷= 10
        value == 0 && break
    end
    reverse!(buffer, start, length(buffer))
    return buffer
end
