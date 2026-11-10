module ItemsetMining

export Itemset, SupportMap, DEFAULT_SEED, canonical_transaction,
       support_threshold, read_transactions, write_itemsets, mine,
       encode_transactions, decode_itemset, write_transactions,
       read_itemset_records, item_frequencies, FrequentItemsets, mine_packed, support_map

include("structures.jl")
include("frequent_itemsets.jl")
include("itemset_order.jl")
include("spmf_writer.jl")
include("encoding.jl")
include("spmf_reader.jl")
include("utils.jl")
include("algorithm/eclat.jl")
include("algorithm/tidsets.jl")
include("algorithm/pair_counts.jl")
include("algorithm/search_nodes.jl")
include("algorithm/eclat_optimized.jl")
include("algorithm/block_counts.jl")
include("cli.jl")
include("precompile.jl")

end
