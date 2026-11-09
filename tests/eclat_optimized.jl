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
        prefix, perfect = Int[], Int[]
        nodes = @inferred ItemsetMining.eclat_search!(class, prefix, perfect, 2, ItemsetMining.SearchNodes(),
                                                      ItemsetMining.SearchState())
        result = @inferred ItemsetMining.expand_nodes(nodes)
        @test [m.tidset for m in class] == before
        @test isempty(prefix) && isempty(perfect)
        @test support_map(result) == brute_force_supports(database, 2)
        @test length(result) == length(support_map(result))
    end

    @testset "Mining allocates its result once, at its final size" begin
        # Shared groups give nodes with many perfect extensions, so most itemsets come from expansion.
        transactions = [fill(collect(1:14), 30); fill([1:14; 15; 16], 10); fill([15, 16, 17], 5)]
        canonical = ItemsetMining.canonical_database(transactions)
        mine = () -> ItemsetMining.mine_optimized(canonical, 5)
        packed = mine()
        @test length(packed) > 50_000
        result_bytes = sizeof(packed.items) + sizeof(packed.offsets) + sizeof(packed.supports)
        @test @allocated(mine()) < 1.25 * result_bytes
    end

    @testset "More perfect-extension subsets than a result can hold throw before any emission" begin
        nodes = ItemsetMining.SearchNodes()
        @test_throws OverflowError ItemsetMining.push_node!(nodes, [100], collect(1:63), 1)
        @test isempty(nodes.supports)
        # 2^62 subsets of two core items need 2^63 item slots, past typemax(Int).
        ItemsetMining.push_node!(nodes, [1, 2], collect(3:64), 1)
        @test_throws OverflowError ItemsetMining.expand_nodes(nodes)
    end

    @testset "Every pair-count and tid-list setting matches the oracle" begin
        rng = Xoshiro(DEFAULT_SEED)
        # Sizes around multiples of 64 cross bitset word boundaries.
        sizes = [0:40; 63:65; 127:129]
        for _ in 1:200
            transactions = random_database(rng, rand(rng, sizes); grouped=rand(rng, Bool))
            canonical = ItemsetMining.canonical_database(transactions)
            min_count = rand(rng, 1:4)
            expected = brute_force_supports(unique.(transactions), min_count)
            for use_pair_counts in (true, false), list_rule in (:never, :always, :cost)
                packed = ItemsetMining.mine_optimized(canonical, min_count; use_pair_counts, list_rule)
                # A duplicate emission would overwrite its map entry, so the counts must agree too.
                @test support_map(packed) == expected
                @test length(packed) == length(expected)
            end
        end
    end
end
