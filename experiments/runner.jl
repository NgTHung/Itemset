"""
    run_experiment(config, manifest; data_dir, out_dir) -> Vector{Dict{String,String}}

Run every planned attempt in a fresh process and append its rows to
`out_dir/runs.csv` as soon as it finishes, so an interrupted run keeps its
evidence. Each attempt keeps its command, stdout, stderr, and reports under
`out_dir/attempts/<id>/`. A failed, timed-out, or skipped attempt becomes a row
with that status, never a zero. After a timeout, later attempts of the same
dataset and variant are skipped, because lower thresholds only add itemsets.
"""
function run_experiment(config::RunConfig, manifest::AbstractDict{String,DatasetEntry};
                        data_dir::AbstractString, out_dir::AbstractString)
    attempts = plan_attempts(config, manifest)
    env = capture_environment(config)
    mkpath(joinpath(out_dir, "attempts"))
    open(io -> TOML.print(io, env), joinpath(out_dir, "environment.toml"), "w")
    open(io -> TOML.print(io, config.table), joinpath(out_dir, "config.toml"), "w")
    inputs = Dict(name => prepare_dataset(manifest[name], data_dir)
                  for name in unique(a.entry.name for a in attempts))
    run_id = basename(normpath(out_dir))
    timed_out = Dict{Tuple{String,Symbol},Float64}()
    rows = Dict{String,String}[]
    open(joinpath(out_dir, "runs.csv"), "w") do csv
        println(csv, join(RESULT_FIELDS, ','))
        for attempt in attempts
            base = base_row(attempt, config, env, run_id)
            key = (attempt.entry.name, attempt.variant)
            new_rows = if haskey(timed_out, key)
                [merge(base, Dict("timing_scope" => "process", "status" => "skipped",
                    "error" => "an earlier attempt at minsup $(timed_out[key]) timed out"))]
            else
                run_attempt(attempt, config, inputs[attempt.entry.name],
                            joinpath(out_dir, "attempts", attempt.id), base)
            end
            any(r -> r["status"] == "timeout", new_rows) && (timed_out[key] = attempt.minsup)
            for row in new_rows
                println(csv, csv_line(row))
            end
            flush(csv)
            append!(rows, new_rows)
            println(stderr, attempt.id, ": ", first(new_rows)["status"], " ",
                    first(new_rows)["elapsed_seconds"])
        end
    end
    return rows
end

function base_row(attempt::Attempt, config::RunConfig, env, run_id)
    stats = attempt.entry.stats
    spmf = attempt.variant == :spmf
    row = Dict{String,String}(field => "" for field in RESULT_FIELDS)
    merge!(row, Dict(
        "run_id" => run_id, "attempt_id" => attempt.id,
        "dataset" => attempt.entry.name, "dataset_version" => attempt.entry.version,
        "input_sha256" => attempt.entry.sha256, "transactions" => string(stats.transactions),
        "items" => string(stats.items), "mean_width" => string(round(mean_width(stats); digits=4)),
        "minsup_relative" => string(attempt.minsup), "minsup_count" => string(attempt.minsup_count),
        "code_revision" => spmf ? "" : env["code_revision"], "variant" => string(attempt.variant),
        "reference_version" => spmf ? env["reference_version"] : "",
        "julia_version" => env["julia_version"], "java_version" => spmf ? env["java_version"] : "",
        "os" => env["os"], "cpu" => env["cpu"], "threads" => spmf ? "" : string(config.julia_threads),
        "seed" => string(DEFAULT_SEED), "repeat" => string(attempt.repeat),
        "timeout_seconds" => string(config.timeout_seconds)))
    return row
end

