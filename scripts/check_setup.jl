using ItemsetMining

VERSION == v"1.13.2" || error("Expected Julia 1.13.2, got $VERSION")
root = dirname(@__DIR__)
transactions = read_transactions(joinpath(root, "data", "toy", "baskets.txt"))
@assert length(transactions) == 4
@assert support_threshold(0.5, length(transactions)) == 2
@assert canonical_transaction([3, 1, 1]) == [1, 3]
println("Setup OK | Julia $VERSION | seed=$DEFAULT_SEED | toy transactions=$(length(transactions))")
println("Eclat implementation and SPMF validation are pending (DAT-8 / DAT-9 / DAT-13).")
