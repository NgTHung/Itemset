"""
    bitset_tidsets(database, items) -> Vector{Vector{UInt64}}

Build one bitset tidset per entry of `items`, in that order. Bit `t - 1` of the
words marks tid `t`, and each set has `cld(length(database), 64)` words. Only
tids 1 to N are ever set, so the unused high bits of the last word stay zero and
`count_ones` over the words is the support. Items not listed are ignored.
"""
function bitset_tidsets(database::Vector{Vector{Int}}, items::Vector{Int})
    words = cld(length(database), 64)
    sets = [zeros(UInt64, words) for _ in items]
    position = Dict(item => k for (k, item) in enumerate(items))
    for (tid, transaction) in enumerate(database)
        word, bit = divrem(tid - 1, 64)
        for item in transaction
            k = get(position, item, 0)
            k == 0 || (sets[k][word+1] |= UInt64(1) << bit)
        end
    end
    return sets
end

"""
Write `a .& b` into `dest` and return its number of set bits, the support of
the joined itemset. One pass reads each word once and allocates nothing. Throws
`DimensionMismatch` unless the three sets have the same length.
"""
function intersect_bitsets!(dest::Vector{UInt64}, a::Vector{UInt64}, b::Vector{UInt64})
    length(dest) == length(a) == length(b) ||
        throw(DimensionMismatch("bitsets have $(length(dest)), $(length(a)), and $(length(b)) words"))
    support = 0
    # @inbounds @simd changed warm mining time by -8% to +11% on five development points, within noise.
    for w in eachindex(a)
        word = a[w] & b[w]
        dest[w] = word
        support += count_ones(word)
    end
    return support
end

"""
    intersect_lists!(dest, a, b, minsup) -> Int

Write the common tids of ascending lists `a` and `b` into `dest` and return
their number when it reaches `minsup`, or -1 when it cannot. The merge stops
early once the tids found plus the shorter remainder fall below `minsup`; it
never stops on reaching `minsup`, since the child needs its whole tidset.
"""
function intersect_lists!(dest::Vector{Int}, a::Vector{Int}, b::Vector{Int}, minsup::Int)
    na, nb = length(a), length(b)
    resize!(dest, min(na, nb))
    i, j, found = 1, 1, 0
    # Each step writes a[i] and keeps it only on a match, so the loop has no data-dependent branch.
    while i <= na && j <= nb
        found + min(na - i, nb - j) + 1 < minsup && return -1
        # In bounds: i <= na, j <= nb, and found < min(i, j) <= min(na, nb) = length(dest).
        @inbounds x, y = a[i], b[j]
        @inbounds dest[found+1] = x
        found += x == y
        i += x <= y
        j += y <= x
    end
    resize!(dest, found)
    return found >= minsup ? found : -1
end

"""Write the tids of bitset `words` into `dest` in ascending order: bit `t - 1` is tid `t`."""
function bitset_tids!(dest::Vector{Int}, words::Vector{UInt64})
    empty!(dest)
    for (w, word) in enumerate(words)
        while word != 0
            push!(dest, 64 * (w - 1) + trailing_zeros(word) + 1)
            word &= word - 1
        end
    end
    return dest
end

bitset_tids(words::Vector{UInt64}) = bitset_tids!(Int[], words)

"""
    difference_lists!(dest, b, a, bound) -> Int

Write the tids of ascending list `b` that are not in ascending list `a` into
`dest` and return their number, or -1 once it passes `bound`. A diffset join
passes the most tids its child may lose and stay frequent as `bound`.
"""
function difference_lists!(dest::Vector{Int}, b::Vector{Int}, a::Vector{Int}, bound::Int)
    nb, na = length(b), length(a)
    resize!(dest, nb)
    i, j, kept = 1, 1, 0
    # As in intersect_lists!, each step writes b[i] and keeps it only when a lacks it.
    while i <= nb && j <= na
        # In bounds: i <= nb, j <= na, and kept < i <= nb = length(dest).
        @inbounds x, y = b[i], a[j]
        @inbounds dest[kept+1] = x
        kept += x < y
        i += x <= y
        j += y <= x
        kept > bound && return -1
    end
    rest = nb - i + 1
    kept + rest > bound && return -1
    copyto!(dest, kept + 1, b, i, rest)
    resize!(dest, kept + rest)
    return kept + rest
end

"""
    bitset_difference!(dest, a, b, bound) -> Int

Write the tids set in bitset `a` but not in `b` into `dest` in ascending order
and return their number, or -1 once it passes `bound`. Throws
`DimensionMismatch` unless `a` and `b` have the same length.
"""
function bitset_difference!(dest::Vector{Int}, a::Vector{UInt64}, b::Vector{UInt64}, bound::Int)
    length(a) == length(b) || throw(DimensionMismatch("bitsets have $(length(a)) and $(length(b)) words"))
    empty!(dest)
    for w in eachindex(a)
        word = a[w] & ~b[w]
        while word != 0
            length(dest) == bound && return -1
            push!(dest, 64 * (w - 1) + trailing_zeros(word) + 1)
            word &= word - 1
        end
    end
    return length(dest)
end
