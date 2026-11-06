"""
One member of a prefix-based equivalence class: the last item of `prefix ∪ {item}`,
that itemset's support, and its tidset, either a bitset of `UInt64` words or an
ascending list of `Int` tids.
"""
struct ClassMember{T<:Union{UInt64,Int}}
    item::Int
    support::Int
    tidset::Vector{T}
end

const BitsetMember = ClassMember{UInt64}
const ListMember = ClassMember{Int}

# Children switch to tid lists when their mean support is below this fraction of ⌈N/64⌉.
const LIST_RATIO = 1 / 6

"""
Spare tidsets of each kind, reused across joins, and the ratio that moves a
class from bitsets to tid lists. One state serves the whole search.
"""
struct SearchState
    bitsets::Vector{Vector{UInt64}}
    lists::Vector{Vector{Int}}
    list_ratio::Float64
end

SearchState(list_ratio::Real=LIST_RATIO) = SearchState(Vector{UInt64}[], Vector{Int}[], Float64(list_ratio))

spare_sets(state::SearchState, ::Type{UInt64}) = state.bitsets
spare_sets(state::SearchState, ::Type{Int}) = state.lists

join_tidsets!(dest::Vector{UInt64}, a::Vector{UInt64}, b::Vector{UInt64}, minsup::Int) = intersect_bitsets!(dest, a, b)
join_tidsets!(dest::Vector{Int}, a::Vector{Int}, b::Vector{Int}, minsup::Int) = intersect_lists!(dest, a, b, minsup)

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
function join_members!(children::Vector{ClassMember{T}}, perfect::Vector{Int}, class::Vector{ClassMember{T}},
                       i::Int, minsup::Int, pool::Vector{Vector{T}}, pairs=NoPairCounts()) where {T}
    a = class[i]
    added = 0
    for j in i+1:lastindex(class)
        may_be_frequent(pairs, i, j, minsup) || continue
        b = class[j]
        tidset = isempty(pool) ? similar(a.tidset) : pop!(pool)
        # t(PXY) = t(PX) ∩ t(PY), so the support needs no database scan.
        support = join_tidsets!(tidset, a.tidset, b.tidset, minsup)
        if support == a.support
            push!(perfect, b.item)
            push!(pool, tidset)
            added += 1
        elseif support >= minsup
            push!(children, ClassMember{T}(b.item, support, tidset))
        else
            push!(pool, tidset)
        end
    end
    return added
end

"""
    eclat_search!(class, prefix, perfect, minsup, result, state, pairs=NoPairCounts()) -> result

Bottom-Up search of one class (Zaki 2000, Sec. 4.2), in the class's item order,
with perfect-extension pruning (`docs/eclat-optimized.md`). `prefix` holds the
prefix items in ascending order, so every emitted itemset is ascending without a
sort. `perfect` holds the perfect extensions found on the path, which every
itemset below may add without changing its support. Each call restores both. A
join writes into a spare tidset from `state`, a child keeps it, and a child class
returns its sets once its search ends, so a failed join allocates nothing.
`pairs` holds pair counts over the ranks of `class` and applies to this class only.
"""
function eclat_search!(class::Vector{ClassMember{T}}, prefix::Vector{Int}, perfect::Vector{Int}, minsup::Int,
                       result::FrequentItemsets, state::SearchState, pairs=NoPairCounts()) where {T}
    pool = spare_sets(state, T)
    for i in eachindex(class)
        a = class[i]
        position = searchsortedfirst(prefix, a.item)
        insert!(prefix, position, a.item)
        children = ClassMember{T}[]
        added = join_members!(children, perfect, class, i, minsup, pool, pairs)
        push_subsets!(result, prefix, perfect, a.support)
        isempty(children) || search_children!(children, prefix, perfect, minsup, result, state)
        resize!(perfect, length(perfect) - added)
        deleteat!(prefix, position)
    end
    return result
end

"""
Search a child class, then return its tidsets to the spare sets, since no class
on the search path refers to them after their search ends. Bitset children move
to tid lists first when `prefer_lists` says lists cost less.
"""
function search_children!(children::Vector{ClassMember{T}}, prefix::Vector{Int}, perfect::Vector{Int},
                          minsup::Int, result::FrequentItemsets, state::SearchState) where {T}
    if prefer_lists(children, state.list_ratio)
        lists = [ListMember(c.item, c.support, bitset_tids!(spare_list(state), c.tidset)) for c in children]
        foreach(c -> push!(state.bitsets, c.tidset), children)
        return search_children!(lists, prefix, perfect, minsup, result, state)
    end
    eclat_search!(children, prefix, perfect, minsup, result, state)
    foreach(c -> push!(spare_sets(state, T), c.tidset), children)
    return result
end

spare_list(state::SearchState) = isempty(state.lists) ? Int[] : pop!(state.lists)

"""
Whether a class of bitset members costs less as tid lists. A bitset join reads
⌈N/64⌉ words whatever the supports, while a list join reads both lists and stops
early once the threshold is out of reach, so lists win for short tidsets.
"""
prefer_lists(children::Vector{BitsetMember}, ratio::Float64) =
    sum(c -> c.support, children) < ratio * length(children) * length(first(children).tidset)
prefer_lists(::Vector{ListMember}, ::Float64) = false

"""
    mine_optimized(database, minsup; use_pair_counts=nothing, list_ratio=LIST_RATIO) -> FrequentItemsets

Mine a canonical database with the optimized variant; see `mine_packed`. The
root class holds bitsets, and a child class moves to tid lists when its mean
support is below `list_ratio` times ⌈N/64⌉. With `use_pair_counts=nothing`,
`pair_filter` decides from the database whether to count root pairs first.
`true` or `false` forces that choice, and a `list_ratio` of 0 or `Inf` forces
bitsets or lists below the root, for tests and sweeps.
"""
function mine_optimized(database::Vector{Vector{Int}}, minsup::Int;
                        use_pair_counts::Union{Nothing,Bool}=nothing, list_ratio::Real=LIST_RATIO)
    class = bitset_class(database, minsup)
    items = [member.item for member in class]
    pairs = use_pair_counts === nothing ? pair_filter(database, items) :
            use_pair_counts ? count_pairs(database, items) : NoPairCounts()
    return eclat_search!(class, Int[], Int[], minsup, FrequentItemsets(), SearchState(list_ratio), pairs)
end
