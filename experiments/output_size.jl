"""
    check_monotone_counts(points)

Throw `ArgumentError` when a dataset reports fewer frequent itemsets at a lower
absolute threshold. Lowering the threshold keeps every frequent itemset frequent
(anti-monotonicity), so a smaller count means a lost itemset. Points without an
exact output count are skipped.
"""
function check_monotone_counts(points::AbstractVector{CurvePoint})
    for dataset in unique(p.dataset for p in points)
        known = sort!([p for p in points if p.dataset == dataset && p.output_count !== nothing];
                      by=p -> -p.minsup_count)
        for (higher, lower) in zip(known, Iterators.drop(known, 1))
            lower.output_count >= higher.output_count || throw(ArgumentError(
                "$dataset has $(lower.output_count) itemsets at count $(lower.minsup_count) but " *
                "$(higher.output_count) at the higher count $(higher.minsup_count)"))
        end
    end
    return nothing
end

"""
    itemset_length_counts(path) -> Vector{Int}

Number of frequent itemsets of each length in an SPMF output, so element `k`
counts the `k`-itemsets. Throws `ArgumentError` for a malformed output, as
`read_itemset_records` does.
"""
function itemset_length_counts(path::AbstractString)
    counts = Int[]
    for record in read_itemset_records(path)
        k = length(record.itemset)
        length(counts) < k && append!(counts, zeros(Int, k - length(counts)))
        counts[k] += 1
    end
    return counts
end

"""
    check_nested_outputs(higher, lower, higher_count)

Check two outputs of one database mined at different thresholds: the itemsets in
`lower` with support at least `higher_count` must be exactly those in `higher`,
with the same supports. Support does not depend on the threshold, so this catches
a support or itemset that only one run got wrong. Throws `ArgumentError` naming
the first itemset that is missing or whose support differs.
"""
function check_nested_outputs(higher::AbstractString, lower::AbstractString, higher_count::Integer)
    expected = Dict(r.itemset => r.support for r in read_itemset_records(higher))
    found = 0
    for record in read_itemset_records(lower)
        support = get(expected, record.itemset, nothing)
        if support === nothing
            record.support >= higher_count && throw(ArgumentError(
                "$(record.itemset) has support $(record.support) >= $higher_count in $lower but is missing from $higher"))
        else
            support == record.support || throw(ArgumentError(
                "$(record.itemset) has support $support in $higher but $(record.support) in $lower"))
            found += 1
        end
    end
    found == length(expected) || throw(ArgumentError(
        "$(length(expected) - found) itemsets of $higher are missing from $lower"))
    return nothing
end
