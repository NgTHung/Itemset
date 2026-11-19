# Compilation cost every cold run about 2 s before mining started. Running the public
# calls once while the package image is built stores their native code in the image.
# The guard keeps the workload out of ordinary `using`.
if ccall(:jl_generating_output, Cint, ()) == 1
    let dir = mktempdir()
        input = joinpath(dir, "transactions.txt")
        output = joinpath(dir, "itemsets.txt")
        write(input, "1 2 3\n1 2\n2 3\n")
        transactions = read_transactions(input)
        # A fractional and an absolute minsup reach `mine_packed` as different types.
        for minsup in (0.5, 2), variant in (:baseline, :optimized)
            write_itemsets(output, mine_packed(transactions; minsup, variant))
            write_itemsets(output, mine(transactions; minsup, variant))
        end
        # A CLI run prints to a file stream, as when its output is redirected.
        open(joinpath(dir, "stdout.txt"), "w") do out
            cli_main(["--help"], out)
            cli_main(["--check-input", input], out)
            for args in (["--minsup", "0.5"], ["--min-count", "2"]), variant in ("baseline", "optimized")
                cli_main([args; "--variant"; variant; "--output"; output; input], out)
                cli_exit_code([args; "--variant"; variant; "--output"; output; input])
            end
        end
        rm(dir; recursive=true)
    end
    # Julia 1.12 keeps this one-line method inferred but without native code after the
    # call above, so the image needs an explicit request to compile it.
    precompile(read_transactions, (String,))
    # Redirected stdout can wrap its file stream in an IOContext.
    precompile(cli_main, (Vector{String}, IOContext{IOStream}))
end
