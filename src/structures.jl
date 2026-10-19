"""Canonical, ascending integer item IDs; a key never contains duplicates."""
const Itemset = Tuple{Vararg{Int}}
const SupportMap = Dict{Itemset,Int}
const DEFAULT_SEED = 42

"""Sort and deduplicate one transaction without changing the caller's data."""
function canonical_transaction(items)
    for item in items
        item isa Integer && !(item isa Bool) && 0 <= item <= typemax(Int) ||
            throw(ArgumentError("item IDs must be nonnegative Int values (not Bool), got $(repr(item))"))
    end
    return sort!(unique(Int[item for item in items]))
end

"""
Julia iterates a number or string as a one-element or per-character collection,
so a flat vector or a bare label would otherwise pass as several transactions.
"""
is_item_collection(value) =
    !(value isa Union{Number,AbstractChar,AbstractString}) && applicable(iterate, value)

"""Canonicalize every transaction. Empty transactions stay, because they count in N."""
function canonical_database(transactions)
    database = Vector{Vector{Int}}()
    for (index, transaction) in enumerate(transactions)
        is_item_collection(transaction) ||
            throw(ArgumentError("transaction $index must be a collection of item IDs, got $(repr(transaction))"))
        try
            push!(database, canonical_transaction(transaction))
        catch error
            # Add the index so the caller can find the bad record in a large database.
            error isa ArgumentError || rethrow()
            throw(ArgumentError("transaction $index: $(error.msg)"))
        end
    end
    return database
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
