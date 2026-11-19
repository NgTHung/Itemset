"""
Merge two ascending tid-lists, as the baseline's `intersect_tidlists` does, and
return the intersection. This copy exists because experiments use only the
public API, and a model of the baseline's work needs the lists to carry on.
"""
function merge_intersection(a::Vector{Int}, b::Vector{Int})
    result = Int[]
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
    join_work(transactions, minsup_count) -> NamedTuple

Run the baseline's Bottom-Up search (Zaki 2000, Sec. 4.2) on `transactions` and
count its work instead of keeping its output. The fields are the number of
frequent `itemsets`, of `frequent_items` at the root, of tid-list `joins`
attempted, of `successful_joins` that reached `minsup_count`, and of
`merged_elements`, the sum of |a| + |b| over all joins. The baseline's cost
model, O(L + m log m + C N) in `docs/eclat.md`, charges each join that sum.
Every itemset longer than one item is the result of exactly one successful join,
so `itemsets == frequent_items + successful_joins`.

Throws `ArgumentError` for a count below 1 or an invalid transaction.
"""
function join_work(transactions, minsup_count::Integer)
    minsup_count >= 1 || throw(ArgumentError("minsup count must be at least 1, got $minsup_count"))
    tidlists = Dict{Int,Vector{Int}}()
    for (tid, transaction) in enumerate(transactions)
        for item in canonical_transaction(transaction)
            push!(get!(Vector{Int}, tidlists, item), tid)
        end
    end
    root = [item => tids for (item, tids) in sort!(collect(tidlists); by=first) if length(tids) >= minsup_count]
    counts = Dict{Symbol,Int}(:itemsets => 0, :joins => 0, :successful_joins => 0, :merged_elements => 0)
    search_class!(root, Int(minsup_count), counts)
    return (itemsets=counts[:itemsets], frequent_items=length(root), joins=counts[:joins],
            successful_joins=counts[:successful_joins], merged_elements=counts[:merged_elements])
end

function search_class!(class::Vector{Pair{Int,Vector{Int}}}, minsup::Int, counts::Dict{Symbol,Int})
    for i in eachindex(class)
        counts[:itemsets] += 1
        a_set = last(class[i])
        child = Pair{Int,Vector{Int}}[]
        for j in i+1:lastindex(class)
            b_set = last(class[j])
            joined = merge_intersection(a_set, b_set)
            counts[:joins] += 1
            counts[:merged_elements] += length(a_set) + length(b_set)
            if length(joined) >= minsup
                counts[:successful_joins] += 1
                push!(child, first(class[j]) => joined)
            end
        end
        isempty(child) || search_class!(child, minsup, counts)
    end
    return counts
end

"""
    join_work_rows(config, manifest, data_dir) -> Vector{NamedTuple}

Count the baseline's work at every threshold of `config`'s series, decreasing
within each dataset, on the files `prepare_dataset` verifies in `data_dir`.
Throws `ArgumentError` for a dataset the manifest lacks.
"""
function join_work_rows(config::RunConfig, manifest::AbstractDict{String,DatasetEntry}, data_dir::AbstractString)
    rows = NamedTuple[]
    for series in config.series
        haskey(manifest, series.dataset) || throw(ArgumentError("unknown dataset $(repr(series.dataset))"))
        entry = manifest[series.dataset]
        transactions = read_transactions(prepare_dataset(entry, data_dir))
        for minsup in sort(series.minsup; rev=true)
            count = support_threshold(minsup, length(transactions))
            work = join_work(transactions, count)
            push!(rows, (dataset=series.dataset, minsup_relative=string(minsup), minsup_count=count, work...))
        end
    end
    return rows
end

const JOIN_WORK_FIELDS = ["dataset", "minsup_relative", "minsup_count", "itemsets", "frequent_items", "joins",
                          "successful_joins", "merged_elements"]

"""Write the rows of `join_work_rows` as CSV."""
function write_join_work(path::AbstractString, rows)
    open(path, "w") do io
        println(io, join(JOIN_WORK_FIELDS, ','))
        for row in rows
            println(io, join((csv_field(getfield(row, Symbol(f))) for f in JOIN_WORK_FIELDS), ','))
        end
    end
    return nothing
end
