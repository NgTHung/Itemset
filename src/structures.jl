"""Canonical, ascending integer item IDs; a key never contains duplicates."""
const Itemset = Tuple{Vararg{Int}}
const SupportMap = Dict{Itemset,Int}
const DEFAULT_SEED = 20261018

"""Sort and deduplicate one transaction without changing the caller's data."""
function canonical_transaction(items)
    all(x -> x isa Integer && !(x isa Bool) && x >= 0, items) ||
        throw(ArgumentError("item IDs must be nonnegative integers (not Bool)"))
    return sort!(unique(Int[x for x in items]))
end

"""
    support_threshold(minsup, transaction_count)

Integer minsup is an absolute positive count. Floating-point minsup is relative,
in (0, 1], rounded upward. A zero-transaction database has no frequent itemsets.
"""
function support_threshold(minsup::Real, transaction_count::Integer)
    transaction_count >= 0 || throw(ArgumentError("transaction count must be nonnegative"))
    if minsup isa Integer && !(minsup isa Bool)
        minsup >= 1 || throw(ArgumentError("absolute minsup must be at least 1"))
        return Int(minsup)
    elseif minsup isa AbstractFloat
        isfinite(minsup) && 0 < minsup <= 1 ||
            throw(ArgumentError("relative minsup must be in (0, 1]"))
        # Use the decimal representation to avoid 0.07 * 100 becoming
        # 7.000000000000001 and accidentally requiring eight transactions.
        return setprecision(BigFloat, 256) do
            max(1, ceil(Int, parse(BigFloat, string(minsup)) * transaction_count))
        end
    end
    throw(ArgumentError("minsup must be an integer count or floating-point fraction"))
end
