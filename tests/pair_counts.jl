@testset "Frequent pair counts" begin
    PairCounts = ItemsetMining.PairCounts

    @testset "Each pair of ranks has its own slot for m = $m" for m in 1:7
        slots = [ItemsetMining.pair_slot(m, i, j) for i in 1:m for j in i+1:m]
        @test sort(slots) == 1:m*(m-1)÷2
    end

    @testset "The table size is checked before allocation" begin
        @test ItemsetMining.pair_table_length(1) == 0
        @test ItemsetMining.pair_table_length(4) == 6
        @test ItemsetMining.pair_table_length(2^40) === nothing
        @test ItemsetMining.pair_table_length(typemax(Int)) === nothing
    end

    @testset "Counts equal the support of each pair" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:50
            database = ItemsetMining.canonical_database([rand(rng, 0:9, rand(rng, 0:7)) for _ in 1:rand(rng, 0:30)])
            items = shuffle(rng, unique(rand(rng, 0:9, rand(rng, 1:8))))
            pairs = @inferred ItemsetMining.count_pairs(database, items)
            for i in eachindex(items), j in i+1:lastindex(items)
                expected = count(t -> items[i] in t && items[j] in t, database)
                @test ItemsetMining.pair_support(pairs, i, j) == expected
            end
        end
    end

    @testset "Pairs are counted only where they replace many root joins" begin
        # Long transactions over few items make counting dearer than joining.
        dense = [collect(1:20) for _ in 1:100]
        @test ItemsetMining.pair_filter(dense, collect(1:20)) isa ItemsetMining.NoPairCounts
        # Short transactions over many items make most root joins fail.
        sparse = [[k, k + 1] for k in 1:2:1000 for _ in 1:30]
        @test ItemsetMining.pair_filter(sparse, collect(1:1000)) isa PairCounts
        @test ItemsetMining.pair_filter(Vector{Int}[], Int[]) isa ItemsetMining.NoPairCounts
    end

    @testset "Joins whose pair count is below minsup are skipped" begin
        BitsetMember = ItemsetMining.BitsetMember
        database = [[1, 2, 3], [1, 2, 3], [1, 3]]
        words = ItemsetMining.bitset_tidsets(database, [1, 2, 3])
        class = [BitsetMember(2, 2, words[2]), BitsetMember(1, 3, words[1]), BitsetMember(3, 3, words[3])]
        # Wrong counts on purpose: a skipped join leaves no child, which shows the table was read.
        pairs = PairCounts(3, Int32[0, 2, 2])
        children, perfect = BitsetMember[], Int[]
        ItemsetMining.join_members!(children, perfect, class, 1, 2, Vector{UInt64}[], pairs)
        @test isempty(children) && perfect == [3]
    end

    @testset "Mining with and without pair counts matches the oracle" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:200
            transactions = [rand(rng, 0:11, rand(rng, 0:6)) for _ in 1:rand(rng, 0:30)]
            database = ItemsetMining.canonical_database(transactions)
            min_count = rand(rng, 1:4)
            expected = brute_force_supports(unique.(transactions), min_count)
            for use_pair_counts in (true, false)
                packed = ItemsetMining.mine_optimized(database, min_count; use_pair_counts)
                @test support_map(packed) == expected
                @test length(packed) == length(expected)
            end
        end
        @test @inferred(ItemsetMining.mine_optimized([[1, 2], [1, 2]], 1; use_pair_counts=true)) isa FrequentItemsets
    end
end
