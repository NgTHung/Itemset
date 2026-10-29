"""
    AssociationRule

The rule `antecedent ⇒ consequent` with the counts its measures need: `support`
is the number of transactions holding both sides, and `transactions` is N.
`confidence`, `lift`, and `relative_support` return exact `Rational`s, so a
ranking or a threshold never depends on floating-point rounding.
"""
struct AssociationRule
    antecedent::Itemset
    consequent::Itemset
    support::Int
    antecedent_support::Int
    consequent_support::Int
    transactions::Int
end

"""support(X ∪ Y) / N."""
relative_support(rule::AssociationRule) = rule.support // rule.transactions

"""support(X ∪ Y) / support(X): the share of baskets with X that also hold Y."""
confidence(rule::AssociationRule) = rule.support // rule.antecedent_support

"""
confidence(X ⇒ Y) / (support(Y) / N): how many times more often Y appears with X
than it would if the two sides were independent. Lift is symmetric in X and Y.
Throws `OverflowError` instead of wrapping when the counts are too large for `Int`.
"""
lift(rule::AssociationRule) =
    Base.checked_mul(rule.support, rule.transactions) //
    Base.checked_mul(rule.antecedent_support, rule.consequent_support)

"""
Rank order: lift, confidence, and support descending, then antecedent and
consequent as ascending ID tuples. Mirrored rules X ⇒ Y and Y ⇒ X always share
a lift, so the direction with the higher confidence ranks first, and the last
two keys make the order total.
"""
rank_key(rule::AssociationRule) =
    (-lift(rule), -confidence(rule), -rule.support, rule.antecedent, rule.consequent)

function subset_support(patterns::AbstractDict, itemset::Itemset)
    support = get(patterns, itemset, nothing)
    # mine returns every subset of a frequent itemset, so a gap means the map
    # did not come from mine and its rules would be incomplete.
    support === nothing &&
        throw(ArgumentError("itemset $itemset is missing; the map must hold every subset of each frequent itemset"))
    return support
end

"""
    association_rules(patterns, transactions; minconf) -> Vector{AssociationRule}

Every rule X ⇒ Y with nonempty disjoint X and Y whose union is a key of
`patterns` and whose confidence is at least `minconf`, in `rank_key` order.
`patterns` is the output of `mine`, so minsup already applies to each union.
`transactions` is N of the mined database.

Throws `ArgumentError` for a `minconf` that is not a fraction in (0, 1], for a
negative N or a support above it, and for a map that lacks a subset of one of
its itemsets.
"""
function association_rules(patterns::AbstractDict, transactions::Integer; minconf::Real)
    minconf isa AbstractFloat && isfinite(minconf) && 0 < minconf <= 1 ||
        throw(ArgumentError("minconf must be a floating-point fraction in (0, 1], got $(repr(minconf))"))
    transactions >= 0 || throw(ArgumentError("transaction count must be nonnegative, got $transactions"))
    rules = AssociationRule[]
    for (itemset, support) in patterns
        support <= transactions ||
            throw(ArgumentError("itemset $itemset has support $support above $transactions transactions"))
        k = length(itemset)
        k >= 2 || continue
        k < 63 || throw(ArgumentError("itemset $itemset is too long to enumerate its $k-item splits"))
        # Each mask picks the antecedent; its complement in the itemset is the consequent.
        for mask in 1:(1 << k) - 2
            antecedent = Tuple(itemset[i] for i in 1:k if isodd(mask >> (i - 1)))
            consequent = Tuple(itemset[i] for i in 1:k if iseven(mask >> (i - 1)))
            antecedent_support = subset_support(patterns, antecedent)
            # confidence ≥ minconf exactly when support ≥ ⌈minconf · support(X)⌉,
            # which support_threshold computes on the decimal value of minconf.
            support >= support_threshold(minconf, antecedent_support) || continue
            push!(rules, AssociationRule(antecedent, consequent, support, antecedent_support,
                                         subset_support(patterns, consequent), transactions))
        end
    end
    return sort!(rules; by=rank_key)
end

