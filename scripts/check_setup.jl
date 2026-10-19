using ItemsetMining

v"1.12" <= VERSION < v"2" || error("Expected Julia 1.12 or later in the 1.x series, got $VERSION")
root = dirname(@__DIR__)
transactions = read_transactions(joinpath(root, "data", "toy", "baskets.txt"))
@assert length(transactions) == 4
@assert support_threshold(0.5, length(transactions)) == 2
@assert canonical_transaction([3, 1, 1]) == [1, 3]
println("Setup OK | Julia $VERSION | seed=$DEFAULT_SEED | toy transactions=$(length(transactions))")