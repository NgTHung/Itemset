@testset "Bitset tidsets" begin
    bitset_tidsets = ItemsetMining.bitset_tidsets
    intersect_bitsets! = ItemsetMining.intersect_bitsets!

    @testset "Bits stop at the last of $n transactions" for n in (0, 1, 63, 64, 65, 127, 128, 129)
        words = only(bitset_tidsets([[1] for _ in 1:n], [1]))
        @test length(words) == cld(n, 64)
        @test sum(count_ones, words; init=0) == n
        # A bit past tid n would count a transaction that does not exist.
        n % 64 == 0 || @test words[end] >> (n % 64) == 0
    end

    @testset "Bit t - 1 marks tid t, in the order the items are given" begin
        a, b = bitset_tidsets([[2], [1, 2], Int[], [1, 3]], [1, 2])
        @test a == [UInt64(0b1010)] && b == [UInt64(0b0011)]
        @test bitset_tidsets([[1]], Int[]) == Vector{UInt64}[]
    end

    @testset "Intersections count exactly and leave their inputs alone" begin
        rng = Xoshiro(DEFAULT_SEED)
        for n in (1, 63, 64, 65, 129, 200), _ in 1:20
            in_a, in_b = rand(rng, Bool, n), rand(rng, Bool, n)
            database = [[item for (item, member) in ((1, in_a[t]), (2, in_b[t])) if member] for t in 1:n]
            a, b = bitset_tidsets(database, [1, 2])
            a_before, b_before = copy(a), copy(b)
            dest = similar(a)
            @test intersect_bitsets!(dest, a, b) == count(in_a .& in_b)
            @test dest == a .& b
            @test a == a_before && b == b_before
        end
        @test @inferred(intersect_bitsets!(zeros(UInt64, 2), ones(UInt64, 2), ones(UInt64, 2))) == 2
        @test_throws DimensionMismatch intersect_bitsets!(zeros(UInt64, 1), zeros(UInt64, 2), zeros(UInt64, 2))
    end
end

@testset "Bitset Eclat search" begin
    @testset "Items run in increasing support, ties by item" begin
        order = ItemsetMining.frequent_items_by_support
        @test order([[1, 2, 3], [1, 2], [2]], 1) == [3 => 1, 1 => 2, 2 => 3]
        @test order([[5], [3], [5, 3, 9]], 2) == [3 => 2, 5 => 2]
        @test order(Vector{Int}[], 1) == Pair{Int,Int}[]
    end

    @testset "Searches leave parent tidsets and the prefix as they found them" begin
        database = [[1, 2, 3, 4], [1, 2, 4], [2, 3], [1, 3, 4], [1, 2, 3, 4]]
        class = ItemsetMining.bitset_class(database, 2)
        before = [copy(member.words) for member in class]
        prefix = Int[]
        result = @inferred ItemsetMining.bitset_search!(class, prefix, 2, FrequentItemsets(), Vector{UInt64}[])
        @test [member.words for member in class] == before
        @test isempty(prefix)
        @test support_map(result) == brute_force_supports(database, 2)
        @test length(result) == length(support_map(result))
        @test all(issorted(items; lt=<=) for (items, _) in result)
    end

    @testset "Maps match the oracle across word boundaries at N = $n" for n in (0, 1, 63, 64, 65, 127, 128, 129)
        rng = Xoshiro(DEFAULT_SEED + n)
        for _ in 1:10
            transactions = [rand(rng, 0:7, rand(rng, 0:5)) for _ in 1:n]
            min_count = rand(rng, 1:max(1, n ÷ 4))
            @test mine(transactions; minsup=min_count, variant=:optimized) ==
                  brute_force_supports(unique.(transactions), min_count)
        end
    end
end
