# Most blocks a class's tid range is split into. A BBQ sweep of 64 to 512 cut warm mining on
# T10I4D100K 0.00025 from 0.865 s to 0.668 s at 256 and 0.659 s at 512, with the other points
# unchanged; see docs/eclat-optimized.md.
const BOUND_BLOCKS = 256

"""
    BlockCounts(counts, class, bound_blocks)

The number of tids of each member of a tid-list class in each block of 2^shift
tids, column by column in `counts`, which is resized and refilled. The support
of a join of members `i` and `j` is at most the sum over blocks of the smaller
of their two counts, so a join whose bound is below minsup is never merged.
Blocks have the narrowest power-of-two width that splits tids 1 to the
class's largest tid into at most `bound_blocks` blocks. Throws `ArgumentError`
when `bound_blocks < 1` or the largest tid exceeds `typemax(Int32)`.
"""
struct BlockCounts
    counts::Vector{Int32}
    blocks::Int

    function BlockCounts(counts::Vector{Int32}, class::Vector{ClassMember{Int}}, bound_blocks::Int)
        bound_blocks >= 1 || throw(ArgumentError("bound_blocks must be at least 1, got $bound_blocks"))
        largest = maximum(m -> last(m.tidset), class)
        # No count or bound exceeds the largest tid, so Int32 cannot overflow below this limit.
        largest <= typemax(Int32) || throw(ArgumentError("tid $largest exceeds the Int32 block counts"))
        width = cld(largest, bound_blocks)
        shift = width <= 1 ? 0 : 64 - leading_zeros(UInt64(width - 1))
        blocks = cld(largest, 1 << shift)
        fill!(resize!(counts, blocks * length(class)), Int32(0))
        for (m, member) in enumerate(class)
            column = (m - 1) * blocks
            for tid in member.tidset
                counts[column + (tid - 1) >> shift + 1] += Int32(1)
            end
        end
        return new(counts, blocks)
    end
end

"""The block-count upper bound on the support of the join of members `i` and `j`."""
function block_bound(bound::BlockCounts, i::Int, j::Int)
    blocks, counts = bound.blocks, bound.counts
    first_i, first_j = (i - 1) * blocks, (j - 1) * blocks
    total = Int32(0)
    for k in 1:blocks
        total += min(counts[first_i+k], counts[first_j+k])
    end
    return Int(total)
end

may_be_frequent(bound::BlockCounts, i::Int, j::Int, minsup::Int) = block_bound(bound, i, j) >= minsup

"""Return the counts of a finished class to `state` for the next tid-list class."""
release_filter!(state::SearchState, filter::BlockCounts) = push!(state.block_counts, filter.counts)
