const REPO_ROOT = dirname(@__DIR__)
const MEASURE_SCRIPT = joinpath(@__DIR__, "measure.jl")
const WORKER_SCRIPT = joinpath(@__DIR__, "eclat_worker.jl")
const RESULT_FIELDS = split(strip(read(joinpath(@__DIR__, "result-fields.txt"), String)), ',')
const VARIANTS = (:baseline, :optimized, :spmf)

Base.@kwdef struct Series
    dataset::String
    minsup::Vector{Float64}
end

"""
One experiment: which variants run on which thresholds, how often, and with
which tools. `project` is the checkout whose `ItemsetMining` is measured, so a
run can time another revision with this repository's harness.
"""
Base.@kwdef struct RunConfig
    name::String
    variants::Vector{Symbol}
    repeats::Int
    timeout_seconds::Float64
    series::Vector{Series}
    project::String = REPO_ROOT
    keep_outputs::Bool = false
    julia_threads::Int = 1
    java::String = "java"
    java_options::Vector{String} = String[]
    spmf_jar::String = joinpath(REPO_ROOT, "tools", "spmf", "spmf.jar")
    spmf_version::String = ""
    table::Dict{String,Any} = Dict{String,Any}()
end

load_run_config(path::AbstractString) = parse_run_config(TOML.parsefile(path))

"""
    parse_run_config(table) -> RunConfig

Validate a run configuration. Relative `project`, `spmf_jar`, and `java` paths
resolve against the repository root. Throws `ArgumentError` naming the field.
"""
function parse_run_config(table::AbstractDict)
    get_field(key, type, default=nothing) = begin
        value = get(table, key, default)
        value isa type || throw(ArgumentError("run config: $key must be a $type, got $(repr(value))"))
        value
    end
    variants = Symbol.(get_field("variants", Vector))
    !isempty(variants) && allunique(variants) && all(in(VARIANTS), variants) ||
        throw(ArgumentError("run config: variants must be distinct values of $VARIANTS, got $variants"))
    repeats = get_field("repeats", Integer)
    repeats >= 1 || throw(ArgumentError("run config: repeats must be at least 1, got $repeats"))
    timeout = get_field("timeout_seconds", Real)
    timeout > 0 || throw(ArgumentError("run config: timeout_seconds must be positive, got $timeout"))
    threads = get_field("julia_threads", Integer, 1)
    threads >= 1 || throw(ArgumentError("run config: julia_threads must be at least 1, got $threads"))
    series = Series[]
    for item in get_field("series", Vector)
        dataset = get(item, "dataset", nothing)
        dataset isa String || throw(ArgumentError("run config: every series needs a dataset name"))
        minsup = get(item, "minsup", Any[])
        !isempty(minsup) && all(m -> m isa AbstractFloat && 0 < m <= 1, minsup) && allunique(minsup) ||
            throw(ArgumentError("run config: series $dataset needs distinct minsup fractions in (0, 1], got $minsup"))
        push!(series, Series(dataset, Float64.(minsup)))
    end
    isempty(series) && throw(ArgumentError("run config: series is empty"))
    resolve(path) = isabspath(path) ? path : normpath(joinpath(REPO_ROOT, path))
    java = get_field("java", String, "java")
    return RunConfig(; name=get_field("name", String), variants, repeats=Int(repeats),
        timeout_seconds=Float64(timeout), series, julia_threads=Int(threads),
        project=resolve(get_field("project", String, ".")),
        keep_outputs=get_field("keep_outputs", Bool, false),
        java=occursin(r"[/\\]", java) ? resolve(java) : java,
        java_options=String.(get_field("java_options", Vector, String[])),
        spmf_jar=resolve(get_field("spmf_jar", String, "tools/spmf/spmf.jar")),
        spmf_version=get_field("spmf_version", String, ""),
        table=Dict{String,Any}(table))
end

"""SPMF's support count: `ceil(minsup * N)` in Float64, measured on SPMF v2.66."""
float_support_count(minsup::Float64, n::Integer) = ceil(Int, minsup * n)

"""True when SPMF and `support_threshold` turn `minsup` into the same count."""
threshold_agrees(minsup::Float64, n::Integer) =
    support_threshold(minsup, n) == float_support_count(minsup, n)

Base.@kwdef struct Attempt
    id::String
    entry::DatasetEntry
    minsup::Float64
    minsup_count::Int
    variant::Symbol
    repeat::Int
end

