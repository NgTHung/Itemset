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
        (isempty(value) || startswith(value, ('#', '%', '@'))) && continue
        items = Int[]
        for token in split(value)
            item = tryparse(Int, token)
            (item === nothing || item < 0) &&
                throw(ArgumentError("line $line_number: invalid item ID $(repr(token))"))
            push!(items, item)
        end
        push!(transactions, canonical_transaction(items))
    end
    return transactions
end

read_transactions(path::AbstractString) = open(read_transactions, path)

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
    print_itemsets(io, patterns)
end

function write_itemsets(path::AbstractString, patterns::AbstractDict)
    check_itemsets(patterns)
    open(io -> print_itemsets(io, patterns), path, "w")
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

function print_itemsets(io::IO, patterns::AbstractDict)
    for items in sort!(collect(keys(patterns)))
        println(io, join(items, ' '), " #SUP: ", patterns[items])
    end
    return nothing
end
