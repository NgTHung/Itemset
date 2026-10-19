"""
    brute_force_supports(transactions, min_count) -> SupportMap

Count every nonempty subset of the distinct items directly. It shares no code
with Eclat, so it can prove hand-derived fixture maps complete and serve as an
independent reference on tiny databases. Throws `ArgumentError` above 16
distinct items, where 2^16 subsets stops being a quick test.
"""
function brute_force_supports(transactions::AbstractVector, min_count::Integer)
    items = sort!(unique(Int[item for transaction in transactions for item in transaction]))
    length(items) <= 16 ||
        throw(ArgumentError("brute force supports at most 16 distinct items, got $(length(items))"))
    supports = SupportMap()
    for mask in 1:(2^length(items) - 1)
        itemset = Tuple(items[bit] for bit in eachindex(items) if isodd(mask >> (bit - 1)))
        support = count(transaction -> all(in(transaction), itemset), transactions)
        support >= min_count && (supports[itemset] = support)
    end
    return supports
end
