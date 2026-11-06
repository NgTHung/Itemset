module OutputComparison
include(joinpath(dirname(@__DIR__), "tools", "spmf", "compare.jl"))
end

"""Parse PrePost+'s complete statistics block, including its resolved support count."""
function parse_prepost_stats(text::AbstractString)
    grab(pattern) = begin
        m = match(pattern, text)
        m === nothing && throw(ArgumentError("PrePost+ output lacks $(pattern.pattern)"))
        parse(Int, m[1])
    end
    return (transactions=grab(r"Number of transactions:\s*(\d+)"),
            itemsets=grab(r"Number of frequent\s+itemsets:\s*(\d+)"),
            total_seconds=grab(r"Total time ~:\s*(\d+) ms") / 1000,
            minsup_count=grab(r"Minsup =\s*(\d+)"))
end

"""Compare complete maps outside timing and persist duplicate and support diagnostics."""
function verify_output(reference::AbstractString, candidate::AbstractString, report::AbstractString)
    result = Dict{String,Any}("reference" => abspath(reference),
        "reference_sha256" => file_sha256(reference), "candidate_sha256" => file_sha256(candidate))
    try
        comparison = OutputComparison.compare_itemsets(open(OutputComparison.parse_itemsets, reference),
                                                        open(OutputComparison.parse_itemsets, candidate))
        merge!(result, Dict("matches" => comparison.matches, "match_rate" => comparison.match_rate,
            "missing" => length(comparison.missing), "extra" => length(comparison.extra),
            "support_mismatches" => length(comparison.support_mismatches),
            "reference_duplicates" => length(comparison.reference_duplicates),
            "candidate_duplicates" => length(comparison.candidate_duplicates)))
    catch err
        err isa ArgumentError || rethrow()
        merge!(result, Dict("matches" => false, "error" => sprint(showerror, err)))
    end
    open(io -> TOML.print(io, result), report, "w")
    return Dict("correctness_status" => result["matches"] ? "exact" : "failed",
        "match_rate" => string(get(result, "match_rate", "")),
        "comparison_reference_sha256" => result["reference_sha256"])
end

"""Create one separately executed SPMF Eclat reference per dataset and absolute threshold."""
function prepare_reference(attempt::Attempt, config::RunConfig, input::String, dir::String)
    mkpath(dir)
    output, report, out, err = joinpath.(dir, ("output.txt", "measure.toml", "stdout.txt", "stderr.txt"))
    if !isfile(report)
        reference = Attempt(; id="reference", entry=attempt.entry, minsup=attempt.minsup,
                            minsup_count=attempt.minsup_count, variant=:spmf, repeat=0, stage="", project="")
        command = measured_command(reference, config, input, output, "")
        write(joinpath(dir, "command.txt"), string(command), "\n")
        run(`$(Base.julia_cmd()) --startup-file=no $MEASURE_SCRIPT --timeout $(config.timeout_seconds)
             --stdout $out --stderr $err --report $report -- $command`)
    end
    measured = TOML.parsefile(report)
    measured["status"] == "ok" || throw(ArgumentError(
        "SPMF reference $(measured["status"]) for $(attempt.entry.name) count $(attempt.minsup_count); see $dir"))
    stats = parse_spmf_stats(read(out, String))
    stats.transactions == attempt.entry.stats.transactions ||
        throw(ArgumentError("SPMF reference transaction count $(stats.transactions) disagrees with manifest"))
    stats.itemsets == count_itemset_lines(output) ||
        throw(ArgumentError("SPMF reference output is truncated at $output"))
    verified = verify_output(output, output, joinpath(dir, "comparison.toml"))
    verified["correctness_status"] == "exact" ||
        throw(ArgumentError("SPMF reference is malformed or contains duplicates at $output"))
    return output
end
