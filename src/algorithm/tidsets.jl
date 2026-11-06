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
