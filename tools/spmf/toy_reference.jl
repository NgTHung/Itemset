using ItemsetMining
using TOML: TOML
include(joinpath(dirname(dirname(@__DIR__)), "experiments", "Experiments.jl"))
using .Experiments: threshold_agrees

const TOY_DIR = joinpath(dirname(dirname(@__DIR__)), "data", "toy")
const SPMF_TOY_DIR = joinpath(TOY_DIR, "spmf")

"""
    toy_reference_main(arguments) -> Int

Mine every run in `data/toy/spmf/runs.toml` with the SPMF JAR and write SPMF's
raw output beside it. `arguments` holds an optional Java executable, by default
`java`. Each input is first rewritten without `@ITEM` labels so SPMF writes item
IDs. Throws `ArgumentError` before running SPMF when a threshold gives SPMF a
different count from `support_threshold`, and fails on a nonzero SPMF exit.
"""
function toy_reference_main(arguments::AbstractVector{<:AbstractString})
    length(arguments) <= 1 ||
        throw(ArgumentError("usage: julia --project=. tools/spmf/toy_reference.jl [JAVA]"))
    java = isempty(arguments) ? "java" : only(arguments)
    jar = joinpath(@__DIR__, "spmf.jar")
    isfile(jar) || throw(ArgumentError("SPMF JAR not found at $jar; see tools/spmf/README.md"))
    runs = TOML.parsefile(joinpath(SPMF_TOY_DIR, "runs.toml"))["run"]
    mktempdir() do dir
        for run_entry in runs
            transactions = read_transactions(joinpath(TOY_DIR, run_entry["input"]))
            minsup, n = run_entry["minsup"], length(transactions)
            threshold_agrees(minsup, n) && support_threshold(minsup, n) == run_entry["count"] ||
                throw(ArgumentError("$(run_entry["input"]): minsup $minsup does not give count $(run_entry["count"]) in SPMF"))
            input = joinpath(dir, run_entry["input"])
            write_transactions(input, transactions)
            output = joinpath(SPMF_TOY_DIR, run_entry["output"])
            # SPMF exits 0 even when it fails, so a stale file must not pass as its output.
            rm(output; force=true)
            run(pipeline(`$java -jar $jar run Eclat $input $output $minsup`; stdout=devnull))
            isfile(output) || throw(ArgumentError("SPMF wrote no output for $(run_entry["input"])"))
            println(run_entry["output"])
        end
    end
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(toy_reference_main(ARGS))
end
