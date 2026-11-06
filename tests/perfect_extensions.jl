"""Mine with the optimized variant and check the map and the number of emitted itemsets."""
function check_optimized_against_oracle(transactions, min_count)
    packed = mine_packed(transactions; minsup=min_count, variant=:optimized)
    patterns = support_map(packed)
    # A duplicate emission would overwrite its map entry, so the counts must agree too.
    return patterns == brute_force_supports(unique.(transactions), min_count) &&
           length(packed) == length(patterns)
end

@testset "Perfect-extension emission" begin
    push_subsets! = ItemsetMining.push_subsets!

    @testset "Every subset of the perfect items joins the prefix once" begin
        prefix, perfect = [2, 5], [7, 1, 4]
        result = @inferred push_subsets!(FrequentItemsets(), prefix, perfect, 3)
        emitted = [collect(items) for (items, _) in result]
        @test length(emitted) == 8
        @test Set(emitted) == Set(sort!([2, 5, s...]) for s in
                                  ([], [7], [1], [4], [7, 1], [7, 4], [1, 4], [7, 1, 4]))
        @test all(issorted(items; lt=<=) for items in emitted)
        @test all(==(3), result.supports)
        @test prefix == [2, 5] && perfect == [7, 1, 4]
    end

    @testset "Consecutive itemsets differ by one item" begin
        result = push_subsets!(FrequentItemsets(), [10], [3, 30, 20, 1], 1)
        emitted = [Set(items) for (items, _) in result]
        @test first(emitted) == Set([10])
        @test all(length(symdiff(emitted[k-1], emitted[k])) == 1 for k in 2:length(emitted))
    end

    @testset "No perfect items emits the prefix alone" begin
        result = push_subsets!(FrequentItemsets(), [4], Int[], 2)
        @test collect(result) == [[4] => 2]
    end

    @testset "More subsets than a result can hold throw before any emission" begin
        result = FrequentItemsets()
        @test_throws OverflowError push_subsets!(result, [100], collect(1:63), 1)
        @test length(result) == 0
    end
end

@testset "Perfect-extension joins" begin
    join_members! = ItemsetMining.join_members!
    BitsetMember = ItemsetMining.BitsetMember

    # Item 1 has t = {1, 2}; item 3 has the same support with t = {1, 3}; item 2 covers both.
    database = [[1, 2, 3], [1, 2], [2, 3]]
    words = ItemsetMining.bitset_tidsets(database, [1, 3, 2])
    class = [BitsetMember(1, 2, words[1]), BitsetMember(3, 2, words[2]), BitsetMember(2, 3, words[3])]

    @testset "Equal tidsets are perfect; equal supports alone are not" begin
        children, perfect = BitsetMember[], Int[]
        @test @inferred(join_members!(children, perfect, class, 1, 1, Vector{UInt64}[])) == 1
        @test perfect == [2]
        @test [(child.item, child.support) for child in children] == [(3, 1)]
    end

    @testset "Perfect and infrequent joins return their sets to the pool" begin
        spare = [zeros(UInt64, 1), zeros(UInt64, 1)]
        children, perfect, pool = BitsetMember[], Int[], copy(spare)
        join_members!(children, perfect, class, 1, 2, pool)
        @test isempty(children) && perfect == [2]
        @test length(pool) == 2 && all(any(s -> s === set, spare) for set in pool)
    end

    @testset "Perfect items found earlier on the path stay in place" begin
        children, perfect = BitsetMember[], [9]
        join_members!(children, perfect, class, 1, 1, Vector{UInt64}[])
        @test perfect == [9, 2]
    end
end

@testset "Bitset search with perfect extensions" begin
    @testset "Universal items" begin
        @test check_optimized_against_oracle([[0, 1, 2, 3, 9], [0, 1, 2, 9], [0, 2, 3, 9], [0, 1, 9]], 1)
        @test check_optimized_against_oracle([[1, 2], [1, 2], [1, 2]], 3)
    end

    @testset "Groups of items with equal tidsets" begin
        # Items 1-3 always occur together, as do 4-5.
        groups = ([1, 2, 3], [4, 5], [6])
        transactions = [vcat((groups[g] for g in pick)...) for pick in
                        ([1, 2], [1], [2, 3], [1, 2, 3], [1, 3], [2])]
        for min_count in 1:4
            @test check_optimized_against_oracle(transactions, min_count)
        end
    end

    @testset "Perfect extensions found at two depths of one path" begin
        # 2 covers t(1); 5 covers t({1, 4}) but not t(1).
        transactions = [[1, 2, 4, 5], [1, 2, 4, 5], [1, 2, 4, 5], [1, 2], [2, 5], [5]]
        @test check_optimized_against_oracle(transactions, 1)
        @test check_optimized_against_oracle(transactions, 3)
    end

    @testset "Supports at the threshold" begin
        transactions = [[1, 2, 3], [1, 2, 3], [3]]
        @test mine(transactions; minsup=2, variant=:optimized) ==
              SupportMap((1,)=>2, (2,)=>2, (3,)=>3, (1, 2)=>2, (1, 3)=>2, (2, 3)=>2, (1, 2, 3)=>2)
        @test mine(transactions; minsup=3, variant=:optimized) == SupportMap((3,)=>3)
    end

    @testset "The search restores the prefix and the perfect stack" begin
        database = [[1, 2, 3, 4], [1, 2, 4], [2, 3], [1, 3, 4], [1, 2, 3, 4]]
        class = ItemsetMining.bitset_class(database, 2)
        prefix, perfect = Int[], Int[]
        result = @inferred ItemsetMining.bitset_search!(class, prefix, perfect, 2,
                                                        FrequentItemsets(), Vector{UInt64}[])
        @test isempty(prefix) && isempty(perfect)
        @test support_map(result) == brute_force_supports(database, 2)
        @test length(result) == length(support_map(result))
    end

    @testset "Seeded databases built from co-occurring groups" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:200
            # Few groups of several items each make perfect extensions common at every depth.
            items = shuffle(rng, 0:11)
            cuts = sort!(rand(rng, 1:11, rand(rng, 1:4)))
            groups = [items[a+1:b] for (a, b) in zip([0; cuts], [cuts; 12]) if a < b]
            transactions = [vcat(Int[], (g for g in groups if rand(rng) < 0.6)...)
                            for _ in 1:rand(rng, 0:15)]
            @test check_optimized_against_oracle(transactions, rand(rng, 1:4))
        end
    end
end
