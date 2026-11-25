using Profile: Profile

"""
Groups of package functions, in the order the report names them. An entry is a function name, or
`name@file.jl` for a name that several files define, such as `may_be_frequent`, so that a sample is
told apart by the file of the method it stops in. A sample goes to the group of the innermost frame
that any group lists, and a sample under `read_transactions` is reading whatever it calls.
The names are internal to the package, which `docs/interface.md` records as the one exception to the
rule that experiments use only the public API. `tests/stage_profile.jl` checks every listed name
against the functions and files the package defines, so renaming one fails the test instead of moving
its samples to `other`.
"""
const STAGE_GROUPS = [
    "read" => ["read_transactions"],
    "item counts" => ["count_items", "frequent_items_by_support"],
    "root bitsets" => ["bitset_tidsets", "bitset_class"],
    "pair counts" => ["pair_filter", "count_pairs", "may_be_frequent@pair_counts.jl"],
    "block counts" => ["BlockCounts", "class_filter", "block_bound", "may_be_frequent@block_counts.jl"],
    "bitset joins" => ["intersect_bitsets!"],
    "list joins" => ["intersect_lists!"],
    "bitset to list" => ["bitset_tids!"],
    "search" => ["join_members!", "eclat_search!", "search_children!", "prefer_lists", "push_node!"],
    "expand" => ["expand_nodes", "write_subsets!", "write_nodes!", "write_itemset!"],
    "canonical check" => ["canonical_database", "is_canonical"],
    "sort" => ["lexicographic_order", "order_equal_keys!", "prefix_key", "checked_order", "itemset_isless"],
    "format" => ["print_packed", "put_digits!", "put_items!", "reserve_line!"],
]

const FRAME_GROUP = Dict{Tuple{Symbol,Symbol},String}(
    (occursin('@', entry) ? (Symbol(first(split(entry, '@'))), Symbol(last(split(entry, '@')))) :
     (Symbol(entry), :*)) => label
    for (label, entries) in STAGE_GROUPS for entry in entries)
const STAGE_SHARE_LABELS = [first.(STAGE_GROUPS); "other"]

frame_group(func::Symbol, file::Symbol) = get(FRAME_GROUP, (func, file), get(FRAME_GROUP, (func, :*), nothing))

"""What one instruction pointer says about a sample: its innermost group, if any, and whether it is inside the reader."""
struct IPInfo
    group::Union{Nothing,String}
    read::Bool
end
Base.:(==)(a::IPInfo, b::IPInfo) = a.group == b.group && a.read == b.read

"""The `IPInfo` of one instruction pointer, from its `frames` as `(function, file)` pairs, innermost first."""
function ip_info(frames)
    group = nothing
    for (func, file) in frames
        group = frame_group(func, file)
        group === nothing || break
    end
    return IPInfo(group, any(frame -> first(frame) === :read_transactions, frames))
end

"""
    block_group(infos) -> String

The group of one sample from the `IPInfo` of its instruction pointers, innermost first: reading when any
pointer is inside `read_transactions`, else the first group any pointer has, else `"other"`.
"""
function block_group(infos)
    found = nothing
    for info in infos
        info.read && return "read"
        found === nothing && (found = info.group)
    end
    return something(found, "other")
end

"""The group of one sample given its `frames`, as `(function, file)` pairs, innermost first."""
stage_group(frames) = block_group((ip_info(frames),))

"""The number of samples in each group of `STAGE_GROUPS` and in `"other"`, counted from the group of each sample."""
function stage_counts(groups)
    counts = Dict{String,Int}(label => 0 for label in STAGE_SHARE_LABELS)
    for group in groups
        counts[group] += 1
    end
    return counts
end

"""The fraction of the samples in each group of `counts`, which are all 0 when there is no sample."""
function stage_shares(counts::AbstractDict{String,Int})
    total = sum(values(counts))
    return Dict(label => (total == 0 ? 0.0 : count / total) for (label, count) in counts)
end

# Thread ids are small integers, while the clock and task fields are large, so a larger value means the
# fields moved and the samples would be cut at the wrong place.
const MAX_THREAD_ID = 65_536

