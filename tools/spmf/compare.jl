using ItemsetMining

struct ParsedItemsets
    itemsets::SupportMap
    duplicates::Vector{Tuple{Itemset,Int}}
end

struct ItemsetComparison
    missing::Vector{Itemset}
    extra::Vector{Itemset}
    support_mismatches::Vector{Tuple{Itemset,Int,Int}}
    reference_duplicates::Vector{Tuple{Itemset,Int}}
    candidate_duplicates::Vector{Tuple{Itemset,Int}}
    match_rate::Float64
    matches::Bool
end

"""
    parse_itemsets(input) -> ParsedItemsets

Read SPMF frequent-itemset output into a canonical support map. Blank lines and
lines beginning with `#`, `%`, or `@` are metadata, except malformed lines that
contain `#SUP:`. Duplicate itemsets are retained as diagnostics. Invalid data
throws `ArgumentError` with the 1-based line number.
"""
function parse_itemsets(input::IO)
    itemsets = SupportMap()
    duplicates = Tuple{Itemset,Int}[]
    for (line_number, raw_line) in enumerate(eachline(input))
        line = strip(raw_line)
        isempty(line) && continue
        if first(line) in ('#', '%', '@') && !occursin("#SUP:", line)
            continue
        end
        match_result = match(r"^(.*?)\s+#SUP:\s*(\d+)\s*$", line)
        match_result === nothing &&
            throw(ArgumentError("invalid SPMF itemset output at line $line_number: expected 'items #SUP: count'"))
        item_text = strip(match_result.captures[1])
        support = tryparse(Int, match_result.captures[2])
        support !== nothing && support > 0 ||
            throw(ArgumentError("invalid support at line $line_number: $(repr(match_result.captures[2]))"))
        tokens = split(item_text)
        isempty(tokens) && throw(ArgumentError("empty itemset at line $line_number"))
        items = Int[]
        for token in tokens
            item = tryparse(Int, token)
            item !== nothing && item >= 0 ||
                throw(ArgumentError("invalid item ID at line $line_number: $(repr(token))"))
            push!(items, item)
        end
        length(unique(items)) == length(items) ||
            throw(ArgumentError("duplicate item ID in itemset at line $line_number"))
        key = Tuple(sort!(items))
        if haskey(itemsets, key)
            push!(duplicates, (key, line_number))
        else
            itemsets[key] = support
        end
    end
    return ParsedItemsets(itemsets, duplicates)
end

"""
    compare_itemsets(reference, candidate) -> ItemsetComparison

Compare complete canonical itemset maps. The match rate is the number of
itemsets present with equal support in both maps divided by the size of their
union; two empty maps have rate 1.0. A duplicate in either input makes the
comparison fail even if its first occurrence matches.
"""
function compare_itemsets(reference::ParsedItemsets, candidate::ParsedItemsets)
    reference_keys = Set(keys(reference.itemsets))
    candidate_keys = Set(keys(candidate.itemsets))
    missing = sort!(collect(setdiff(reference_keys, candidate_keys)))
    extra = sort!(collect(setdiff(candidate_keys, reference_keys)))
    shared = intersect(reference_keys, candidate_keys)
    support_mismatches = Tuple{Itemset,Int,Int}[]
    for key in shared
        reference_support = reference.itemsets[key]
        candidate_support = candidate.itemsets[key]
        reference_support == candidate_support ||
            push!(support_mismatches, (key, reference_support, candidate_support))
    end
    sort!(support_mismatches)
    matching_count = length(shared) - length(support_mismatches)
    union_count = length(union(reference_keys, candidate_keys))
    match_rate = union_count == 0 ? 1.0 : matching_count / union_count
    matches = isempty(missing) && isempty(extra) && isempty(support_mismatches) &&
              isempty(reference.duplicates) && isempty(candidate.duplicates)
    return ItemsetComparison(
        missing,
        extra,
        support_mismatches,
        reference.duplicates,
        candidate.duplicates,
        match_rate,
        matches,
    )
end

"""Write the complete comparison diagnostics in deterministic order."""
function print_comparison(output::IO, result::ItemsetComparison)
    println(output, "Missing from candidate: ", isempty(result.missing) ? "none" : join(result.missing, ", "))
    println(output, "Extra in candidate: ", isempty(result.extra) ? "none" : join(result.extra, ", "))
    println(output, "Support mismatches: ", isempty(result.support_mismatches) ? "none" : join(result.support_mismatches, ", "))
    println(output, "Reference duplicates: ", isempty(result.reference_duplicates) ? "none" : join(result.reference_duplicates, ", "))
    println(output, "Candidate duplicates: ", isempty(result.candidate_duplicates) ? "none" : join(result.candidate_duplicates, ", "))
    println(output, "Exact-map match rate: ", result.match_rate * 100, "%")
    return nothing
end

function spmf_main(arguments::AbstractVector{<:AbstractString})
    length(arguments) == 2 ||
        throw(ArgumentError("usage: julia --project=. tools/spmf/compare.jl REFERENCE OUTPUT"))
    reference = open(parse_itemsets, arguments[1])
    candidate = open(parse_itemsets, arguments[2])
    result = compare_itemsets(reference, candidate)
    print_comparison(stdout, result)
    return isempty(result.missing) && isempty(result.extra) &&
           isempty(result.support_mismatches) && isempty(result.reference_duplicates) &&
           isempty(result.candidate_duplicates) ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(spmf_main(ARGS))
    catch error
        showerror(stderr, error)
        println(stderr)
        exit(2)
    end
end
