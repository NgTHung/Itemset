const SUPPORT_TAG = codeunits(" #SUP: ")
const WRITE_CHUNK = 1 << 16

# Values below this length format through the table; 2^20 entries keep it at 9 MiB and cover
# every item and support of the benchmark datasets.
const DIGIT_TABLE_LENGTH = 1 << 20

"""
The decimal digits of every value in `0:length(words)-1`. `words[v+1]` holds the
digit bytes of `v`, first digit in the low byte, and `lengths[v+1]` their count.
A table value has at most 7 digits, so it fits one word.
"""
struct DigitTable
    words::Vector{UInt64}
    lengths::Vector{UInt8}

    """A table covering `0:largest`, capped at `DIGIT_TABLE_LENGTH` entries."""
    function DigitTable(largest::Int)
        count = clamp(largest + 1, 10, DIGIT_TABLE_LENGTH)
        words, lengths = Vector{UInt64}(undef, count), Vector{UInt8}(undef, count)
        for value in 0:count-1
            # A value's digits are those of value ÷ 10 followed by its last digit.
            head, digit = divrem(value, 10)
            if head == 0
                words[value+1], lengths[value+1] = UInt64('0') + digit, 1
            else
                words[value+1] = words[head+1] | (UInt64('0') + digit) << (8 * lengths[head+1])
                lengths[value+1] = lengths[head+1] + 1
            end
        end
        return new(words, lengths)
    end
end

"""
Write itemsets `order` as SPMF lines through one fixed buffer. Each line's
largest possible size is reserved before it is written, so the buffer is
flushed between lines, and grown only for a line longer than `WRITE_CHUNK`.
"""
function print_packed(io::IO, packed::FrequentItemsets, order::Vector{Int})
    table = DigitTable(max(maximum(packed.items; init=0), maximum(packed.supports; init=0)))
    buffer = Vector{UInt8}(undef, WRITE_CHUNK)
    used = 0
    for k in order
        start, stop = packed.offsets[k], packed.offsets[k+1] - 1
        # An Int has at most 19 digits, so an item and its separator take at most 20 bytes.
        line_bound = 20 * (stop - start + 1) + length(SUPPORT_TAG) + 20
        if used + line_bound > length(buffer)
            write(io, view(buffer, 1:used))
            used = 0
            line_bound > length(buffer) && resize!(buffer, line_bound)
        end
        for position in start:stop
            position == start || (buffer[used += 1] = UInt8(' '))
            used = put_number!(buffer, used, table, packed.items[position])
        end
        copyto!(buffer, used + 1, SUPPORT_TAG, 1, length(SUPPORT_TAG))
        used = put_number!(buffer, used + length(SUPPORT_TAG), table, packed.supports[k])
        buffer[used += 1] = UInt8('\n')
    end
    write(io, view(buffer, 1:used))
    return nothing
end

"""
Write the decimal digits of a nonnegative `value` into `buffer` after position
`used`, and return the new last position. May write up to 8 bytes past it, which
the caller's 20-byte reservation per number covers.
"""
@inline function put_number!(buffer::Vector{UInt8}, used::Int, table::DigitTable, value::Int)
    # Inlined so the table path costs no call per number; this took Mushroom 0.05 printing from 0.61 s to 0.50 s on BBQ.
    0 <= value < length(table.words) || return put_digits!(buffer, used, value)
    # The constructor gives both table vectors one length, and the range check above
    # and this one cover every index below.
    checkbounds(buffer, used + 8)
    @inbounds word = table.words[value+1]
    # Always writing all 8 bytes lets the compiler merge them into one store; the
    # bytes past the digits are overwritten by what follows.
    for byte in 1:8
        @inbounds buffer[used+byte] = (word >> (8 * (byte - 1))) % UInt8
    end
    return used + @inbounds table.lengths[value+1]
end

"""Write a value outside the digit table, placing digits from the right, so no string or reversal is needed."""
function put_digits!(buffer::Vector{UInt8}, used::Int, value::Int)
    last_position = used + ndigits(value)
    position = last_position
    while true
        value, digit = divrem(value, 10)
        buffer[position] = UInt8('0') + digit % UInt8
        position -= 1
        value == 0 && return last_position
    end
end
