"""
Read SPMF transaction text. Skip blank lines and #, %, @ comment/metadata lines.
Item 0 is valid. Negative IDs (including sequence delimiters) are rejected.
Duplicates within a transaction collapse; duplicate transactions remain distinct.
For intentionally empty transactions, use the in-memory API instead of blank lines.
"""
function read_transactions(io::IO)
    bytes = read(io)
    transactions = Vector{Vector{Int}}()
    # Parsing into one reused vector and copying it at its final length allocates each
    # transaction once; growing a fresh vector per line took most of the read time.
    scratch = Int[]
    line_number = 0
    start = 1
    while start <= length(bytes)
        stop = something(findnext(==(UInt8(0x0a)), bytes, start), length(bytes) + 1)
        line_number += 1
        if parse_transaction_line!(scratch, view(bytes, start:stop-1), line_number)
            push!(transactions, canonical_copy(scratch))
        end
        start = stop + 1
    end
    return transactions
end

"""A sorted, deduplicated copy of `items`; files usually list items ascending already, so that case only copies."""
canonical_copy(items::Vector{Int}) = is_canonical(items) ? copy(items) : unique!(sort(items))

read_transactions(path::AbstractString) = open(read_transactions, path)

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

is_spmf_metadata(line::AbstractString) = isempty(line) || startswith(line, ('#', '%', '@'))

is_ascii_space(byte::UInt8) = byte == UInt8(' ') || 0x09 <= byte <= 0x0d

"""
Replace `items` with the item IDs of one line's bytes, in file order, and return
`true`, or return `false` for a blank or metadata line. Tokens and errors match
`parse_item_ids` on the stripped line.
"""
function parse_transaction_line!(items::Vector{Int}, line::AbstractVector{UInt8}, line_number::Int)
    empty!(items)
    # Bytes above 0x7f can be Unicode spaces or digits, which only the string parser handles.
    if any(>(0x7f), line)
        value = strip(String(line))
        is_spmf_metadata(value) && return false
        append!(items, parse_item_ids(value, line_number))
        return true
    end
    i, n = 1, length(line)
    while i <= n && is_ascii_space(line[i])
        i += 1
    end
    i > n && return false
    line[i] in codeunits("#%@") && return false
    while i <= n
        j = i
        value = 0
        all_digits = true
        while j <= n && !is_ascii_space(line[j])
            digit = line[j] - UInt8('0')
            all_digits &= digit <= 9
            value = 10value + digit
            j += 1
        end
        # 18 digits stay below typemax(Int), so `value` is exact; other tokens, whose `value` may have wrapped, take the general parser.
        push!(items, all_digits && j - i <= 18 ? value : parse_item_id(view(line, i:j-1), line_number))
        i = j
        while i <= n && is_ascii_space(line[i])
            i += 1
        end
    end
    return true
end

"""Parse one ASCII token that is not a plain run of at most 18 digits, such as `+5` or a 19-digit ID."""
function parse_item_id(token::AbstractVector{UInt8}, line_number::Int)
    text = String(copy(token))
    item = tryparse(Int, text)
    (item === nothing || item < 0) &&
        throw(ArgumentError("line $line_number: invalid item ID $(repr(text))"))
    return item
end

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
