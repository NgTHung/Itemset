"""Pack `itemsets` in the given order with support 1, so only their order matters."""
pack_itemsets(itemsets) =
    FrequentItemsets(reduce(vcat, itemsets; init=Int[]), cumsum([1; length.(itemsets)]), ones(Int, length(itemsets)))

"""The write order by definition: compare item vectors as Julia does, where a prefix sorts first."""
reference_order(itemsets) = sortperm(itemsets; lt=isless)

@testset "Lexicographic itemset order" begin
    lexicographic_order = ItemsetMining.lexicographic_order

    @testset "Random itemsets over item range $range" for range in (0:9, 0:200, 0:70_000, typemax(Int)-20:typemax(Int))
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:3
            itemsets = unique([sort!(unique(rand(rng, range, rand(rng, 1:12)))) for _ in 1:rand(rng, 1:400)])
            @test lexicographic_order(pack_itemsets(itemsets)) == reference_order(itemsets)
        end
    end

    @testset "Itemsets that differ only after many shared items" begin
        # Longer than any one sort key, so ties on the first items must still resolve.
        shared = collect(0:2:58)
        itemsets = [[shared; 100], shared, [shared; 61], [shared; 61; 70], [shared[1:end-1]; 59], [shared; 60]]
        @test lexicographic_order(pack_itemsets(itemsets)) == reference_order(itemsets)
    end

    @testset "A repeated itemset throws and names the itemset" begin
        @test_throws "[1, 2, 3]" lexicographic_order(pack_itemsets([[1, 2, 3], [4], [1, 2, 3]]))
        @test_throws ArgumentError lexicographic_order(pack_itemsets([collect(0:40), [1], collect(0:40)]))
    end
end
