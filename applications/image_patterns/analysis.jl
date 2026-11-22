function checked_pattern(pattern; max_word=typemax(Int))
    items = Tuple(pattern)
    !isempty(items) && all(x -> x isa Int && 1 <= x <= max_word, items) &&
        issorted(items) && allunique(items) ||
        throw(ArgumentError("invalid visual-word pattern: $pattern"))
    items
end

function checked_patterns(patterns)
    columns = [checked_pattern(pattern) for pattern in patterns]
    allunique(columns) || throw(ArgumentError("duplicate visual-word patterns: $patterns"))
    columns
end

function check_visual_transactions(transactions)
    for (i, items) in enumerate(transactions)
        all(x -> x isa Int && x > 0, items) ||
            throw(ArgumentError("invalid visual words in transaction $i: $items"))
    end
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
    check_visual_transactions(transactions)
    presence = falses(length(transactions), length(columns))
    for (j, pattern) in enumerate(columns), i in supporting_images(transactions, pattern)
        presence[i, j] = true
    end
    presence
end

function image_label_totals(images, transactions)
    length(images) == length(transactions) ||
        throw(ArgumentError("image/transaction counts differ: $(length(images)), $(length(transactions))"))
    seen = Set{Int}()
    totals = zeros(Int, 10)
    for image in images
        image.id in seen && throw(ArgumentError("duplicate source image ID $(image.id)"))
        push!(seen, image.id)
        totals[image.label + 1] += 1
    end
    totals
end

function pattern_label_summary(images, positions; totals)
    image_ids = [Int[] for _ in 0:9]
    for p in positions
        image = images[p]
        push!(image_ids[image.label + 1], image.id)
    end
    [begin
        ids = sort!(image_ids[label + 1])
        total, support = totals[label + 1], length(ids)
        (; label, total, support, fraction=total == 0 ? nothing : support / total, image_ids=ids)
    end for label in 0:9]
end

"""
    pattern_label_summary(images, transactions, itemset)

Return ten rows with digit label, total images, supporting images, fraction,
and all supporting source IDs in ascending order. A label absent from the input
has fraction `nothing`. Preserve empty transactions in each label's denominator.
Misaligned images, duplicate source IDs, or invalid words throw `ArgumentError`.
"""
function pattern_label_summary(images, transactions, itemset)
    totals = image_label_totals(images, transactions)
    check_visual_transactions(transactions)
    positions = supporting_images(transactions, checked_pattern(itemset))
    pattern_label_summary(images, positions; totals)
end