function run_attempt(attempt::Attempt, config::RunConfig, input::String, dir::String, base)
    mkpath(dir)
    paths = Dict(name => joinpath(dir, name) for name in
                 ("stdout.txt", "stderr.txt", "measure.toml", "worker.toml", "output.txt"))
    command = measured_command(attempt, config, input, paths["output.txt"], paths["worker.toml"])
    wrapper = `$(Base.julia_cmd()) --startup-file=no $MEASURE_SCRIPT --timeout $(config.timeout_seconds)
               --stdout $(paths["stdout.txt"]) --stderr $(paths["stderr.txt"])
               --report $(paths["measure.toml"]) -- $command`
    write(joinpath(dir, "command.txt"), string(command), "\n")
    # The wrapper exits nonzero only for its own bad arguments, which is a harness bug.
    run(wrapper)
    measured = TOML.parsefile(paths["measure.toml"])
    process = merge(base, Dict("command" => strip(string(command), '`'), "timing_scope" => "process",
        "elapsed_seconds" => string(measured["elapsed_seconds"]),
        "peak_rss_bytes" => measured["peak_rss_bytes"] < 0 ? "" : string(measured["peak_rss_bytes"]),
        "memory_tool" => measured["memory_tool"], "status" => measured["status"],
        "warmup_policy" => attempt.variant == :spmf ? "cold-jvm" : "cold-process"))
    rows = if measured["status"] == "timeout"
        [merge(process, Dict("error" => "killed after $(config.timeout_seconds) s"))]
    elseif measured["status"] == "error"
        [merge(process, Dict("error" => last_lines(paths["stderr.txt"])))]
    else
        try
            completed_rows(attempt, process, paths)
        catch err
            # Output that disagrees with the run's own report is a failed
            # attempt, recorded with the reason instead of a number.
            err isa ArgumentError || rethrow()
            [merge(process, Dict("status" => "error", "error" => err.msg))]
        end
    end
    config.keep_outputs || rm(paths["output.txt"]; force=true)
    return rows
end

"""Rows for an attempt whose process exited 0, after checking its output."""
function completed_rows(attempt::Attempt, process, paths)
    n = attempt.entry.stats.transactions
    output_count = count_itemset_lines(paths["output.txt"])
    common = merge(process, Dict("output_count" => string(output_count),
                                 "output_sha256" => file_sha256(paths["output.txt"])))
    if attempt.variant == :spmf
        stats = parse_spmf_stats(read(paths["stdout.txt"], String))
        stats.transactions == n ||
            throw(ArgumentError("SPMF read $(stats.transactions) transactions, expected $n"))
        stats.itemsets == output_count ||
            throw(ArgumentError("SPMF reported $(stats.itemsets) itemsets but wrote $output_count"))
        return [common, merge(common, Dict("timing_scope" => "spmf_total",
                                           "elapsed_seconds" => string(stats.total_seconds)))]
    end
    report = TOML.parsefile(paths["worker.toml"])
    report["transactions"] == n ||
        throw(ArgumentError("worker read $(report["transactions"]) transactions, expected $n"))
    report["minsup_count"] == attempt.minsup_count ||
        throw(ArgumentError("worker used count $(report["minsup_count"]), expected $(attempt.minsup_count)"))
    report["output_count"] == output_count ||
        throw(ArgumentError("worker mined $(report["output_count"]) itemsets but wrote $output_count"))
    warm(scope, seconds) = merge(common, Dict("timing_scope" => scope, "warmup_policy" => "toy-warmup",
                                              "elapsed_seconds" => string(seconds)))
    mine_row = merge(warm("mine", report["mine_seconds"]), Dict(
        "allocated_bytes" => string(report["mine_allocated_bytes"]),
        "gc_seconds" => string(report["mine_gc_seconds"])))
    return [common, warm("read", report["read_seconds"]), mine_row, warm("write", report["write_seconds"])]
end

"""The last nonempty stderr lines, enough to name an exception without its stack trace."""
function last_lines(path::AbstractString; limit::Int=400)
    lines = filter(!isempty, strip.(readlines(path)))
    isempty(lines) && return "process exited nonzero without stderr"
    # Julia prints the exception message first and its stack trace after, so
    # the first ERROR line names the failure.
    index = findfirst(l -> startswith(l, "ERROR"), lines)
    text = index === nothing ? join(last(lines, 3), " | ") : lines[index]
    return first(text, limit)
end
