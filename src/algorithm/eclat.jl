"""
    mine(transactions; minsup, variant=:baseline) -> SupportMap

Shared Eclat contract for both applications. `transactions` contains integer-ID
collections; duplicate transactions count separately and empty transactions count
in the relative-support denominator. Return ALL frequent nonempty itemsets with
exact integer support. No implicit length cap or closed/maximal substitution.

Implementation task: DAT-8 (baseline); optimization follows baseline validation.
This setup deliberately raises an error until the paper-based miner is written.
"""
function mine(transactions; minsup::Real, variant::Symbol=:baseline)
    variant in (:baseline, :optimized) ||
        throw(ArgumentError("variant must be :baseline or :optimized"))
    support_threshold(minsup, length(transactions))
    throw(ErrorException("Eclat $variant is not implemented yet. See DAT-8; fixtures are development aids only."))
end
