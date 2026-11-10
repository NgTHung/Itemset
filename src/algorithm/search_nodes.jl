"""
    SearchNodes()

The nodes an optimized search emits, in preorder. Node `k` adds `items[k]` to
the core of the last earlier node at depth `depths[k] - 1`, adds the perfect
extensions `perfect[perfect_offsets[k]:perfect_offsets[k+1]-1]` to that node's,
and has `supports[k]`, the support every itemset of the node shares
(`docs/eclat-optimized.md`). A record stores only what the node adds, so it
costs the same at every depth. A node stands for 2^|E| itemsets, so
`expand_nodes` knows the result's final size before it writes one.
"""
struct SearchNodes
    depths::Vector{Int}
    items::Vector{Int}
    supports::Vector{Int}
    perfect::Vector{Int}
    perfect_offsets::Vector{Int}
end

SearchNodes() = SearchNodes(Int[], Int[], Int[], Int[], [1])

"""
Record a node at `depth` whose core adds `item` and whose perfect extensions
add `perfect`, with `support`. The caller records nodes in preorder, so a node
at depth `d > 1` follows the node at depth `d - 1` it extends.
"""
function push_node!(nodes::SearchNodes, depth::Int, item::Int, perfect::AbstractVector{Int}, support::Int)
    push!(nodes.depths, depth)
    push!(nodes.items, item)
    push!(nodes.supports, support)
    append!(nodes.perfect, perfect)
    push!(nodes.perfect_offsets, length(nodes.perfect) + 1)
    return nodes
end

added_perfect(nodes::SearchNodes, k::Int) = view(nodes.perfect, nodes.perfect_offsets[k]:nodes.perfect_offsets[k+1]-1)

"""
The depth of node `k` when the current path has `path_length` nodes. A depth
more than one below the path would extend a node that was never recorded, so it
throws `ArgumentError` instead of expanding a wrong core.
"""
function checked_depth(nodes::SearchNodes, k::Int, path_length::Int)
    depth = nodes.depths[k]
    1 <= depth <= path_length + 1 ||
        throw(ArgumentError("node $k has depth $depth below a path of $path_length nodes"))
    return depth
end

"""
    expand_nodes(nodes) -> FrequentItemsets

Every itemset of every node, `core ∪ S` for each subset `S` of the node's
perfect extensions, in node order. The arrays are allocated once at their final
size. Throws `OverflowError` for a node with more than 62 perfect extensions,
or when the itemset or item count exceeds `typemax(Int)`, and `ArgumentError`
when a node's depth skips a level.
"""
function expand_nodes(nodes::SearchNodes)
    # perfect_counts[d] is the number of perfect extensions of the path's node at depth d.
    perfect_counts = Int[]
    count, total = 0, 0
    for k in eachindex(nodes.supports)
        depth = checked_depth(nodes, k, length(perfect_counts))
        inherited = depth == 1 ? 0 : perfect_counts[depth-1]
        perfect_count = inherited + length(added_perfect(nodes, k))
        perfect_count <= 62 ||
            throw(OverflowError("$perfect_count perfect extensions give 2^$perfect_count itemsets"))
        push!(resize!(perfect_counts, depth - 1), perfect_count)
        subsets = 1 << perfect_count
        count = Base.checked_add(count, subsets)
        # Each perfect item lies in half of the subsets.
        node_items = Base.checked_add(Base.checked_mul(subsets, depth), (subsets >> 1) * perfect_count)
        total = Base.checked_add(total, node_items)
    end
    items = Vector{Int}(undef, total)
    offsets = Vector{Int}(undef, Base.checked_add(count, 1))
    supports = Vector{Int}(undef, count)
    offsets[1] = 1
    write_nodes!(items, offsets, supports, nodes)
    return FrequentItemsets(items, offsets, supports)
end

"""
Write the itemsets of every node into result arrays sized by `expand_nodes`.
`path` holds the core items in the order the nodes added them, `core` the same
items ascending, and `perfect` the path's perfect extensions in order, so each
node costs one sorted insert and the deletes of the nodes it leaves.
"""
function write_nodes!(items::Vector{Int}, offsets::Vector{Int}, supports::Vector{Int}, nodes::SearchNodes)
    path, core, perfect, itemset = Int[], Int[], Int[], Int[]
    # perfect_lengths[d] is length(perfect) once the path's node at depth d is applied.
    perfect_lengths = Int[]
    next = 1
    for k in eachindex(nodes.supports)
        depth = nodes.depths[k]
        while length(path) >= depth
            left = pop!(path)
            deleteat!(core, searchsortedfirst(core, left))
        end
        resize!(perfect_lengths, depth - 1)
        resize!(perfect, depth == 1 ? 0 : perfect_lengths[depth-1])
        item = nodes.items[k]
        push!(path, item)
        insert!(core, searchsortedfirst(core, item), item)
        append!(perfect, added_perfect(nodes, k))
        push!(perfect_lengths, length(perfect))
        append!(empty!(itemset), core)
        next = write_subsets!(items, offsets, supports, next, itemset, perfect, nodes.supports[k])
    end
    return next
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
