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
    append_item_tokens!(items, line, i, n, line_number)
    return true
end

"""
Append the item IDs of the ASCII bytes `line[i:n]`, split at ASCII spaces, to
`items`. Throws `ArgumentError` naming `line_number` for an invalid token, as
`parse_item_ids` does.
"""
function append_item_tokens!(items::Vector{Int}, line::AbstractVector{UInt8}, i::Int, n::Int, line_number::Int)
    while i <= n && is_ascii_space(line[i])
        i += 1
    end
    while i <= n
        j, value, plain = plain_digits(line, i, n)
        push!(items, plain ? value : parse_item_id(view(line, i:j-1), line_number))
        i = j
        while i <= n && is_ascii_space(line[i])
            i += 1
        end
    end
    return items
end

"""
Scan the token that starts at `line[i]` and ends before the next ASCII space or
past `n`. Return the index after it, its value, and whether it is a plain run of
at most 18 digits; only then is the value exact, because 18 digits stay below
`typemax(Int)` and other tokens may wrap.
"""
function plain_digits(line::AbstractVector{UInt8}, i::Int, n::Int)
    j = i
    value = 0
    all_digits = true
    while j <= n && !is_ascii_space(line[j])
        digit = line[j] - UInt8('0')
        all_digits &= digit <= 9
        value = 10value + digit
        j += 1
    end
    return j, value, all_digits && j - i <= 18
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
    bytes = read(io)
    records = ItemsetRecord[]
    items = Int[]
    line_number = 0
    start = 1
    while start <= length(bytes)
        stop = something(findnext(==(UInt8(0x0a)), bytes, start), length(bytes) + 1)
        line_number += 1
        line = view(bytes, start:stop-1)
        record = plain_record!(items, line, line_number)
        if record === nothing
            # Anything but a plain `items #SUP: count` line, including every invalid one,
            # goes through the general parser, so skips and error messages stay exact.
            record = record_from_text(strip(String(line)), line_number)
        end
        record === nothing || push!(records, record)
        start = stop + 1
    end
    return records
end

read_itemset_records(path::AbstractString) = open(read_itemset_records, path)

const SUPPORT_MARK = codeunits("#SUP:")

"""
Parse an ASCII line of plain item IDs, `#SUP:`, and one plain positive count
into a record, or return `nothing` when the line has any other form. Item
tokens that are not plain digits still parse or throw as in `parse_item_ids`.
"""
function plain_record!(items::Vector{Int}, line::AbstractVector{UInt8}, line_number::Int)
    any(>(0x7f), line) && return nothing
    mark = findfirst(SUPPORT_MARK, line)
    mark === nothing && return nothing
    n = length(line)
    i = last(mark) + 1
    while i <= n && is_ascii_space(line[i])
        i += 1
    end
    i <= n || return nothing
    j, support, plain = plain_digits(line, i, n)
    plain && support >= 1 || return nothing
    while j <= n
        is_ascii_space(line[j]) || return nothing
        j += 1
    end
    empty!(items)
    append_item_tokens!(items, line, 1, first(mark) - 1, line_number)
    isempty(items) && return nothing
    is_canonical(items) || is_canonical(sort!(items)) || return nothing
    return (itemset=Tuple(items), support=support, line=line_number)
end

"""
Parse one stripped line of SPMF itemset output into a record, or return
`nothing` for a metadata line. Throws `ArgumentError` naming `line_number`.
"""
function record_from_text(value::AbstractString, line_number::Int)
    is_spmf_metadata(value) && !occursin("#SUP:", value) && return nothing
    parts = match(r"^(.*?)\s*#SUP:\s*(\S*)$", value)
    parts === nothing &&
        throw(ArgumentError("line $line_number: expected 'items #SUP: count', got $(repr(value))"))
    items = parse_item_ids(parts[1], line_number)
    isempty(items) && throw(ArgumentError("line $line_number: empty itemset"))
    allunique(items) || throw(ArgumentError("line $line_number: repeated item ID in $(repr(value))"))
    support = tryparse(Int, parts[2])
    (support === nothing || support < 1) &&
        throw(ArgumentError("line $line_number: invalid support $(repr(parts[2]))"))
    return (itemset=Tuple(sort!(items)), support=support, line=line_number)
end
