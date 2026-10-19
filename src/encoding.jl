"""
    encode_transactions(rows) -> (transactions::Vector{Vector{Int}}, labels::Vector)

Map label rows, such as the product names on each receipt, to integer-ID
transactions. `labels` holds the distinct labels in sorted order, and
`labels[id]` is the label of ID `id`, so the mapping depends only on the label
set, never on row order. Repeated labels in a row collapse and empty rows stay
as `Int[]`.

Throws `ArgumentError` naming the row for a `missing` or `nothing` label, so an
uncleaned value never becomes an item.
"""
function encode_transactions(rows)
    for (index, row) in enumerate(rows), label in row
        (label === missing || label === nothing) &&
            throw(ArgumentError("row $index: label $(repr(label)) is not an item; clean it before encoding"))
    end
    labels = sort!(unique(eltype(eltype(rows))[label for row in rows for label in row]))
    ids = Dict(label => id for (id, label) in enumerate(labels))
    transactions = [canonical_transaction([ids[label] for label in row]) for row in rows]
    return transactions, labels
end

"""
    decode_itemset(labels, itemset) -> Vector

Return the labels of `itemset`'s IDs, in itemset order. Throws `ArgumentError`
for an ID outside `1:length(labels)`, which means the itemset and the labels
come from different encodings.
"""
function decode_itemset(labels::AbstractVector, itemset)
    for id in itemset
        checkbounds(Bool, labels, id) ||
            throw(ArgumentError("item ID $id has no label; labels cover 1:$(length(labels))"))
    end
    return [labels[id] for id in itemset]
end
