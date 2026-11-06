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
    bitset_search!(class, prefix, minsup, result, pool) -> result

Bottom-Up search of one class (Zaki 2000, Sec. 4.2) over bitset tidsets, in the
class's item order. `prefix` holds the prefix items in ascending order, so every
emitted itemset is ascending without a sort; each call restores it. `pool` holds
spare bitsets: a join writes into one, a frequent join keeps it, and a child
class returns its sets once its search ends, so a failed join allocates nothing.
"""
function bitset_search!(class::Vector{BitsetMember}, prefix::Vector{Int}, minsup::Int,
                        result::FrequentItemsets, pool::Vector{Vector{UInt64}})
    for i in eachindex(class)
        a = class[i]
        position = searchsortedfirst(prefix, a.item)
        insert!(prefix, position, a.item)
        push_itemset!(result, prefix, a.support)
        children = BitsetMember[]
        for j in i+1:lastindex(class)
            b = class[j]
            words = isempty(pool) ? similar(a.words) : pop!(pool)
            # t(PXY) = t(PX) ∩ t(PY), so the support needs no database scan.
            support = intersect_bitsets!(words, a.words, b.words)
            support >= minsup ? push!(children, BitsetMember(b.item, support, words)) : push!(pool, words)
        end
        if !isempty(children)
            bitset_search!(children, prefix, minsup, result, pool)
            # No class on the search path refers to these sets after their search ends.
            foreach(child -> push!(pool, child.words), children)
        end
        deleteat!(prefix, position)
    end
    return result
end

"""Mine a canonical database with bitset tidsets; see `mine_packed`."""
mine_bitsets(database::Vector{Vector{Int}}, minsup::Int) =
    bitset_search!(bitset_class(database, minsup), Int[], minsup, FrequentItemsets(), Vector{UInt64}[])
