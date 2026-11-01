"""
    run_experiment(config, manifest; data_dir, out_dir) -> Vector{Dict{String,String}}

Run every planned attempt in a fresh process and append its rows to
`out_dir/runs.csv` as soon as it finishes, so an interrupted run keeps its
evidence. Each attempt keeps its command, stdout, stderr, and reports under
`out_dir/attempts/<id>/`. A failed, timed-out, or skipped attempt becomes a row
with that status, never a zero. `skip_after_timeout` controls optional pilot
skipping; required series attempt every point and repeat.
"""
function run_experiment(config::RunConfig, manifest::AbstractDict{String,DatasetEntry};
                        data_dir::AbstractString, out_dir::AbstractString)
    attempts = plan_attempts(config, manifest)
    env = capture_environment(config)
    mkpath(joinpath(out_dir, "attempts"))
    open(io -> TOML.print(io, env), joinpath(out_dir, "environment.toml"), "w")
    open(io -> TOML.print(io, config.table), joinpath(out_dir, "config.toml"), "w")
    archive_sources(config, out_dir)
    inputs = Dict(name => prepare_dataset(manifest[name], data_dir)
                  for name in unique(a.entry.name for a in attempts))
    run_id = basename(normpath(out_dir))
    timed_out = Dict{Tuple{String,Symbol},Float64}()
    rows = Dict{String,String}[]
    references = Dict{Tuple{String,Int},String}()
    open(joinpath(out_dir, "runs.csv"), "w") do csv
        println(csv, join(RESULT_FIELDS, ','))
        for attempt in attempts
            base = base_row(attempt, config, env, run_id)
            key = (attempt.entry.name, attempt.variant)
            reference() = get!(references, (attempt.entry.name, attempt.minsup_count)) do
                prepare_reference(attempt, config, inputs[attempt.entry.name],
                    joinpath(out_dir, "references", "$(attempt.entry.name)-c$(attempt.minsup_count)"))
            end
            new_rows = if config.skip_after_timeout && haskey(timed_out, key)
                [merge(base, Dict("timing_scope" => "process", "status" => "skipped",
                    "error" => "an earlier attempt at minsup $(timed_out[key]) timed out"))]
            else
                run_attempt(attempt, config, inputs[attempt.entry.name],
                            joinpath(out_dir, "attempts", attempt.id), base; reference)
            end
            any(r -> r["status"] == "timeout", new_rows) && (timed_out[key] = attempt.minsup)
            for row in new_rows
                println(csv, csv_line(row))
            end
            flush(csv)
            append!(rows, new_rows)
            write_summary(rows, joinpath(out_dir, "summary.csv"))
            GC.gc()
            println(stderr, attempt.id, ": ", first(new_rows)["status"], " ",
                    first(new_rows)["elapsed_seconds"])
        end
    end
    return rows
end

function base_row(attempt::Attempt, config::RunConfig, env, run_id)
    stats = attempt.entry.stats
    spmf = attempt.variant in REFERENCE_VARIANTS
    row = Dict{String,String}(field => "" for field in RESULT_FIELDS)
    merge!(row, Dict(
        "run_id" => run_id, "attempt_id" => attempt.id,
        "dataset" => attempt.entry.name, "dataset_version" => attempt.entry.version,
        "input_sha256" => attempt.entry.sha256, "transactions" => string(stats.transactions),
        "items" => string(stats.items), "mean_width" => string(round(mean_width(stats); digits=4)),
        "minsup_relative" => string(attempt.minsup), "minsup_count" => string(attempt.minsup_count),
        "code_revision" => spmf ? "" : env["code_revision"], "variant" => string(attempt.variant),
        "stage" => config.stage, "mode" => string(config.mode), "correctness_status" => "not_checked",
        "reference_version" => spmf ? env["reference_version"] : "",
        "julia_version" => env["julia_version"], "java_version" => spmf ? env["java_version"] : "",
        "os" => env["os"], "cpu" => env["cpu"], "threads" => spmf ? "" : string(config.julia_threads),
        "seed" => string(DEFAULT_SEED), "repeat" => string(attempt.repeat),
        "timeout_seconds" => string(config.timeout_seconds)))
    return row
