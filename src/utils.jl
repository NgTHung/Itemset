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

"""Write deterministic canonical SPMF output. Validate before writing any bytes."""
function write_itemsets(io::IO, patterns::AbstractDict)
    for (items, support) in patterns
        !isempty(items) && Tuple(canonical_transaction(items)) == items ||
            throw(ArgumentError("itemset keys must be nonempty canonical tuples"))
        support isa Integer && !(support isa Bool) && support >= 1 ||
            throw(ArgumentError("supports must be positive integers"))
    end
    for items in sort!(collect(keys(patterns)))
        println(io, join(items, ' '), " #SUP: ", patterns[items])
    end
    return nothing
end

write_itemsets(path::AbstractString, patterns::AbstractDict) =
    open(io -> write_itemsets(io, patterns), path, "w")
