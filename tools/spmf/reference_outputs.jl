using ItemsetMining
using TOML: TOML
include(joinpath(dirname(dirname(@__DIR__)), "experiments", "Experiments.jl"))
using .Experiments: file_sha256, threshold_agrees

const DATA_DIR = joinpath(dirname(dirname(@__DIR__)), "data")
const REFERENCE_DIRS = [joinpath(DATA_DIR, "toy"), joinpath(DATA_DIR, "correctness")]

"""
    reference_outputs_main(arguments) -> Int

Mine every run in `data/toy/spmf/runs.toml` and `data/correctness/spmf/runs.toml`
with the SPMF JAR and write SPMF's raw output beside each list. `arguments` holds
an optional Java executable, by default `java`. Each input is first rewritten
without `@ITEM` labels so SPMF writes item IDs. Throws `ArgumentError` before
running SPMF when an input's SHA-256 differs from its `input_sha256` or a
threshold gives SPMF a different count from `support_threshold`, and fails on a
nonzero SPMF exit.
"""
function reference_outputs_main(arguments::AbstractVector{<:AbstractString})
    length(arguments) <= 1 ||
        throw(ArgumentError("usage: julia --project=. tools/spmf/reference_outputs.jl [JAVA]"))
    java = isempty(arguments) ? "java" : only(arguments)
    jar = joinpath(@__DIR__, "spmf.jar")
    isfile(jar) || throw(ArgumentError("SPMF JAR not found at $jar; see tools/spmf/README.md"))
    mktempdir() do dir
        for data_dir in REFERENCE_DIRS
            spmf_dir = joinpath(data_dir, "spmf")
            for run_entry in TOML.parsefile(joinpath(spmf_dir, "runs.toml"))["run"]
                source = joinpath(data_dir, run_entry["input"])
                expected_sha = get(run_entry, "input_sha256", nothing)
                expected_sha === nothing || file_sha256(source) == expected_sha ||
                    throw(ArgumentError("$source: SHA-256 differs from input_sha256 $expected_sha"))
                transactions = read_transactions(source)
                minsup, n = run_entry["minsup"], length(transactions)
                threshold_agrees(minsup, n) && support_threshold(minsup, n) == run_entry["count"] ||
                    throw(ArgumentError("$(run_entry["input"]): minsup $minsup does not give count $(run_entry["count"]) in SPMF"))
                input = joinpath(dir, run_entry["input"])
                write_transactions(input, transactions)
                output = joinpath(spmf_dir, run_entry["output"])
                # SPMF exits 0 even when it fails, so a stale file must not pass as its output.
                rm(output; force=true)
                run(pipeline(`$java -jar $jar run Eclat $input $output $minsup`; stdout=devnull))
                isfile(output) || throw(ArgumentError("SPMF wrote no output for $(run_entry["input"])"))
                println(relpath(output, DATA_DIR))
            end
        end
    end
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(reference_outputs_main(ARGS))
end