end

function run_attempt(attempt::Attempt, config::RunConfig, input::String, dir::String, base;
                     reference=() -> throw(ArgumentError("no SPMF reference supplied")))
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
        "warmup_policy" => attempt.variant in REFERENCE_VARIANTS ? "cold-jvm" :
                           config.mode == :warm ? "warm-worker" : "cold-process"))
    rows = if measured["status"] == "timeout"
        [merge(process, Dict("error" => "killed after $(config.timeout_seconds) s"))]
    elseif measured["status"] == "error"
        [merge(process, Dict("error" => last_lines(paths["stderr.txt"])))]
    else
        try
            completed = completed_rows(attempt, process, paths)
            verification = config.verify_outputs ?
                verify_output(reference(), paths["output.txt"], joinpath(dir, "comparison.toml")) :
                Dict("correctness_status" => "unverified")
            for row in completed
                merge!(row, verification)
                if row["correctness_status"] == "failed"
                    merge!(row, Dict("status" => "error", "error" => "exact-map comparison failed; see comparison.toml"))
                end
            end
            completed
        catch err
            # Output that disagrees with the run's own report is a failed
            # attempt, recorded with the reason instead of a number.
            err isa ArgumentError || rethrow()
            [merge(process, Dict("status" => "error", "correctness_status" => "failed", "error" => err.msg))]
        end
    end
    if !config.keep_outputs && all(r -> r["status"] == "ok", rows)
        rm(paths["output.txt"]; force=true)
    end
    return rows
end

"""Rows for an attempt whose process exited 0, after checking its output."""
function completed_rows(attempt::Attempt, process, paths)
    n = attempt.entry.stats.transactions
    output_count = count_itemset_lines(paths["output.txt"])
    common = merge(process, Dict("output_count" => string(output_count),
                                 "output_sha256" => file_sha256(paths["output.txt"])))
    if attempt.variant in REFERENCE_VARIANTS
        text = read(paths["stdout.txt"], String)
        stats = attempt.variant == :spmf ? parse_spmf_stats(text) : parse_prepost_stats(text)
        if attempt.variant == :prepost
            stats.minsup_count == attempt.minsup_count || throw(ArgumentError(
                "PrePost+ used count $(stats.minsup_count), expected $(attempt.minsup_count)"))
        end
        stats.transactions == n ||
            throw(ArgumentError("SPMF read $(stats.transactions) transactions, expected $n"))
        stats.itemsets == output_count ||
            throw(ArgumentError("SPMF reported $(stats.itemsets) itemsets but wrote $output_count"))
        return [common, merge(common, Dict("timing_scope" => "spmf_total",
                                           "elapsed_seconds" => string(stats.total_seconds)))]
    end
    # The CLI reports no phases; the exact-map comparison checks its output instead.
    get(process, "mode", "") == "cli" && return [common]
    report = TOML.parsefile(paths["worker.toml"])
    report["transactions"] == n ||
        throw(ArgumentError("worker read $(report["transactions"]) transactions, expected $n"))
    report["minsup_count"] == attempt.minsup_count ||
        throw(ArgumentError("worker used count $(report["minsup_count"]), expected $(attempt.minsup_count)"))
    report["output_count"] == output_count ||
        throw(ArgumentError("worker mined $(report["output_count"]) itemsets but wrote $output_count"))
    report["mode"] == process["mode"] || throw(ArgumentError("worker mode disagrees with config"))
    phases = [merge(common, Dict("timing_scope" => scope,
        "warmup_policy" => report["mode"] == "warm" ? "dataset-warmup" : "cold-call",
        "elapsed_seconds" => string(report[scope * "_seconds"]),
        "allocated_bytes" => string(report[scope * "_allocated_bytes"]),
        "gc_seconds" => string(report[scope * "_gc_seconds"]))) for scope in ("read", "mine", "write")]
    return [common; phases]
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
