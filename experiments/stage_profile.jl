using Profile: Profile

"""
Groups of package functions, in the order the report names them. A sample goes to the group
of the innermost frame that any group lists, so a join called from the search counts as a join.
`tests/stage_profile.jl` checks every listed name against the functions the package defines, so
renaming one fails the test instead of moving its samples to `other`.
"""
const STAGE_GROUPS = [
    "read" => ["read_transactions"],
    "item counts" => ["count_items", "frequent_items_by_support"],
    "root bitsets" => ["bitset_tidsets", "bitset_class"],
    "pair counts" => ["pair_filter", "count_pairs", "may_be_frequent"],
    "block counts" => ["BlockCounts", "class_filter", "block_bound"],
    "bitset joins" => ["intersect_bitsets!"],
    "list joins" => ["intersect_lists!"],
    "bitset to list" => ["bitset_tids!"],
    "search" => ["join_members!", "eclat_search!", "search_children!", "prefer_lists", "push_node!"],
    "expand" => ["expand_nodes", "write_subsets!", "write_nodes!"],
    "canonical check" => ["canonical_database", "is_canonical"],
    "sort" => ["lexicographic_order", "order_equal_keys!", "prefix_key", "checked_order", "itemset_isless"],
    "format" => ["print_packed", "put_digits!", "put_items!", "reserve_line!", "write_itemset!"],
]

const FRAME_GROUP = Dict(Symbol(name) => label for (label, names) in STAGE_GROUPS for name in names)
const STAGE_SHARE_LABELS = [first.(STAGE_GROUPS); "other"]

"""
    stage_group(frames) -> String

The group of one profile sample, whose `frames` run from the innermost call outward, or
`"other"` when no frame belongs to a group.
"""
function stage_group(frames)
    for frame in frames
        group = get(FRAME_GROUP, frame, nothing)
        group === nothing || return group
    end
    return "other"
end

"""The number of samples of `stacks` in each group of `STAGE_GROUPS` and in `"other"`."""
function stage_counts(stacks)
    counts = Dict{String,Int}(label => 0 for label in STAGE_SHARE_LABELS)
    for stack in stacks
        counts[stage_group(stack)] += 1
    end
    return counts
end

"""The fraction of the samples in each group of `counts`, which are all 0 when there is no sample."""
function stage_shares(counts::AbstractDict{String,Int})
    total = sum(values(counts))
    return Dict(label => (total == 0 ? 0.0 : count / total) for (label, count) in counts)
end

"""
    thread_blocks(data, thread) -> Vector{Vector{UInt}}

The stacks of the samples that thread `thread` took, from `Profile.fetch(include_meta=true)`.
Each sample is a block of instruction pointers, innermost first, then the thread id, task id,
clock, and sleep state, then two zeros. Samples of other threads, such as one that only waits,
are not returned, and a sample of `thread` that waits inside the run is, because that wait is
part of its cost. No sample gives no block. Throws `ArgumentError` when samples carry no metadata.
"""
function thread_blocks(data, thread::Integer)
    blocks = Vector{Vector{UInt}}()
    isempty(data) && return blocks
    Profile.has_meta(data) || throw(ArgumentError("the profile data carries no thread metadata"))
    first_ip = 1
    for i in eachindex(data)
        Profile.is_block_end(data, i) || continue
        data[i - Profile.META_OFFSET_THREADID] == thread &&
            push!(blocks, data[first_ip:i-Profile.nmeta-2])
        first_ip = i + 1
    end
    return blocks
end

"""
    profile_stacks(work; thread=Threads.threadid()) -> Vector{Vector{Symbol}}

Run `work()` under the sampling profiler and return the samples of `thread` as stacks of
function names, innermost first. The buffer and delay of the profiler stay as the caller set them.
"""
function profile_stacks(work; thread::Integer=Threads.threadid())
    Profile.clear()
    Profile.@profile work()
    data = Profile.fetch(include_meta=true)
    blocks = thread_blocks(data, thread)
    names = Profile.getdict(reduce(vcat, blocks; init=UInt[]))
    stacks = [Symbol[frame.func for ip in block for frame in get(names, ip, Base.StackTraces.StackFrame[])]
              for block in blocks]
    Profile.clear()
    return stacks
end

"""
    with_profiler(f; n=10^7, delay=0.0005)

Run `f()` with a profiler buffer of `n` samples and a sampling delay of `delay` seconds, and
restore the caller's settings afterwards, so a later profile in the same process is unchanged.
"""
function with_profiler(f; n::Integer=10^7, delay::Real=0.0005)
    old_n, old_delay = Profile.init()
    Profile.init(; n, delay)
    try
        return f()
    finally
        Profile.init(; n=old_n, delay=old_delay)
    end
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

stage_field(label) = "share_" * replace(label, ' ' => '_')

const STAGE_PROFILE_FIELDS = ["dataset", "minsup_relative", "minsup_count", "transactions", "itemsets",
                              "read_seconds", "mine_seconds", "write_seconds", "gc_seconds", "samples",
                              stage_field.(STAGE_SHARE_LABELS)...]

median_of(values) = sample_quantile(sort!(collect(Float64, values)), 0.5)

"""
    stage_profile_rows(config, manifest, data_dir; repeats=5) -> Vector{NamedTuple}

For every threshold of `config`'s series, decreasing within each dataset, time the read, mine,
and write stages of the optimized CLI path on the files `prepare_dataset` verifies in `data_dir`.
The seconds are medians of `repeats` warm passes after one warm-up pass, `gc_seconds` is the
median garbage-collection time of a whole pass, and the `share_*` fields are the fractions of
the main thread's profiler samples over `repeats` more passes. `samples` is their number, and
shares are 0 when it is 0, as on a database too small to sample. The variants and repeats of
`config` do not apply. Throws `ArgumentError` for a dataset the manifest lacks or fewer than one repeat.
"""
function stage_profile_rows(config::RunConfig, manifest::AbstractDict{String,DatasetEntry}, data_dir::AbstractString;
                            repeats::Integer=5)
    repeats >= 1 || throw(ArgumentError("repeats must be at least 1, got $repeats"))
    return with_profiler() do
        for_each_point(config, manifest, data_dir) do point
            stage_pass(point.path, point.minsup_count)
            passes = [stage_pass(point.path, point.minsup_count) for _ in 1:repeats]
            counts = stage_counts(profile_stacks(() -> foreach(_ -> stage_pass(point.path, point.minsup_count), 1:repeats)))
            shares = stage_shares(counts)
            seconds = [median_of(p.seconds[i] for p in passes) for i in 1:3]
            (; dataset=point.dataset, minsup_relative=point.minsup_relative, minsup_count=point.minsup_count,
             transactions=first(passes).transactions, itemsets=first(passes).itemsets,
             read_seconds=seconds[1], mine_seconds=seconds[2], write_seconds=seconds[3],
             gc_seconds=median_of(sum(p.gc) for p in passes), samples=sum(values(counts)),
             (Symbol(stage_field(label)) => shares[label] for label in STAGE_SHARE_LABELS)...)
        end
    end
end

"""Write the rows of `stage_profile_rows` as CSV."""
write_stage_profile(path::AbstractString, rows) = write_rows(path, STAGE_PROFILE_FIELDS, rows)
