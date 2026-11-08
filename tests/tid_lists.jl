@testset "Tid-list tidsets" begin
    intersect_lists! = ItemsetMining.intersect_lists!

    @testset "A join reaching minsup is exact; any other returns -1" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:500
            a = sort!(unique(rand(rng, 1:60, rand(rng, 0:40))))
            b = sort!(unique(rand(rng, 1:60, rand(rng, 0:40))))
            minsup = rand(rng, 1:20)
            dest = rand(rng, 1:9, rand(rng, 0:3))
            a_before, b_before = copy(a), copy(b)
            both = intersect(a, b)
            support = intersect_lists!(dest, a, b, minsup)
            if length(both) >= minsup
                @test support == length(both) && dest == both
            else
                @test support == -1
            end
            @test a == a_before && b == b_before
        end
        @test @inferred(intersect_lists!(Int[], [1, 2, 3], [2, 3], 1)) == 2
        @test intersect_lists!(Int[], Int[], Int[], 1) == -1
    end

    @testset "Bitset bits become tids for N = $n" for n in (1, 63, 64, 65, 129)
        rng = Xoshiro(DEFAULT_SEED + n)
        members = [t for t in 1:n if rand(rng, Bool)]
        words = only(ItemsetMining.bitset_tidsets([t in members ? [1] : Int[] for t in 1:n], [1]))
        @test @inferred(ItemsetMining.bitset_tids(words)) == members
    end

    @testset "Children switch to lists only when their joins outweigh the conversion" begin
        prefer_lists = ItemsetMining.prefer_lists
        BitsetMember = ItemsetMining.BitsetMember
        class(k, support) = [BitsetMember(c, support, zeros(UInt64, 100)) for c in 1:k]
        state(rule=:cost) = ItemsetMining.SearchState(rule, 8.0)
        # 20 children with short tidsets: 190 joins of 100 words against 20 conversions and short merges.
        @test prefer_lists(class(20, 2), state())
        # Two children: one join cannot repay two conversions.
        @test !prefer_lists(class(2, 1), state())
        # Long tidsets make each merge dearer than a bitset join.
        @test !prefer_lists(class(20, 90), state())
        @test prefer_lists(class(2, 90), state(:always))
        @test !prefer_lists(class(20, 2), state(:never))
    end
end

@testset "Search with tid-list classes" begin
    BitsetMember, ListMember = ItemsetMining.BitsetMember, ItemsetMining.ListMember

    @testset "A list search leaves parents, prefix, and perfect stack as it found them" begin
        database = [[1, 2, 3, 4], [1, 2, 4], [2, 3], [1, 3, 4], [1, 2, 3, 4], [2, 4]]
        class = [ListMember(m.item, m.support, ItemsetMining.bitset_tids(m.tidset))
                 for m in ItemsetMining.bitset_class(database, 2)]
        before = [copy(m.tidset) for m in class]
        prefix, perfect = Int[], Int[]
        result = @inferred ItemsetMining.eclat_search!(class, prefix, perfect, 2, FrequentItemsets(),
                                                       ItemsetMining.SearchState())
        @test [m.tidset for m in class] == before
        @test isempty(prefix) && isempty(perfect)
        @test support_map(result) == brute_force_supports(database, 2)
        @test length(result) == length(support_map(result))
    end

    @testset "Mining matches the oracle with lists $rule" for rule in (:never, :always, :cost)
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:200
            transactions = [rand(rng, 0:11, rand(rng, 0:7)) for _ in 1:rand(rng, 0:40)]
            database = ItemsetMining.canonical_database(transactions)
            min_count = rand(rng, 1:4)
            expected = brute_force_supports(unique.(transactions), min_count)
            packed = ItemsetMining.mine_optimized(database, min_count; list_rule=rule)
            @test support_map(packed) == expected
            @test length(packed) == length(expected)
        end
    end

    @testset "Perfect extensions are found inside list classes" begin
        # Items 2 and 3 always occur together, so below the root one is perfect for the other.
        transactions = [[1, 2, 3], [1, 2, 3], [1, 4], [2, 3, 4], [1, 2, 3, 4]]
        packed = ItemsetMining.mine_optimized(ItemsetMining.canonical_database(transactions), 1; list_rule=:always)
        @test support_map(packed) == brute_force_supports(transactions, 1)
        @test length(packed) == length(support_map(packed))
    end
end
