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
    empty!(dest)
    i, j = 1, 1
    while i <= length(a) && j <= length(b)
        length(dest) + min(length(a) - i, length(b) - j) + 1 < minsup && return -1
        x, y = a[i], b[j]
        if x == y
            push!(dest, x)
            i += 1
            j += 1
        elseif x < y
            i += 1
        else
            j += 1
        end
    end
    return length(dest) >= minsup ? length(dest) : -1
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
