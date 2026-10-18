module ItemsetMining

export Itemset, SupportMap, DEFAULT_SEED, canonical_transaction,
       support_threshold, read_transactions, write_itemsets, mine

include("structures.jl")
include("utils.jl")
include("algorithm/eclat.jl")

end
