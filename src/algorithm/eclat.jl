"""
    mine(transactions; minsup, variant=:baseline) -> SupportMap

Return every frequent nonempty itemset in `transactions` with its exact support
count. `transactions` holds integer-ID collections; duplicate transactions count
separately and empty transactions count in the relative-support denominator.
There is no length cap and no closed or maximal substitution, because callers
compare complete maps. See `docs/interface.md` for the full contract.

Throws `ArgumentError` for an unknown `variant`, invalid `minsup`, or an invalid
transaction, whose 1-based index the message names. Throws `ErrorException` for
a variant without an implementation.
"""
function mine(transactions; minsup::Real, variant::Symbol=:baseline)
    variant in (:baseline, :optimized) ||
        throw(ArgumentError("variant must be :baseline or :optimized"))
    database = canonical_database(transactions)
    sup_req = support_threshold(minsup, length(database))
    # Raise instead of running the baseline, so a benchmark never mislabels it.
    variant == :baseline || throw(ErrorException("Eclat $variant is not implemented"))
    class = to_class(database)
    class = filter!(p -> length(last(p)) >= sup_req, class)
    res::SupportMap = Dict()
    bottom_up!(class, (), sup_req, res)
    return res
end

"""
Build the vertical index: each item paired with its tid-list, ordered by item.
Tids are added in ascending order, so every tid-list is sorted.
"""
function to_class(database::Vector{Vector{Int}})::Vector{Pair{Int, Vector{Int}}}
    class::Dict{Int, Vector{Int}} = Dict()
    for (tid, value) in enumerate(database)
        for item in value
            if !haskey(class, item)
                class[item] = Vector()
            end
            push!(class[item], tid)
        end
    end
    return sort!(collect(class), by=first)
end

"""
Bottom-Up search of one prefix-based equivalence class (Zaki 2000, Sec. 4.2).
Each member is the last item of `prefix ∪ {item}` with that itemset's tid-list,
and every member is already frequent.
"""
function bottom_up!(class::Vector{Pair{Int, Vector{Int}}}, prefix::Itemset, minsup::Int, res::SupportMap)
    for i in eachindex(class)
        cur_pass::Vector{Pair{Int, Vector{Int}}} = Vector()
        (a, a_set) = class[i]
        t_prefix = (prefix...,a)
        res[t_prefix] = length(a_set)
        for (b, b_set) in class[i+1:end]
            # t(PXY) = t(PX) ∩ t(PY), so the support needs no database scan.
            ab_set = a_set ∩ b_set
            if length(ab_set) >= minsup
                push!(cur_pass, b => ab_set)
            end
        end
        isempty(cur_pass) || bottom_up!(cur_pass, t_prefix, minsup, res)
    end
    return res
end