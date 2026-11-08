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
reaches `minsup`; the other joins cannot be frequent and are skipped. Children
take the tidset form of the element type of `children`, which may differ from
the class's at a switch. A join with the same support as member `i` has the
same tidset, so its item goes onto `perfect` and its set back to `pool`; a
frequent join with lower support becomes a child; the rest go back to `pool`.
Returns the number of items pushed onto `perfect`.
"""
function join_members!(children::Vector{C}, perfect::Vector{Int}, class::Vector{<:ClassMember},
                       i::Int, minsup::Int, pool::Vector{Vector{T}}, pairs=NoPairCounts()) where {T,C<:ClassMember{<:Any,T}}
    a = class[i]
    added = 0
    for j in i+1:lastindex(class)
        may_be_frequent(pairs, i, j, minsup) || continue
        b = class[j]
        tidset = isempty(pool) ? new_tidset(C, a) : pop!(pool)
        # t(PXY) = t(PX) ∩ t(PY), so the support needs no database scan.
        support = join_tidsets!(tidset, a, b, minsup, C)
        if support == a.support
            push!(perfect, b.item)
            push!(pool, tidset)
            added += 1
        elseif support >= minsup
            push!(children, C(b.item, support, tidset))
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
returns its sets once its search ends, so a failed join allocates nothing. The
children of a bitset member take diffsets when `prefer_diffsets` says so.
`pairs` holds pair counts over the ranks of `class` and applies to this class only.
"""
function eclat_search!(class::Vector{M}, prefix::Vector{Int}, perfect::Vector{Int}, minsup::Int,
                       result::FrequentItemsets, state::SearchState, pairs=NoPairCounts()) where {M<:ClassMember}
    for i in eachindex(class)
        a = class[i]
        position = searchsortedfirst(prefix, a.item)
        insert!(prefix, position, a.item)
        added = prefer_diffsets(a, minsup, state) ?
            extend_member!(DiffMember, class, i, prefix, perfect, minsup, result, state, pairs) :
            extend_member!(M, class, i, prefix, perfect, minsup, result, state, pairs)
        resize!(perfect, length(perfect) - added)
        deleteat!(prefix, position)
    end
    return result
end

"""
Join member `i` of `class` with the later members, emit it with every subset of
the perfect stack, then search its children, whose tidsets take the form of
member type `C`. `eclat_search!` passes `C` as a type, so each call compiles
with a concrete child vector. Returns the number of perfect items it added.
"""
function extend_member!(::Type{C}, class::Vector{<:ClassMember}, i::Int, prefix::Vector{Int}, perfect::Vector{Int},
                        minsup::Int, result::FrequentItemsets, state::SearchState, pairs) where {C<:ClassMember}
    children = C[]
    added = join_members!(children, perfect, class, i, minsup, spare_sets(state, tidset_eltype(C)), pairs)
    push_subsets!(result, prefix, perfect, class[i].support)
    isempty(children) || search_children!(children, prefix, perfect, minsup, result, state)
    return added
end

"""
Search a child class, then return its tidsets to the spare sets, since no class
on the search path refers to them after their search ends. Bitset children move
to tid lists first when `prefer_lists` says lists cost less.
"""
function search_children!(children::Vector{C}, prefix::Vector{Int}, perfect::Vector{Int},
                          minsup::Int, result::FrequentItemsets, state::SearchState) where {C<:ClassMember}
    if prefer_lists(children, state)
        lists = [ListMember(c.item, c.support, bitset_tids!(spare_list(state), c.tidset)) for c in children]
        foreach(c -> push!(state.bitsets, c.tidset), children)
        return search_children!(lists, prefix, perfect, minsup, result, state)
    end
    eclat_search!(children, prefix, perfect, minsup, result, state)
    foreach(c -> push!(spare_sets(state, tidset_eltype(C)), c.tidset), children)
    return result
end

"""
    mine_optimized(database, minsup; use_pair_counts=nothing, list_rule=:cost,
                   list_step_cost=LIST_STEP_COST, diff_rule=:cost, diff_ratio=DIFF_RATIO) -> FrequentItemsets

Mine a canonical database with the optimized variant; see `mine_packed`. The
root class holds bitsets. A child class moves to tid lists when `prefer_lists`
finds them cheaper, and to diffsets when `prefer_diffsets` does. With
`use_pair_counts=nothing`, `pair_filter` decides from the database whether to
count root pairs first. The keywords force these choices or change their costs,
for tests and sweeps.
"""
function mine_optimized(database::Vector{Vector{Int}}, minsup::Int;
                        use_pair_counts::Union{Nothing,Bool}=nothing, list_rule::Symbol=:cost,
                        list_step_cost::Real=LIST_STEP_COST, diff_rule::Symbol=:cost, diff_ratio::Real=DIFF_RATIO)
    class = bitset_class(database, minsup)
    items = [member.item for member in class]
    pairs = use_pair_counts === nothing ? pair_filter(database, items) :
            use_pair_counts ? count_pairs(database, items) : NoPairCounts()
    return eclat_search!(class, Int[], Int[], minsup, FrequentItemsets(), SearchState(list_rule, list_step_cost, diff_rule, diff_ratio), pairs)
end
