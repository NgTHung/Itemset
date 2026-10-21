module ItemsetMining

export Itemset, SupportMap, DEFAULT_SEED, canonical_transaction,
       support_threshold, read_transactions, write_itemsets, mine,
       encode_transactions, decode_itemset, write_transactions

include("structures.jl")
include("encoding.jl")
include("utils.jl")
include("algorithm/eclat.jl")

end