"""
    thread_blocks(data, thread) -> Vector{UnitRange{Int}}

The index ranges, in `data` from `Profile.fetch(include_meta=true)`, of the instruction pointers of the
samples that thread `thread` took. A sample is a block of pointers, innermost first, then the thread id, task
id, clock, and sleep state, then two zeros. Samples of other threads, such as one that only waits, are not
returned, and a sample of `thread` that waits inside the run is, because that wait is part of its cost. No
sample gives no range. Throws `ArgumentError` when samples carry no metadata or a thread id is out of range,
which means the layout of the profiler's buffer changed.
"""
function thread_blocks(data, thread::Integer)
    ranges = UnitRange{Int}[]
    isempty(data) && return ranges
    Profile.has_meta(data) || throw(ArgumentError("the profile data carries no thread metadata"))
    first_ip = 1
    for i in eachindex(data)
        Profile.is_block_end(data, i) || continue
        id = data[i-Profile.META_OFFSET_THREADID]
        1 <= id <= MAX_THREAD_ID ||
            throw(ArgumentError("thread id $id is out of range, so the layout of the profile buffer changed"))
        id == thread && push!(ranges, first_ip:i-Profile.nmeta-2)
        first_ip = i + 1
    end
    return ranges
end

"""
    profile_counts(work; thread=Threads.threadid(), label="") -> Dict{String,Int}

Run `work()` under the sampling profiler and count the samples of `thread` in each group. Each distinct
instruction pointer is looked up once, so memory stays small however long the profile. The buffer and delay
of the profiler stay as the caller set them. Throws `ArgumentError`, naming `label`, when the buffer filled,
because the counts would come from a truncated profile.
"""
function profile_counts(work; thread::Integer=Threads.threadid(), label::AbstractString="")
    Profile.clear()
    Profile.@profile work()
    full = Profile.is_buffer_full()
    data = Profile.fetch(include_meta=true, limitwarn=false)
    if full
        Profile.clear()
        throw(ArgumentError("the profiler buffer filled during $(isempty(label) ? "the run" : label); " *
                            "raise the buffer or lower the repeats"))
    end
    ranges = thread_blocks(data, thread)
    pointers = unique!(UInt[ip for range in ranges for ip in view(data, range)])
    frames = Profile.getdict(pointers)
    info = Dict(ip => ip_info([(frame.func, Symbol(basename(String(frame.file)))) for frame in
                               get(frames, ip, Base.StackTraces.StackFrame[])]) for ip in pointers)
    counts = stage_counts(block_group(info[ip] for ip in view(data, range)) for range in ranges)
    Profile.clear()
    return counts
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

"""The passes to time and to profile: `repeats` when given, else those of `config`. Throws `ArgumentError` below 1."""
function stage_repeats(config::RunConfig, repeats::Union{Nothing,Integer})
    count = something(repeats, config.repeats)
    count >= 1 || throw(ArgumentError("repeats must be at least 1, got $count"))
    return count
end

"""
    stage_profile_rows(config, manifest, data_dir; repeats=nothing) -> Vector{NamedTuple}

For every threshold of `config`'s series, decreasing within each dataset, time the read, mine,
and write stages of the optimized CLI path on the files `prepare_dataset` verifies in `data_dir`.
The seconds are medians of `repeats` warm passes after one warm-up pass, `gc_seconds` is the
median garbage-collection time of a whole pass, and the `share_*` fields are the fractions of
the main thread's profiler samples over `repeats` more passes. `repeats` defaults to the `repeats` of
`config`, and the variants of `config` do not apply. `samples` is the number of samples, and shares
are 0 when it is 0, as on a database too small to sample. Throws `ArgumentError` for a dataset the
manifest lacks, fewer than one repeat, or a profiler buffer that filled.
"""
function stage_profile_rows(config::RunConfig, manifest::AbstractDict{String,DatasetEntry}, data_dir::AbstractString;
                            repeats::Union{Nothing,Integer}=nothing)
    count = stage_repeats(config, repeats)
    return with_profiler() do
        for_each_point(config, manifest, data_dir) do point
            stage_pass(point.path, point.minsup_count)
            passes = [stage_pass(point.path, point.minsup_count) for _ in 1:count]
            counts = profile_counts(() -> foreach(_ -> stage_pass(point.path, point.minsup_count), 1:count);
                                    label="$(point.dataset) at minsup $(point.minsup_relative)")
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
