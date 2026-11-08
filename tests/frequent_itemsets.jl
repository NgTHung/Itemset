@testset "Packed frequent itemsets" begin
    @testset "Layout" begin
        packed = FrequentItemsets([1, 1, 2, 3], [1, 2, 4, 5], [4, 2, 3])
        @test collect(packed) == [[1] => 4, [1, 2] => 2, [3] => 3]
        @test support_map(packed) == SupportMap((1,)=>4, (1, 2)=>2, (3,)=>3)
        for (items, offsets, supports) in (([1], [1, 3], [1]), ([1, 2], [1, 3, 2], [1, 1]), ([1], [1, 2], [1, 1]))
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
        boundary = read_transactions(joinpath(TOY_DIR, "boundary.txt"))
        @test support_map(mine_packed(boundary; minsup=1, variant)) == BOUNDARY_LOW_EXPECTED
        rng = Xoshiro(DEFAULT_SEED)
        # Equal maps and equal counts also prove each itemset ascending and emitted once.
        for _ in 1:300
            transactions = [rand(rng, 0:11, rand(rng, 0:9)) for _ in 1:rand(rng, 0:20)]
            min_count = rand(rng, 1:5)
            packed = mine_packed(transactions; minsup=min_count, variant)
            expected = brute_force_supports(unique.(transactions), min_count)
            @test support_map(packed) == expected
            @test length(packed) == length(expected)
        end
        @test @inferred(mine_packed([[1, 2], [2]]; minsup=1, variant)) isa FrequentItemsets
    end
end

# The line format the writer must reproduce byte for byte, in numeric lexicographic order.
reference_lines(pairs) = join(("$(join(k, ' ')) #SUP: $v\n" for (k, v) in sort!([collect(k) => v for (k, v) in pairs]; by=first)))

@testset "Writing packed itemsets" begin
    # Unsorted input, multi-digit IDs, item 0, and a line longer than any buffer chunk.
    long = collect(0:20_000)
    packed = FrequentItemsets([10, 2, 0, 1, 10, 1, long...], [1, 2, 3, 4, 6, 7, 7 + length(long)],
                              [1, 7, 3, 12, 5, typemax(Int)])
    @test sprint(write_itemsets, packed) == reference_lines(packed)
    rng = Xoshiro(DEFAULT_SEED)
    many = mine_packed([rand(rng, 0:30, rand(rng, 0:12)) for _ in 1:400]; minsup=2)
    @test length(many) > 5_000
    @test sprint(write_itemsets, many) == reference_lines(many)
    @test sprint(write_itemsets, FrequentItemsets()) == ""
    # Every digit count from 1 to 19, and enough lines to cross many buffer flushes.
    limit = ItemsetMining.DIGIT_TABLE_LENGTH
    edges = sort!(unique([0; [10^d + s for d in 0:18 for s in (-1, 0)]; limit-1:limit+1; typemax(Int)]))
    edge_singles = FrequentItemsets(edges, collect(1:length(edges)+1), max.(edges, 1))
    @test sprint(write_itemsets, edge_singles) == reference_lines(edge_singles)
    edge_set = FrequentItemsets(edges, [1, length(edges) + 1], [typemax(Int)])
    @test sprint(write_itemsets, edge_set) == reference_lines(edge_set)
    singles = FrequentItemsets(collect(0:99_999), collect(1:100_001), collect(100_000:-1:1))
    @test sprint(write_itemsets, singles) == reference_lines(singles)
    for (items, offsets, supports) in (([2, 1], [1, 3], [1]), ([1, 1], [1, 3], [1]), (Int[], [1, 1], [1]),
                                       ([-1], [1, 2], [1]), ([1], [1, 2], [0]), ([1, 1], [1, 2, 3], [1, 2]))
        bad = FrequentItemsets(items, offsets, supports)
        path = tempname()
        write(path, "keep\n")
        @test_throws ArgumentError write_itemsets(path, bad)
        @test read(path, String) == "keep\n"
    end
end
