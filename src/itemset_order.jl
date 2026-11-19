"""
    lexicographic_order(packed) -> Vector{Int}

Return the indices of `packed` in the order `write_itemsets` writes them: items
compare as numbers, one position at a time, and a prefix precedes its
extensions. Expects validated itemsets, each nonempty, ascending, and
nonnegative. Throws `ArgumentError` naming an itemset that appears twice.
"""
function lexicographic_order(packed::FrequentItemsets)
    count = length(packed)
    # A depth-first search in item order emits this order already, so one scan suffices.
    all(k -> itemset_isless(packed, k, k + 1), 1:count-1) && return collect(1:count)
    # Low bits hold the index and the rest hold the first items, so one radix sort gives the order.
    index_bits = 64 - leading_zeros(UInt64(count))
    width = item_key_bits(packed.items)
    per_key = (128 - index_bits) ÷ width
    keyed = Vector{UInt128}(undef, count)
    for k in 1:count
        keyed[k] = prefix_key(packed, k, width, per_key) << index_bits | UInt128(k)
    end
    sort!(keyed)
    order = [Int(key & (UInt128(1) << index_bits - 1)) for key in keyed]
    first_in_run = 1
    for i in 2:count+1
        i <= count && keyed[i] >> index_bits == keyed[first_in_run] >> index_bits && continue
        order_equal_keys!(order, first_in_run, i - 1, packed)
        first_in_run = i
    end
    return order
end

"""
Bits per item in a sort key: enough for `item + 1` of the largest item, since
digit 0 marks a position past the end of a shorter itemset.
"""
item_key_bits(items::Vector{Int}) = 64 - leading_zeros(UInt64(maximum(items; init=0)) + 1)

"""
Pack the first `per_key` items of itemset `k`, each as `item + 1`, first item in
the highest bits. Ended positions stay 0, so comparing keys as integers compares
those items lexicographically with a prefix first.
"""
function prefix_key(packed::FrequentItemsets, k::Int, width::Int, per_key::Int)
    start = packed.offsets[k]
    used = min(packed.offsets[k+1] - start, per_key)
    key = UInt128(0)
    for position in start:start+used-1
        key = key << width | (UInt128(packed.items[position]) + 1)
    end
    # One shift fills the ended positions, so a short itemset costs only its own items.
    return key << (width * (per_key - used))
end

"""
Order the run `order[first:last]` of itemsets whose keys are equal, and throw on
a repeat. They share their first items, so they are compared in full.
"""
function order_equal_keys!(order::Vector{Int}, first::Int, last::Int, packed::FrequentItemsets)
    first == last && return order
    run = view(order, first:last)
    sort!(run; lt=(a, b) -> itemset_isless(packed, a, b))
    for i in 2:length(run)
        itemset_isless(packed, run[i-1], run[i]) || throw_repeated(packed, run[i])
    end
    return order
end

throw_repeated(packed::FrequentItemsets, k::Int) =
    throw(ArgumentError("itemset $(collect(itemset_view(packed, k))) appears more than once"))

"""Compare itemsets `a` and `b` as numbers, item by item; a prefix sorts first."""
function itemset_isless(packed::FrequentItemsets, a::Int, b::Int)
    offsets, items = packed.offsets, packed.items
    i, j = offsets[a], offsets[b]
    while i < offsets[a+1] && j < offsets[b+1]
        items[i] == items[j] || return items[i] < items[j]
        i += 1
        j += 1
    end
    return i == offsets[a+1] && j < offsets[b+1]
end
