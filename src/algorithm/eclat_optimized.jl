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

# One tid-list merge step costs about this many bitset-join words. A BBQ sweep of 2 to 16 found 8
# fastest on T10I4D100K 0.00025 (1.20 s to 0.90 s) with Retail and T10I4D100K 0.001 unchanged; see
# docs/eclat-optimized.md.
const LIST_STEP_COST = 8.0

"""
Spare tidsets of each kind, reused across joins, and the rule that moves a class
from bitsets to tid lists: `:cost` compares the two with `prefer_lists`, and
`:always` or `:never` force the choice. One state serves the whole search.
Throws `ArgumentError` for any other rule.
"""
struct SearchState
    bitsets::Vector{Vector{UInt64}}
    lists::Vector{Vector{Int}}
    list_rule::Symbol
    list_step_cost::Float64

    function SearchState(list_rule::Symbol=:cost, list_step_cost::Real=LIST_STEP_COST)
        list_rule in (:cost, :always, :never) ||
            throw(ArgumentError("list_rule must be :cost, :always, or :never, got $(repr(list_rule))"))
        return new(Vector{UInt64}[], Vector{Int}[], list_rule, Float64(list_step_cost))
    end
end

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
    if prefer_lists(children, state)
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
Whether a class of `k` bitset members costs less as tid lists, counting the
joins of this class only. As bitsets, its `k(k - 1)/2` joins read `W = ⌈N/64⌉`
words each. As lists, each member first costs one `W`-word scan to convert, and
the joins then merge `(k - 1)` times the sum of the supports, at
`list_step_cost` words per step. A class with few members cannot repay the
conversion, and long tidsets make each merge dearer than a bitset join.
"""
function prefer_lists(children::Vector{BitsetMember}, state::SearchState)
    state.list_rule === :cost || return state.list_rule === :always
    k, words = length(children), length(first(children).tidset)
    list_cost = k * words + state.list_step_cost * (k - 1) * sum(c -> c.support, children)
    return list_cost < words * k * (k - 1) / 2
end
prefer_lists(::Vector{ListMember}, ::SearchState) = false

"""
    mine_optimized(database, minsup; use_pair_counts=nothing, list_rule=:cost,
                   list_step_cost=LIST_STEP_COST) -> FrequentItemsets

Mine a canonical database with the optimized variant; see `mine_packed`. The
root class holds bitsets, and a child class moves to tid lists when
`prefer_lists` finds them cheaper. With `use_pair_counts=nothing`, `pair_filter`
decides from the database whether to count root pairs first. The keywords force
these choices or change the list cost, for tests and sweeps.
"""
function mine_optimized(database::Vector{Vector{Int}}, minsup::Int;
                        use_pair_counts::Union{Nothing,Bool}=nothing, list_rule::Symbol=:cost,
                        list_step_cost::Real=LIST_STEP_COST)
    class = bitset_class(database, minsup)
    items = [member.item for member in class]
    pairs = use_pair_counts === nothing ? pair_filter(database, items) :
            use_pair_counts ? count_pairs(database, items) : NoPairCounts()
    return eclat_search!(class, Int[], Int[], minsup, FrequentItemsets(), SearchState(list_rule, list_step_cost), pairs)
end
