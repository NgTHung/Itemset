using ItemsetMining

const DuplicateRecord = ItemsetMining.ItemsetRecord

struct ParsedItemsets
    itemsets::SupportMap
    duplicates::Vector{DuplicateRecord}
end

struct ItemsetComparison
    missing::Vector{Itemset}
    extra::Vector{Itemset}
    support_mismatches::Vector{Tuple{Itemset,Int,Int}}
    reference_duplicates::Vector{DuplicateRecord}
    candidate_duplicates::Vector{DuplicateRecord}
    match_rate::Float64
    matches::Bool
end

"""
    parse_itemsets(input) -> ParsedItemsets

Read SPMF frequent-itemset output into a canonical support map that keeps each
itemset's first support. Later occurrences of an itemset go to `duplicates`
with their own support and line. Invalid data throws `ArgumentError` with the
1-based line number, as `read_itemset_records` does.
"""
function parse_itemsets(input::IO)
    itemsets = SupportMap()
    duplicates = DuplicateRecord[]
    for record in read_itemset_records(input)
        if haskey(itemsets, record.itemset)
            push!(duplicates, record)
        else
            itemsets[record.itemset] = record.support
        end
    end
    return ParsedItemsets(itemsets, duplicates)
end

"""
    compare_itemsets(reference, candidate) -> ItemsetComparison

Compare complete canonical itemset maps. The match rate is the number of
itemsets present once with equal support in both maps divided by the size of
their union; two empty maps have rate 1.0. A duplicated itemset never counts as
matching, because its supports are ambiguous, and makes the comparison fail.
"""
function compare_itemsets(reference::ParsedItemsets, candidate::ParsedItemsets)
    reference_keys = Set(keys(reference.itemsets))
    candidate_keys = Set(keys(candidate.itemsets))
    missing = sort!(collect(setdiff(reference_keys, candidate_keys)))
    extra = sort!(collect(setdiff(candidate_keys, reference_keys)))
    shared = intersect(reference_keys, candidate_keys)
    duplicated = Set(d.itemset for d in Iterators.flatten((reference.duplicates, candidate.duplicates)))
    support_mismatches = Tuple{Itemset,Int,Int}[]
    matching_count = 0
    for key in shared
        reference_support = reference.itemsets[key]
        candidate_support = candidate.itemsets[key]
        if reference_support != candidate_support
            push!(support_mismatches, (key, reference_support, candidate_support))
        elseif !(key in duplicated)
            matching_count += 1
        end
    end
    sort!(support_mismatches)
    union_count = length(union(reference_keys, candidate_keys))
    match_rate = union_count == 0 ? 1.0 : matching_count / union_count
    matches = isempty(missing) && isempty(extra) && isempty(support_mismatches) && isempty(duplicated)
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

describe(d::DuplicateRecord) = "$(d.itemset) support $(d.support) at line $(d.line)"

"""Write the complete comparison diagnostics in deterministic order."""
function print_comparison(output::IO, result::ItemsetComparison)
    listing(values) = isempty(values) ? "none" : join(values, ", ")
    println(output, "Missing from candidate: ", listing(result.missing))
    println(output, "Extra in candidate: ", listing(result.extra))
    println(output, "Support mismatches: ", listing(result.support_mismatches))
    println(output, "Reference duplicates: ", listing(describe.(result.reference_duplicates)))
    println(output, "Candidate duplicates: ", listing(describe.(result.candidate_duplicates)))
    println(output, "Exact-map match rate: ", result.match_rate * 100, "%")
    return nothing
end

"""
    spmf_main(arguments; out=stdout, err=stderr) -> Int

Compare the REFERENCE and OUTPUT files named in `arguments` and return the
exit code: 0 for equal maps, 1 for any difference, 2 when either file is
malformed. A wrong argument count throws `ArgumentError`, and an unreadable
file throws its I/O error, so the script reports them as setup errors.
"""
function spmf_main(arguments::AbstractVector{<:AbstractString}; out::IO=stdout, err::IO=stderr)
    length(arguments) == 2 ||
        throw(ArgumentError("usage: julia --project=. tools/spmf/compare.jl REFERENCE OUTPUT"))
    parsed = ParsedItemsets[]
    for path in arguments
        try
            push!(parsed, open(parse_itemsets, path))
        catch error
            # Only parse errors mean malformed output; I/O errors must stay setup errors.
            error isa ArgumentError || rethrow()
            println(err, path, ": ", sprint(showerror, error))
            return 2
        end
    end
    result = compare_itemsets(parsed[1], parsed[2])
    print_comparison(out, result)
    return result.matches ? 0 : 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    code = try
        spmf_main(ARGS)
    catch error
        # Exit 3 keeps setup errors apart from the 1 that means a real difference.
        showerror(stderr, error)
        println(stderr)
        3
    end
    exit(code)
end
