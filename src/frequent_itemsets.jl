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

function Base.iterate(packed::FrequentItemsets, k::Int=1)
    k > length(packed) && return nothing
    items = view(packed.items, packed.offsets[k]:packed.offsets[k+1]-1)
    return items => packed.supports[k], k + 1
end

"""Append one itemset, copied from `items`, with its support."""
function push_itemset!(packed::FrequentItemsets, items::Vector{Int}, support::Int)
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
