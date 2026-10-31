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
mine(transactions; minsup::Real, variant::Symbol=:baseline) =
    support_map(mine_packed(transactions; minsup, variant))

"""
    mine_packed(transactions; minsup, variant=:baseline) -> FrequentItemsets

Return the same itemsets and supports as `mine`, packed into flat arrays instead
of a tuple-keyed map, and throw for the same input. Each itemset is ascending;
the order of itemsets is unspecified. Writers and benchmarks use this form, so
they never build a key per itemset.
"""
function mine_packed(transactions; minsup::Real, variant::Symbol=:baseline)
    variant in (:baseline, :optimized) ||
        throw(ArgumentError("variant must be :baseline or :optimized"))
    database = canonical_database(transactions)
    sup_req = support_threshold(minsup, length(database))
    # Raise instead of running the baseline, so a benchmark never mislabels it.
    variant == :baseline || throw(ErrorException("Eclat $variant is not implemented"))
    class = to_class(database)
    class = filter!(p -> length(last(p)) >= sup_req, class)
    return bottom_up!(class, Int[], sup_req, FrequentItemsets())
end

"""
Build the vertical index: each item paired with its tid-list, ordered by item.
Tids are added in ascending order, so every tid-list is sorted.
"""
function to_class(database::Vector{Vector{Int}})::Vector{Pair{Int, Vector{Int}}}
    class = Dict{Int, Vector{Int}}()
    for (tid, value) in enumerate(database)
        for item in value
            push!(get!(Vector{Int}, class, item), tid)
        end
    end
    return sort!(collect(class), by=first)
end

"""
Intersect two ascending tid-lists in one merge pass, so a join costs
O(|a| + |b|) and allocates only the ascending result.
"""
function intersect_tidlists(a::Vector{Int}, b::Vector{Int})
    result = Int[]
    sizehint!(result, min(length(a), length(b)))
    i, j = 1, 1
    while i <= length(a) && j <= length(b)
        x, y = a[i], b[j]
        if x == y
            push!(result, x)
            i += 1
            j += 1
        elseif x < y
            i += 1
        else
            j += 1
        end
    end
    return result
end

"""
Bottom-Up search of one prefix-based equivalence class (Zaki 2000, Sec. 4.2).
Each member is the last item of `prefix ∪ {item}` with that itemset's tid-list,
and every member is already frequent. `prefix` is one stack shared by the whole
search, so its type stays concrete at every depth; each call restores it.
"""
function bottom_up!(class::Vector{Pair{Int, Vector{Int}}}, prefix::Vector{Int}, minsup::Int, res::FrequentItemsets)
    for i in eachindex(class)
        (a, a_set) = class[i]
        push!(prefix, a)
        push_itemset!(res, prefix, length(a_set))
        cur_pass = Pair{Int, Vector{Int}}[]
        for j in i+1:lastindex(class)
            (b, b_set) = class[j]
            # t(PXY) = t(PX) ∩ t(PY), so the support needs no database scan.
            ab_set = intersect_tidlists(a_set, b_set)
            if length(ab_set) >= minsup
                push!(cur_pass, b => ab_set)
            end
        end
        isempty(cur_pass) || bottom_up!(cur_pass, prefix, minsup, res)
        pop!(prefix)
    end
    return res
end