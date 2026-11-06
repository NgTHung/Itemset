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
        rm(dir; recursive=true)
    end
    # Julia 1.12 keeps this one-line method inferred but without native code after the
    # call above, so the image needs an explicit request to compile it.
    precompile(read_transactions, (String,))
end
