"""
Support of every pair of root items, in a triangular table over their ranks in
the root class. Zaki (2000, Sec. 4.2) counts the 2-itemsets this way from the
horizontal database, so a root join whose pair is infrequent is never run.
"""
struct PairCounts
    m::Int
    counts::Vector{Int32}
end

"""The filter for classes below the root, and for databases where counting costs more than it saves."""
struct NoPairCounts end

"""Slot of ranks `i < j` among `m` items: row `i` starts after the `(i - 1)` rows above it."""
pair_slot(m::Int, i::Int, j::Int) = (i - 1) * m - (i - 1) * i ÷ 2 + (j - i)

"""
Number of slots for `m` items, or `nothing` when `m(m - 1)/2` overflows or the
table would pass `MAX_PAIR_SLOTS`; the search then joins every root pair instead.
"""
function pair_table_length(m::Int)
    product, overflow = Base.mul_with_overflow(m, m - 1)
    overflow && return nothing
    slots = product ÷ 2
    return slots <= MAX_PAIR_SLOTS ? slots : nothing
end

# 2^28 Int32 slots is 1 GiB, an eighth of the 8 GiB peak RSS the plan allows.
const MAX_PAIR_SLOTS = 2^28

"""
    count_pairs(database, items) -> PairCounts

Count, for each pair of entries of `items`, the transactions of `database` that
hold both. Ranks are positions in `items`. Throws `ArgumentError` when the table
for `length(items)` items cannot be allocated.
"""
function count_pairs(database::Vector{Vector{Int}}, items::Vector{Int})
    m = length(items)
    slots = pair_table_length(m)
    slots === nothing && throw(ArgumentError("a pair table for $m items has more than $MAX_PAIR_SLOTS slots"))
    counts = zeros(Int32, slots)
    rank = Dict(item => r for (r, item) in enumerate(items))
    ranks = Int[]
    for transaction in database
        empty!(ranks)
        for item in transaction
            r = get(rank, item, 0)
            r == 0 || push!(ranks, r)
        end
        sort!(ranks)
        for x in eachindex(ranks), y in x+1:lastindex(ranks)
            counts[pair_slot(m, ranks[x], ranks[y])] += Int32(1)
        end
    end
    return PairCounts(m, counts)
end

pair_support(pairs::PairCounts, i::Int, j::Int) = Int(pairs.counts[pair_slot(pairs.m, i, j)])

"""Whether the join of class members `i < j` can reach `minsup`; without counts, always."""
may_be_frequent(pairs::PairCounts, i::Int, j::Int, minsup::Int) = pair_support(pairs, i, j) >= minsup
may_be_frequent(::NoPairCounts, i::Int, j::Int, minsup::Int) = true

# A table increment hits a random slot and can miss the cache, while a join word is read in order.
const PAIR_COST_RATIO = 10

"""
    pair_filter(database, items) -> PairCounts or NoPairCounts

Count pairs only when that costs less than the root joins it can skip. Counting
touches at most the sum of `|t|(|t| - 1)/2` slots over transactions `t`, and the
root joins read `m(m - 1)/2` bitsets of `⌈N/64⌉` words each. Dense data, with
long transactions over few items, joins instead.
"""
function pair_filter(database::Vector{Vector{Int}}, items::Vector{Int})
    slots = pair_table_length(length(items))
    (slots === nothing || slots == 0 || length(database) > typemax(Int32)) && return NoPairCounts()
    increments = sum(t -> length(t) * (length(t) - 1) ÷ 2, database; init=0)
    join_words = slots * cld(length(database), 64)
    return increments * PAIR_COST_RATIO < join_words ? count_pairs(database, items) : NoPairCounts()
end
