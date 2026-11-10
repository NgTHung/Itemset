"""
    item_frequencies(transactions) -> Dict{Int,Int}

Count each item once per transaction, including duplicate transactions separately.
Canonicalizes item IDs and throws `ArgumentError` for invalid transactions or IDs.
"""
item_frequencies(transactions) = count_items(canonical_database(transactions))

"""Count each item of a canonical database, whose transactions hold each item once."""
function count_items(database::Vector{Vector{Int}})
    counts = Dict{Int,Int}()
    for transaction in database
        for item in transaction
            counts[item] = get(counts, item, 0) + 1
        end
    end
    return counts
end

"""
    write_transactions(io_or_path, transactions; labels=nothing)

Write SPMF transaction text, one canonical transaction per line. With `labels`,
first write SPMF's `@CONVERTED_FROM_TEXT` and `@ITEM=id=label` lines, which
`read_transactions` skips, so the file also carries its mapping.

Validates everything before opening the output, so invalid input never touches
an existing file. Throws `ArgumentError` naming the transaction for an invalid
or empty transaction, because a blank line reads back as no transaction and
would change N. Also throws for an ID without a label and for a label
containing a line break.
"""
function write_transactions(io::IO, transactions; labels=nothing)
    database = checked_spmf_database(transactions, labels)
    print_transactions(io, database, labels)
end

function write_transactions(path::AbstractString, transactions; labels=nothing)
    database = checked_spmf_database(transactions, labels)
    open(io -> print_transactions(io, database, labels), path, "w")
end

function checked_spmf_database(transactions, labels)
    database = canonical_database(transactions)
    for (index, transaction) in enumerate(database)
        isempty(transaction) &&
            throw(ArgumentError("transaction $index is empty; SPMF text cannot encode it"))
        labels === nothing && continue
        for id in transaction
            checkbounds(Bool, labels, id) ||
                throw(ArgumentError("transaction $index: item ID $id has no label"))
        end
    end
    if labels !== nothing
        for label in labels
            occursin(r"[\r\n]", string(label)) &&
                throw(ArgumentError("label $(repr(label)) contains a line break"))
        end
    end
    return database
end

function print_transactions(io::IO, database, labels)
    if labels !== nothing
        println(io, "@CONVERTED_FROM_TEXT")
        for (id, label) in pairs(labels)
            println(io, "@ITEM=", id, '=', label)
        end
    end
    print_transaction_lines(io, database)
end

"""
Write deterministic canonical SPMF output. Validate before opening the output,
so an invalid map never touches an existing file.
"""
write_itemsets(io::IO, patterns::AbstractDict) = write_itemsets(io, checked_packed(patterns))

write_itemsets(path::AbstractString, patterns::AbstractDict) = write_itemsets(path, checked_packed(patterns))

"""
Validate every key and support, then pack them in iteration order, so the map
shares the packed writer and its sort. Throws `ArgumentError` naming the first
invalid key or support.
"""
function checked_packed(patterns::AbstractDict)
    for (items, support) in patterns
        is_canonical_key(items) ||
            throw(ArgumentError("itemset keys must be nonempty canonical tuples, got $(repr(items))"))
        support isa Integer && !(support isa Bool) && 1 <= support <= typemax(Int) ||
            throw(ArgumentError("supports must be positive integers, got $(repr(support)) for $(repr(items))"))
    end
    packed = FrequentItemsets()
    sizehint!(packed.offsets, length(patterns) + 1)
    sizehint!(packed.supports, length(patterns))
    for (items, support) in patterns
        push_itemset!(packed, items, support)
    end
    return packed
end

"""True for a nonempty tuple of strictly ascending item IDs, which is what `canonical_transaction` returns as a tuple."""
is_canonical_key(items) =
    items isa Tuple && !isempty(items) && all(is_item_id, items) && all(i -> items[i] < items[i+1], 1:length(items)-1)