"""
    plan_attempts(config, manifest) -> Vector{Attempt}

Order attempts by dataset, then by decreasing minsup, then repeat, then variant.
Interleaving variants spreads machine drift evenly across them, and decreasing
minsup lets a timeout skip the lower, slower thresholds. Throws `ArgumentError`
for an unknown dataset or a threshold SPMF would round to another count.
"""
function plan_attempts(config::RunConfig, manifest::AbstractDict{String,DatasetEntry})
    attempts = Attempt[]
    for series in config.series
        haskey(manifest, series.dataset) ||
            throw(ArgumentError("run config: unknown dataset $(repr(series.dataset))"))
        entry = manifest[series.dataset]
        n = entry.stats.transactions
        for minsup in sort(series.minsup; rev=true)
            threshold_agrees(minsup, n) || throw(ArgumentError(
                "dataset $(entry.name): minsup $minsup is $(support_threshold(minsup, n)) transactions " *
                "in decimal but $(float_support_count(minsup, n)) in Float64 as SPMF computes it; choose another value"))
            for repeat in 1:config.repeats, variant in config.variants
                push!(attempts, Attempt(; id="$(entry.name)-m$(minsup)-r$(repeat)-$(variant)", entry,
                    minsup, minsup_count=support_threshold(minsup, n), variant, repeat))
            end
        end
    end
    return attempts
end

function measured_command(attempt::Attempt, config::RunConfig, input::String, output::String, report::String)
    if attempt.variant == :spmf
        return `$(config.java) $(config.java_options) -jar $(config.spmf_jar) run Eclat $input $output $(attempt.minsup)`
    end
    return `$(Base.julia_cmd()) --startup-file=no --threads=$(config.julia_threads) --project=$(config.project)
            $WORKER_SCRIPT --variant $(attempt.variant) --minsup $(attempt.minsup)
            --output $output --report $report $input`
end

"""Parse the statistics block SPMF prints after a run."""
function parse_spmf_stats(text::AbstractString)
    grab(pattern) = begin
        m = match(pattern, text)
        m === nothing && throw(ArgumentError("SPMF output lacks $(pattern.pattern)"))
        parse(Int, m[1])
    end
    return (transactions=grab(r"Transactions count from database : (\d+)"),
            itemsets=grab(r"Frequent itemsets count : (\d+)"),
            total_seconds=grab(r"Total time ~ (\d+) ms") / 1000)
end

"""Count itemset lines, skipping SPMF's `@` metadata lines."""
count_itemset_lines(path::AbstractString) =
    count(line -> !isempty(line) && !startswith(line, '@'), eachline(path))

function csv_field(value)
    value === missing && return ""
    text = string(value)
    return occursin(r"[\",\r\n]", text) ? "\"" * replace(text, "\"" => "\"\"") * "\"" : text
end

"""Join a row in `RESULT_FIELDS` order. Throws `ArgumentError` for a missing field."""
function csv_line(row::AbstractDict)
    for field in RESULT_FIELDS
        haskey(row, field) || throw(ArgumentError("result row lacks field $field"))
    end
    return join((csv_field(row[field]) for field in RESULT_FIELDS), ',')
end

function code_revision(project::AbstractString)
    try
        revision = readchomp(`git -C $project rev-parse HEAD`)
        dirty = !isempty(readchomp(`git -C $project status --porcelain --untracked-files=no`))
        return dirty ? revision * "-dirty" : revision
    catch
        # A project outside Git cannot name its code, so its rows say so.
        return "unknown"
    end
end

first_line(text::AbstractString) = String(rstrip(first(split(text, '\n')), '\r'))

function java_version(java::AbstractString)
    buffer = IOBuffer()
    run(pipeline(`$java -version`; stdout=buffer, stderr=buffer))
    return first_line(String(take!(buffer)))
end

"""Facts shared by every row of a run. Throws `ArgumentError` when SPMF cannot run."""
function capture_environment(config::RunConfig)
    os_release = Sys.iswindows() ? string(Sys.windows_version()) : readchomp(`uname -r`)
    env = Dict{String,Any}(
        "julia_version" => string(VERSION),
        "os" => "$(Sys.KERNEL) $os_release $(Sys.MACHINE)",
        "cpu" => strip(Sys.cpu_info()[1].model),
        "logical_cpus" => Sys.CPU_THREADS,
        "total_memory_bytes" => Int(Sys.total_memory()),
        "code_revision" => code_revision(config.project),
        "harness_revision" => code_revision(REPO_ROOT),
        "java_version" => "",
        "reference_version" => "",
    )
    if :spmf in config.variants
        isfile(config.spmf_jar) || throw(ArgumentError("SPMF JAR not found at $(config.spmf_jar); see tools/spmf/README.md"))
        env["java_version"] = try
            java_version(config.java)
        catch err
            throw(ArgumentError("cannot run $(config.java) -version: $(sprint(showerror, err))"))
        end
        env["spmf_jar_sha256"] = file_sha256(config.spmf_jar)
        env["reference_version"] = strip("SPMF $(config.spmf_version) jar-sha256=$(env["spmf_jar_sha256"])")
    end
    return env
end
