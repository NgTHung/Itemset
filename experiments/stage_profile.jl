using Profile: Profile
using Statistics: median

"""
Groups of profile frames, in the order the report names them. A sample goes to the first group
whose pattern matches its innermost frame that any pattern matches, so a join called from the
search counts as a join. `tests/stage_profile.jl` checks that every pattern matches a function
the package defines, so renaming one fails the test instead of moving its samples to `other`.
"""
const STAGE_GROUPS = [
    "read" => r"^read_transactions",
    "item counts" => r"^(count_items|frequent_items_by_support)",
    "root bitsets" => r"^(bitset_tidsets|bitset_class)",
    "pair counts" => r"^(pair_filter|count_pairs|may_be_frequent)",
    "block counts" => r"^(BlockCounts|class_filter|block_bound)",
    "bitset joins" => r"^intersect_bitsets",
    "list joins" => r"^intersect_lists",
    "bitset to list" => r"^bitset_tids",
    "search" => r"^(join_members|eclat_search|search_children|prefer_lists|push_node)",
    "expand" => r"^(expand_nodes|write_subsets|write_nodes)",
    "canonical check" => r"^(canonical_database|is_canonical)",
    "sort" => r"^(lexicographic_order|order_equal_keys|prefix_key|checked_order|itemset_isless)",
    "format" => r"^(print_packed|put_digits|put_items|reserve_line|write_itemset)",
]

# The profiler also samples threads that only wait. They carry no work, so they leave the shares.
const IDLE_FRAME = r"^(Zw|Nt)Wait|SleepConditionVariable|^pthread_cond|^uv_cond|futex|^jl_task_get_next|^poptask$"

"""
    stage_group(frames) -> Union{Nothing,String}

The group of one profile sample, whose `frames` run from the innermost call outward. `nothing`
for a sample of an idle thread, and `"other"` when no frame belongs to a group.
"""
function stage_group(frames)
    any(frame -> occursin(IDLE_FRAME, String(frame)), frames) && return nothing
    for frame in frames
        name = String(frame)
        for (label, pattern) in STAGE_GROUPS
            occursin(pattern, name) && return label
        end
    end
    return "other"
end

"""
    stage_shares(stacks) -> Dict{String,Float64}

The fraction of the non-idle samples in each group of `STAGE_GROUPS`, plus `"other"`. Every
group is present, and all fractions are 0 when no sample remains.
"""
function stage_shares(stacks)
    counts = Dict{String,Int}(label => 0 for label in [first.(STAGE_GROUPS); "other"])
    for stack in stacks
        group = stage_group(stack)
        group === nothing || (counts[group] += 1)
    end
    total = sum(values(counts))
    return Dict(label => (total == 0 ? 0.0 : count / total) for (label, count) in counts)
end

"""Run `work()` under the sampling profiler and return its samples as stacks of function names, innermost first."""
function profile_stacks(work)
    Profile.clear()
    Profile.init(n=10^7, delay=0.0005)
    Profile.@profile work()
    data = Profile.fetch(include_meta=false)
    names = Profile.getdict(data)
    stacks = Vector{Vector{Symbol}}()
    current = Symbol[]
    for ip in data
        if ip == 0
            isempty(current) || push!(stacks, current)
            current = Symbol[]
        else
            for frame in get(names, ip, Base.StackTraces.StackFrame[])
                push!(current, frame.func)
            end
        end
    end
    isempty(current) || push!(stacks, current)
    Profile.clear()
    return stacks
end

"""
One CLI-style pass over `path`: read, `mine_packed` with the optimized variant, and write to
`devnull`. Returns the seconds and the garbage-collection seconds of each of the three stages,
and the number of itemsets and transactions.
"""
function stage_pass(path::AbstractString, minsup::Integer)
    clock() = (time_ns(), Base.gc_time_ns())
    t0, g0 = clock()
    transactions = read_transactions(path)
    t1, g1 = clock()
    packed = mine_packed(transactions; minsup, variant=:optimized)
    t2, g2 = clock()
    write_itemsets(devnull, packed)
    t3, g3 = clock()
    seconds = [t1 - t0, t2 - t1, t3 - t2] ./ 1e9
    gc = [g1 - g0, g2 - g1, g3 - g2] ./ 1e9
    return (; seconds, gc, itemsets=length(packed), transactions=length(transactions))
end

const STAGE_SHARE_LABELS = [first.(STAGE_GROUPS); "other"]
stage_field(label) = "share_" * replace(label, ' ' => '_')

const STAGE_PROFILE_FIELDS = ["dataset", "minsup_relative", "minsup_count", "transactions", "itemsets",
                              "read_seconds", "mine_seconds", "write_seconds", "gc_seconds", "samples",
                              stage_field.(STAGE_SHARE_LABELS)...]

"""
    stage_profile_rows(config, manifest, data_dir; repeats=5) -> Vector{NamedTuple}

For every threshold of `config`'s series, decreasing within each dataset, time the read, mine,
and write stages of the optimized CLI path on the files `prepare_dataset` verifies in `data_dir`.
The seconds are medians of `repeats` warm passes after one warm-up pass, `gc_seconds` is the
median garbage-collection time of a whole pass, and the `share_*` fields are the fractions of the
profiler's non-idle samples over `repeats` more passes. `samples` is their number, and shares are
0 when it is 0, as on a database too small to sample. The variants and repeats of `config` do not
apply. Throws `ArgumentError` for a dataset the manifest lacks or fewer than one repeat.
"""
function stage_profile_rows(config::RunConfig, manifest::AbstractDict{String,DatasetEntry}, data_dir::AbstractString;
                            repeats::Integer=5)
    repeats >= 1 || throw(ArgumentError("repeats must be at least 1, got $repeats"))
    rows = NamedTuple[]
    for series in config.series
        haskey(manifest, series.dataset) || throw(ArgumentError("unknown dataset $(repr(series.dataset))"))
        path = prepare_dataset(manifest[series.dataset], data_dir)
        database_size = length(read_transactions(path))
        for minsup in sort(series.minsup; rev=true)
            threshold = support_threshold(minsup, database_size)
            stage_pass(path, threshold)
            passes = [stage_pass(path, threshold) for _ in 1:repeats]
            stacks = profile_stacks(() -> foreach(_ -> stage_pass(path, threshold), 1:repeats))
            shares = stage_shares(stacks)
            seconds = [median(p.seconds[i] for p in passes) for i in 1:3]
            push!(rows, (; dataset=series.dataset, minsup_relative=string(minsup), minsup_count=threshold,
                         transactions=first(passes).transactions, itemsets=first(passes).itemsets,
                         read_seconds=seconds[1], mine_seconds=seconds[2], write_seconds=seconds[3],
                         gc_seconds=median(sum(p.gc) for p in passes),
                         samples=count(s -> stage_group(s) !== nothing, stacks),
                         (Symbol(stage_field(label)) => shares[label] for label in STAGE_SHARE_LABELS)...))
        end
    end
    return rows
end

"""Write the rows of `stage_profile_rows` as CSV."""
function write_stage_profile(path::AbstractString, rows)
    open(path, "w") do io
        println(io, join(STAGE_PROFILE_FIELDS, ','))
        for row in rows
            println(io, join((csv_field(getfield(row, Symbol(f))) for f in STAGE_PROFILE_FIELDS), ','))
        end
    end
    return nothing
end
