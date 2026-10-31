@testset "Packed frequent itemsets" begin
    @testset "Layout" begin
        empty = FrequentItemsets()
        @test length(empty) == 0
        @test isempty(collect(empty))
        @test support_map(empty) == SupportMap()
        packed = FrequentItemsets([1, 1, 2, 3], [1, 2, 4, 5], [4, 2, 3])
        @test length(packed) == 3
        @test collect(packed) == [[1] => 4, [1, 2] => 2, [3] => 3]
        @test support_map(packed) == SupportMap((1,)=>4, (1, 2)=>2, (3,)=>3)
        for (items, offsets, supports) in ((Int[], Int[], Int[]), ([1], [1, 3], [1]),
                                           ([1, 2], [1, 3, 2], [1, 1]), ([1], [2, 2], [1]),
                                           ([1], [1, 2], [1, 1]))
            @test_throws ArgumentError FrequentItemsets(items, offsets, supports)
        end
    end
    @testset "Mining $variant" for variant in MINED_VARIANTS
        for case in MINING_CASES
            transactions = read_transactions(joinpath(TOY_DIR, case.name * ".txt"))
            packed = mine_packed(transactions; minsup=case.minsup, variant)
            @test support_map(packed) == case.expected
            # A repeated itemset would collapse in the map, so count records too.
            @test length(packed) == length(case.expected)
        end
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:100
            transactions = [rand(rng, 0:11, rand(rng, 0:9)) for _ in 1:rand(rng, 0:20)]
            min_count = rand(rng, 1:5)
            packed = mine_packed(transactions; minsup=min_count, variant)
            expected = brute_force_supports(unique.(transactions), min_count)
            @test support_map(packed) == expected
            @test length(packed) == length(expected)
            @test all(issorted(items; lt=<=) for (items, _) in packed)
        end
        @test_throws ArgumentError mine_packed([[1]]; minsup=1, variant=:unknown)
        @test_throws "transaction 2" mine_packed([[1], [-1]]; minsup=1, variant)
        @test @inferred(mine_packed([[1, 2], [2]]; minsup=1, variant)) isa FrequentItemsets
    end
end