"""
    top_rules(rules, k) -> (rules, ties_beyond)

The first `k` of `rules`, which must be in `rank_key` order, and the number of
later rules whose lift equals the `k`-th rule's lift. A nonzero `ties_beyond`
means the cut falls inside a tie, so the table states it. Throws
`ArgumentError` for `k < 1` or unranked rules.
"""
function top_rules(rules::AbstractVector{AssociationRule}, k::Integer)
    k >= 1 || throw(ArgumentError("k must be at least 1, got $k"))
    issorted(rules; by=rank_key) || throw(ArgumentError("rules must be in rank_key order"))
    k >= length(rules) && return (rules=collect(rules), ties_beyond=0)
    cutoff = lift(rules[k])
    return (rules=rules[1:k], ties_beyond=count(r -> lift(r) == cutoff, @view rules[k+1:end]))
end

"""
    top_rule_groups(rules, k) -> Vector{AssociationRule}

The highest-ranked rule of each distinct product group X ∪ Y, for the first `k`
groups. One frequent itemset yields up to 2^m - 2 rules with similar lift, so
this view shows `k` different patterns instead of one pattern's splits.
"""
function top_rule_groups(rules::AbstractVector{AssociationRule}, k::Integer)
    k >= 1 || throw(ArgumentError("k must be at least 1, got $k"))
    seen = Set{Itemset}()
    groups = AssociationRule[]
    for rule in rules
        length(groups) == k && break
        group = Tuple(sort!([rule.antecedent..., rule.consequent...]))
        group in seen && continue
        push!(seen, group)
        push!(groups, rule)
    end
    return groups
end

"""
    measure_rule(rule, transactions) -> AssociationRule

Recount the supports of `rule`'s sides in another basket set, such as one year
of receipts, without mining it. Mining a subset again at the same relative
minsup would drop a rule that falls just under the smaller threshold, which
reads as a vanished pattern. The counts may be zero, so check
`antecedent_support` and `consequent_support` before asking for confidence or lift.
"""
function measure_rule(rule::AssociationRule, transactions::AbstractVector{<:AbstractVector{Int}})
    antecedent = consequent = both = 0
    for t in transactions
        has_antecedent = issubset(rule.antecedent, t)
        has_consequent = issubset(rule.consequent, t)
        antecedent += has_antecedent
        consequent += has_consequent
        both += has_antecedent && has_consequent
    end
    return AssociationRule(rule.antecedent, rule.consequent, both, antecedent, consequent, length(transactions))
end

"""Map each rule's `(antecedent, consequent)` to its 1-based rank in `rules`."""
rule_ranks(rules::AbstractVector{AssociationRule}) =
    Dict((r.antecedent, r.consequent) => rank for (rank, r) in enumerate(rules))

"""Both sides of `rule` as text, joining multi-item sides with ` + `."""
rule_labels(rule::AssociationRule, labels::AbstractVector) =
    (join(decode_itemset(labels, rule.antecedent), " + "),
     join(decode_itemset(labels, rule.consequent), " + "))

"""
    write_rules(path, rules, labels)

Write `rules` as a TSV, one row per rule in the given order with its rank,
labels, IDs, support count, and measures to four decimals. Validates every
label before opening `path`, so an ID without a label or a label with a tab or
line break throws `ArgumentError` and leaves an existing file untouched.
"""
function write_rules(path::AbstractString, rules::AbstractVector{AssociationRule}, labels::AbstractVector)
    rows = map(enumerate(rules)) do (rank, rule)
        left, right = rule_labels(rule, labels)
        occursin(r"[\t\r\n]", left * right) &&
            throw(ArgumentError("rule $rank has a label with a tab or line break"))
        join((rank, left, right, join(rule.antecedent, ' '), join(rule.consequent, ' '), rule.support,
              @sprintf("%.4f", Float64(relative_support(rule))), @sprintf("%.4f", Float64(confidence(rule))),
              @sprintf("%.4f", Float64(lift(rule)))), '\t')
    end
    open(path, "w") do io
        println(io, "rank\tantecedent\tconsequent\tantecedent_ids\tconsequent_ids\tsupport\trelative_support\tconfidence\tlift")
        foreach(row -> println(io, row), rows)
    end
    return nothing
end
