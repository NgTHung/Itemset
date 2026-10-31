"""
Read SPMF transaction text. Skip blank lines and #, %, @ comment/metadata lines.
Item 0 is valid. Negative IDs (including sequence delimiters) are rejected.
Duplicates within a transaction collapse; duplicate transactions remain distinct.
For intentionally empty transactions, use the in-memory API instead of blank lines.
"""
function read_transactions(io::IO)
    transactions = Vector{Vector{Int}}()
    for (line_number, line) in enumerate(eachline(io))
        value = strip(line)
        is_spmf_metadata(value) && continue
        push!(transactions, canonical_transaction(parse_item_ids(value, line_number)))
    end
    return transactions
end

read_transactions(path::AbstractString) = open(read_transactions, path)

is_spmf_metadata(line::AbstractString) = isempty(line) || startswith(line, ('#', '%', '@'))

function parse_item_ids(text::AbstractString, line_number::Integer)
    items = Int[]
    for token in split(text)
        item = tryparse(Int, token)
        (item === nothing || item < 0) &&
            throw(ArgumentError("line $line_number: invalid item ID $(repr(token))"))
        push!(items, item)
    end
    return items
end

const ItemsetRecord = @NamedTuple{itemset::Itemset, support::Int, line::Int}

"""
    read_itemset_records(io_or_path) -> Vector{@NamedTuple{itemset, support, line}}

Read SPMF frequent-itemset output, such as `write_itemsets` or SPMF writes, as
one record per itemset line in file order. Each itemset is canonical, and
`line` is its 1-based line number. Repeated itemsets stay as separate records,
so a comparison can report them instead of losing one support.

Skips the same metadata lines as `read_transactions`, except a line holding
`#SUP:`, because `#SUP: 1` is an empty itemset, not a comment. Throws
`ArgumentError` with the line number for a line without `#SUP:`, an invalid or
repeated item ID, an empty itemset, or a support below 1.
"""
function read_itemset_records(io::IO)
    records = ItemsetRecord[]
    for (line_number, line) in enumerate(eachline(io))
        value = strip(line)
        is_spmf_metadata(value) && !occursin("#SUP:", value) && continue
        parts = match(r"^(.*?)\s*#SUP:\s*(\S*)$", value)
        parts === nothing &&
            throw(ArgumentError("line $line_number: expected 'items #SUP: count', got $(repr(value))"))
        items = parse_item_ids(parts[1], line_number)
        isempty(items) && throw(ArgumentError("line $line_number: empty itemset"))
        allunique(items) || throw(ArgumentError("line $line_number: repeated item ID in $(repr(value))"))
        support = tryparse(Int, parts[2])
        (support === nothing || support < 1) &&
            throw(ArgumentError("line $line_number: invalid support $(repr(parts[2]))"))
        push!(records, (itemset=Tuple(sort!(items)), support=support, line=line_number))
    end
    return records
end

read_itemset_records(path::AbstractString) = open(read_itemset_records, path)

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
    for transaction in database
        println(io, join(transaction, ' '))
    end
    return nothing
end

"""
Write deterministic canonical SPMF output. Validate before opening the output,
so an invalid map never touches an existing file.
"""
function write_itemsets(io::IO, patterns::AbstractDict)
    check_itemsets(patterns)
    packed = sorted_packed(patterns)
    print_packed(io, packed, collect(1:length(packed)))
end

function write_itemsets(path::AbstractString, patterns::AbstractDict)
    check_itemsets(patterns)
    packed = sorted_packed(patterns)
    open(io -> print_packed(io, packed, collect(1:length(packed))), path, "w")
end

function check_itemsets(patterns::AbstractDict)
    for (items, support) in patterns
        !isempty(items) && Tuple(canonical_transaction(items)) == items ||
            throw(ArgumentError("itemset keys must be nonempty canonical tuples"))
        support isa Integer && !(support isa Bool) && support >= 1 ||
            throw(ArgumentError("supports must be positive integers"))
    end
    return nothing
end

"""Pack validated, canonical keys in write order, so both result forms share one writer."""
function sorted_packed(patterns::AbstractDict)
    packed = FrequentItemsets()
    for (items, support) in sort!(collect(patterns); by=first)
        push_itemset!(packed, items, support)
    end
    return packed
end
