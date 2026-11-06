"""
One member of a prefix-based equivalence class: the last item of `prefix ∪ {item}`,
that itemset's support, and its bitset tidset.
"""
struct BitsetMember
    item::Int
    support::Int
    words::Vector{UInt64}
end

"""
Frequent items as `item => support`, in increasing support with ties broken by
item. Rare items first keep the classes near the root small, because a class
holds only the later items, and the later items are the frequent ones.
"""
function frequent_items_by_support(database::Vector{Vector{Int}}, minsup::Int)
    frequent = [item => support for (item, support) in count_items(database) if support >= minsup]
    return sort!(frequent; by=p -> (last(p), first(p)))
end

"""The root class: every frequent item with its bitset, in `frequent_items_by_support` order."""
function bitset_class(database::Vector{Vector{Int}}, minsup::Int)
    frequent = frequent_items_by_support(database, minsup)
    sets = bitset_tidsets(database, first.(frequent))
    return [BitsetMember(item, support, words) for ((item, support), words) in zip(frequent, sets)]
end

"""
    push_subsets!(result, prefix, perfect, support) -> result

Append `prefix ∪ S` with `support` for every subset `S` of `perfect`, starting
with `prefix` alone. `prefix` is ascending and disjoint from `perfect`. Gray-code
order changes one item per step, so each itemset costs one sorted insert or
delete, not a rebuild. Both vectors are restored. Throws `OverflowError` for more
than 62 perfect items, whose 2^63 subsets no result can hold.
"""
function push_subsets!(result::FrequentItemsets, prefix::Vector{Int}, perfect::Vector{Int}, support::Int)
    count = length(perfect)
    count <= 62 || throw(OverflowError("$count perfect extensions give 2^$count itemsets"))
    push_itemset!(result, prefix, support)
    for step in 1:(1 << count) - 1
        item = perfect[trailing_zeros(step) + 1]
        position = searchsortedfirst(prefix, item)
        if position <= length(prefix) && prefix[position] == item
            deleteat!(prefix, position)
        else
            insert!(prefix, position, item)
        end
        push_itemset!(result, prefix, support)
    end
    # Gray code 2^count - 1 holds only the last perfect item.
    count == 0 || deleteat!(prefix, searchsortedfirst(prefix, perfect[count]))
    return result
end

"""
    join_members!(children, perfect, class, i, minsup, pool, pairs=NoPairCounts()) -> Int

Join member `i` of `class` with every later member whose pair count in `pairs`
reaches `minsup`; the other joins cannot be frequent and are skipped. A join with the same support
as member `i` has the same tidset, so its item goes onto `perfect` and its set
back to `pool`; a frequent join with lower support becomes a child; the rest go
back to `pool`. Returns the number of items pushed onto `perfect`.
"""
function join_members!(children::Vector{BitsetMember}, perfect::Vector{Int}, class::Vector{BitsetMember},
                       i::Int, minsup::Int, pool::Vector{Vector{UInt64}}, pairs=NoPairCounts())
    a = class[i]
    added = 0
    for j in i+1:lastindex(class)
        may_be_frequent(pairs, i, j, minsup) || continue
        b = class[j]
        words = isempty(pool) ? similar(a.words) : pop!(pool)
        # t(PXY) = t(PX) ∩ t(PY), so the support needs no database scan.
        support = intersect_bitsets!(words, a.words, b.words)
        if support == a.support
            push!(perfect, b.item)
            push!(pool, words)
            added += 1
        elseif support >= minsup
            push!(children, BitsetMember(b.item, support, words))
        else
            push!(pool, words)
        end
    end
    return added
end

"""
    bitset_search!(class, prefix, perfect, minsup, result, pool, pairs=NoPairCounts()) -> result

Bottom-Up search of one class (Zaki 2000, Sec. 4.2) over bitset tidsets, in the
class's item order, with perfect-extension pruning (`docs/eclat-optimized.md`).
`prefix` holds the prefix items in ascending order, so every emitted itemset is
ascending without a sort. `perfect` holds the perfect extensions found on the
path, which every itemset below may add without changing its support. Each call
restores both. `pool` holds spare bitsets: a join writes into one, a child keeps
it, and a child class returns its sets once its search ends, so a failed join
allocates nothing. `pairs` holds pair counts over the ranks of `class` and
applies to this class only.
"""
function bitset_search!(class::Vector{BitsetMember}, prefix::Vector{Int}, perfect::Vector{Int}, minsup::Int,
                        result::FrequentItemsets, pool::Vector{Vector{UInt64}}, pairs=NoPairCounts())
    for i in eachindex(class)
        a = class[i]
        position = searchsortedfirst(prefix, a.item)
        insert!(prefix, position, a.item)
        children = BitsetMember[]
        added = join_members!(children, perfect, class, i, minsup, pool, pairs)
        push_subsets!(result, prefix, perfect, a.support)
        if !isempty(children)
            bitset_search!(children, prefix, perfect, minsup, result, pool)
            # No class on the search path refers to these sets after their search ends.
            foreach(child -> push!(pool, child.words), children)
        end
        resize!(perfect, length(perfect) - added)
        deleteat!(prefix, position)
    end
    return result
end

"""
    mine_bitsets(database, minsup; use_pair_counts=nothing) -> FrequentItemsets

Mine a canonical database with bitset tidsets; see `mine_packed`. With
`use_pair_counts=nothing`, `pair_filter` decides from the database whether to count
root pairs first; `true` or `false` forces the choice, for tests.
"""
function mine_bitsets(database::Vector{Vector{Int}}, minsup::Int; use_pair_counts::Union{Nothing,Bool}=nothing)
    class = bitset_class(database, minsup)
    items = [member.item for member in class]
    pairs = use_pair_counts === nothing ? pair_filter(database, items) :
            use_pair_counts ? count_pairs(database, items) : NoPairCounts()
    return bitset_search!(class, Int[], Int[], minsup, FrequentItemsets(), Vector{UInt64}[], pairs)
end
