"""
    mine(transactions; minsup, variant=:baseline) -> SupportMap

Return every frequent nonempty itemset in `transactions` with its exact support
count. `transactions` holds integer-ID collections; duplicate transactions count
separately and empty transactions count in the relative-support denominator.
There is no length cap and no closed or maximal substitution, because callers
compare complete maps. See `docs/interface.md` for the full contract.

Throws `ArgumentError` for an unknown `variant` or invalid `minsup`, and
`ErrorException` for a variant without an implementation.
"""
function mine(transactions; minsup::Real, variant::Symbol=:baseline)
    variant in (:baseline, :optimized) ||
        throw(ArgumentError("variant must be :baseline or :optimized"))
    support_threshold(minsup, length(transactions))
    throw(ErrorException("Eclat $variant is not implemented"))
end
