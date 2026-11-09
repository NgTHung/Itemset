"""
    SearchNodes()

The nodes an optimized search emits, back to back like `FrequentItemsets`: node
`k` has the ascending core itemset `cores[core_offsets[k]:core_offsets[k+1]-1]`,
the perfect extensions `perfect[perfect_offsets[k]:perfect_offsets[k+1]-1]`, and
the support every itemset of the node shares (`docs/eclat-optimized.md`). A node
stands for 2^|E| itemsets, so `expand_nodes` knows the result's final size
before it writes one, and the result never grows.
"""
struct SearchNodes
    cores::Vector{Int}
    core_offsets::Vector{Int}
    perfect::Vector{Int}
    perfect_offsets::Vector{Int}
    supports::Vector{Int}
end

SearchNodes() = SearchNodes(Int[], [1], Int[], [1], Int[])

"""
Record the node of core itemset `core`, perfect extensions `perfect`, and
`support`, copying both vectors. Throws `OverflowError` for more than 62
perfect items, whose 2^63 subsets no result can hold.
"""
function push_node!(nodes::SearchNodes, core::Vector{Int}, perfect::Vector{Int}, support::Int)
    count = length(perfect)
    count <= 62 || throw(OverflowError("$count perfect extensions give 2^$count itemsets"))
    append!(nodes.cores, core)
    push!(nodes.core_offsets, length(nodes.cores) + 1)
    append!(nodes.perfect, perfect)
    push!(nodes.perfect_offsets, length(nodes.perfect) + 1)
    push!(nodes.supports, support)
    return nodes
end

"""
    expand_nodes(nodes) -> FrequentItemsets

Every itemset of every node, `core ∪ S` for each subset `S` of the node's
perfect extensions, in node order. The arrays are allocated once at their final
size. Throws `OverflowError` when the itemset or item count exceeds `typemax(Int)`.
"""
function expand_nodes(nodes::SearchNodes)
    count, total = 0, 0
    for k in eachindex(nodes.supports)
        core_length = nodes.core_offsets[k+1] - nodes.core_offsets[k]
        perfect_count = nodes.perfect_offsets[k+1] - nodes.perfect_offsets[k]
        subsets = 1 << perfect_count
        count = Base.checked_add(count, subsets)
        # Each perfect item lies in half of the subsets.
        node_items = Base.checked_add(Base.checked_mul(subsets, core_length), (subsets >> 1) * perfect_count)
        total = Base.checked_add(total, node_items)
    end
    items = Vector{Int}(undef, total)
    offsets = Vector{Int}(undef, Base.checked_add(count, 1))
    supports = Vector{Int}(undef, count)
    offsets[1] = 1
    itemset = Int[]
    next = 1
    for k in eachindex(nodes.supports)
        append!(empty!(itemset), view(nodes.cores, nodes.core_offsets[k]:nodes.core_offsets[k+1]-1))
        perfect = view(nodes.perfect, nodes.perfect_offsets[k]:nodes.perfect_offsets[k+1]-1)
        next = write_subsets!(items, offsets, supports, next, itemset, perfect, nodes.supports[k])
    end
    return FrequentItemsets(items, offsets, supports)
end

"""
Write `itemset ∪ S` with `support` for every subset `S` of `perfect`, starting
with `itemset` alone, as result entries `next` onward; return the next free entry.
Gray-code order changes one item per step, so each itemset costs one sorted
insert or delete, not a rebuild. `itemset` ends holding the last perfect item.
"""
function write_subsets!(items::Vector{Int}, offsets::Vector{Int}, supports::Vector{Int}, next::Int,
                        itemset::Vector{Int}, perfect::AbstractVector{Int}, support::Int)
    next = write_itemset!(items, offsets, supports, next, itemset, support)
    for step in 1:(1 << length(perfect)) - 1
        item = perfect[trailing_zeros(step) + 1]
        position = searchsortedfirst(itemset, item)
        if position <= length(itemset) && itemset[position] == item
            deleteat!(itemset, position)
        else
            insert!(itemset, position, item)
        end
        next = write_itemset!(items, offsets, supports, next, itemset, support)
    end
    return next
end

function write_itemset!(items::Vector{Int}, offsets::Vector{Int}, supports::Vector{Int}, next::Int,
                        itemset::Vector{Int}, support::Int)
    start = offsets[next]
    copyto!(items, start, itemset, 1, length(itemset))
    offsets[next+1] = start + length(itemset)
    supports[next] = support
    return next + 1
end
