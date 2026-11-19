"""
A seeded database of `n` transactions over items 0-11. A grouped database draws whole
groups of items that always co-occur, so perfect extensions appear at every depth.
"""
function random_database(rng, n; grouped::Bool)
    grouped || return [rand(rng, 0:11, rand(rng, 0:7)) for _ in 1:n]
    items = shuffle(rng, 0:11)
    cuts = sort!(rand(rng, 1:11, rand(rng, 1:4)))
    groups = [items[a+1:b] for (a, b) in zip([0; cuts], [cuts; 12]) if a < b]
    return [vcat(Int[], (g for g in groups if rand(rng) < 0.6)...) for _ in 1:n]
end

@testset "Optimized Eclat" begin
    BitsetMember, ListMember = ItemsetMining.BitsetMember, ItemsetMining.ListMember
    database = [[1, 2, 3, 4], [1, 2, 4], [2, 3], [1, 3, 4], [1, 2, 3, 4], [2, 4]]
    bitset_class = ItemsetMining.bitset_class(database, 2)
    list_class = [ListMember(m.item, m.support, ItemsetMining.bitset_tids(m.tidset)) for m in bitset_class]

    @testset "A $form search is type-stable and restores its shared state" for (form, class) in
            (("bitset", bitset_class), ("tid-list", list_class))
        before = [copy(m.tidset) for m in class]
        perfect = Int[]
        nodes = @inferred ItemsetMining.eclat_search!(class, 1, perfect, 2, ItemsetMining.SearchNodes(),
                                                      ItemsetMining.SearchState())
        result = @inferred ItemsetMining.expand_nodes(nodes)
        @test [m.tidset for m in class] == before
        @test isempty(perfect)
        @test support_map(result) == brute_force_supports(database, 2)
        @test length(result) == length(support_map(result))
    end

    @testset "Mining allocates little beyond its result" begin
        result_bytes(packed) = sizeof(packed.items) + sizeof(packed.offsets) + sizeof(packed.supports)
        # Shared groups give nodes with many perfect extensions, so most itemsets come from expansion.
        grouped = [fill(collect(1:14), 30); fill([1:14; 15; 16], 10); fill([15, 16, 17], 5)]
        # Independent items give almost no perfect extensions, so nearly every node is one itemset.
        rng = Xoshiro(DEFAULT_SEED)
        independent = [randsubseq(rng, 0:40, 0.5) for _ in 1:300]
        for (transactions, min_count, limit) in ((grouped, 5, 1.25), (independent, 12, 3.0))
            canonical = ItemsetMining.canonical_database(transactions)
            mine = () -> ItemsetMining.mine_optimized(canonical, min_count)
            packed = mine()
            @test length(packed) > 50_000
            @test @allocated(mine()) < limit * result_bytes(packed)
        end
    end

    @testset "More perfect-extension subsets than a result can hold throw before any emission" begin
        # The 63 perfect items come from two nodes on one path, so only their sum is too large.
        nodes = ItemsetMining.SearchNodes()
        ItemsetMining.push_node!(nodes, 1, 100, collect(1:40), 1)
        ItemsetMining.push_node!(nodes, 2, 101, collect(41:63), 1)
        @test_throws OverflowError ItemsetMining.expand_nodes(nodes)
        # 2^62 subsets of two core items need 2^63 item slots, past typemax(Int).
        nodes = ItemsetMining.SearchNodes()
        ItemsetMining.push_node!(nodes, 1, 1, Int[], 1)
        ItemsetMining.push_node!(nodes, 2, 2, collect(3:64), 1)
        @test_throws OverflowError ItemsetMining.expand_nodes(nodes)
    end

    @testset "A block-count bound never rejects a frequent join" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:10
            n = rand(rng, 1:300)
            class = [ListMember(m, 1, sort!(randsubseq(rng, 1:n, rand(rng)))) for m in 1:rand(rng, 2:6)]
            filter!(m -> !isempty(m.tidset), class)
            length(class) >= 2 || continue
            bound = ItemsetMining.BlockCounts(Int32[], class, rand(rng, 1:70))
            for i in eachindex(class), j in i+1:lastindex(class)
                common = length(intersect(class[i].tidset, class[j].tidset))
                @test ItemsetMining.may_be_frequent(bound, i, j, common)
            end
        end
        # Tids 1 to 3 and 200 to 202 share no block of 64, so the bound proves the join empty.
        apart = [ListMember(1, 3, [1, 2, 3]), ListMember(2, 3, [200, 201, 202])]
        @test !ItemsetMining.may_be_frequent(ItemsetMining.BlockCounts(Int32[], apart, 4), 1, 2, 1)
    end

    @testset "Every pair-count, tid-list, and block-bound setting matches the oracle" begin
        rng = Xoshiro(DEFAULT_SEED)
        # Pin word boundaries and both data shapes without repeating the full configuration grid.
        cases = ((0, false, 1), (1, true, 1), (63, false, 2), (64, true, 3),
                 (65, false, 4), (127, true, 2), (128, false, 3), (129, true, 4))
        for (n, grouped, min_count) in cases
            transactions = random_database(rng, n; grouped)
            canonical = ItemsetMining.canonical_database(transactions)
            expected = brute_force_supports(unique.(transactions), min_count)
            for use_pair_counts in (true, false), list_rule in (:never, :always, :cost),
                bound_blocks in (0, 4, ItemsetMining.BOUND_BLOCKS)
                packed = ItemsetMining.mine_optimized(canonical, min_count; use_pair_counts, list_rule, bound_blocks)
                # A duplicate emission would overwrite its map entry, so the counts must agree too.
                @test support_map(packed) == expected
                @test length(packed) == length(expected)
            end
        end
    end
end
