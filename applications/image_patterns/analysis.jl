function checked_patterns(patterns)
    columns = Tuple{Vararg{Int}}[]
    for pattern in patterns
        items = collect(pattern)
        !isempty(items) && all(x -> x isa Int && x > 0, items) &&
            issorted(items) && allunique(items) ||
            throw(ArgumentError("invalid visual-word pattern: $pattern"))
        push!(columns, Tuple(items))
    end
    allunique(columns) || throw(ArgumentError("duplicate visual-word patterns: $patterns"))
    columns
end

"""
    itemset_features(transactions, patterns) -> BitMatrix

Return one row per image and one column per pattern in the supplied order.
An entry is true exactly when the whole pattern occurs in that transaction.
Keep empty images as zero rows. Patterns must be nonempty, ascending, unique
positive Int tuples; invalid patterns or transactions throw `ArgumentError`.
Fit the vocabulary on training data before transforming held-out images.
"""
function itemset_features(transactions, patterns)
    columns = checked_patterns(patterns)
    presence = falses(length(transactions), length(columns))
    for (i, transaction) in enumerate(transactions)
        items = collect(transaction)
        all(x -> x isa Int && x > 0, items) ||
            throw(ArgumentError("invalid visual words in transaction $i: $transaction"))
        for (j, pattern) in enumerate(columns)
            presence[i, j] = all(word -> word in items, pattern)
        end
    end
    presence
end

"""
    pattern_label_summary(images, transactions, itemset)

Return ten rows with digit label, total images, supporting images, fraction,
and all supporting source IDs in ascending order. A label absent from the input
has fraction `nothing`. Preserve empty transactions in each label's denominator.
Misaligned images, duplicate source IDs, or invalid words throw `ArgumentError`.
"""
function pattern_label_summary(images, transactions, itemset)
    length(images) == length(transactions) ||
        throw(ArgumentError("image/transaction counts differ: $(length(images)), $(length(transactions))"))
    allunique(image.id for image in images) ||
        throw(ArgumentError("duplicate source image IDs"))
    presence = itemset_features(transactions, [itemset])
    [begin
        positions = findall(image -> image.label == label, images)
        ids = sort!([images[p].id for p in positions if presence[p, 1]])
        total, support = length(positions), length(ids)
        (; label, total, support, fraction=total == 0 ? nothing : support / total, image_ids=ids)
    end for label in 0:9]
end
