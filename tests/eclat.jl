# Variants with an implementation; every case below runs against each of them.
const MINED_VARIANTS = (:baseline,)

@testset "Eclat vertical index" begin
    @test ItemsetMining.to_class([[1, 3], Int[], [0, 1], [1]]) ==
          [0 => [3], 1 => [1, 3, 4], 3 => [1]]
    @test ItemsetMining.to_class(Vector{Int}[]) == Pair{Int,Vector{Int}}[]
    @test ItemsetMining.to_class([[2], [2]]) == [2 => [1, 2]]
end

@testset "Eclat $variant" for variant in MINED_VARIANTS
    @testset "Toy fixtures" begin
        for case in MINING_CASES
            transactions = read_transactions(joinpath(TOY_DIR, case.name * ".txt"))
            @test mine(transactions; minsup=case.minsup, variant) == case.expected
        end
        boundary = read_transactions(joinpath(TOY_DIR, "boundary.txt"))
        @test mine(boundary; minsup=1, variant) == BOUNDARY_LOW_EXPECTED
        c = IMAGE_CASE
        @test mine(c.transactions; minsup=c.minsup, variant) == c.expected
        @test mine(c.transactions; minsup=c.sensitive_minsup, variant) == c.sensitive_expected
    end
    @testset "Threshold boundaries" begin
        @test mine([[1], [1], [2]]; minsup=2, variant) == SupportMap((1,)=>2)
        @test mine([[1], [1], [2]]; minsup=1, variant) == SupportMap((1,)=>2, (2,)=>1)
        @test mine([[1], [1], [2]]; minsup=4, variant) == SupportMap()
        @test mine(Vector{Int}[]; minsup=0.5, variant) == SupportMap()
        @test mine([[0, 1], [0]]; minsup=1, variant) == SupportMap((0,)=>2, (1,)=>1, (0, 1)=>1)
    end
    @testset "Joins stay inside one prefix class" begin
        # (1,2) and (3,4) are both frequent, but their tidset intersection is
        # t(1234), so a join across classes would give {1,2,4} support 1.
        patterns = mine([[1, 2, 3, 4], [1, 2, 4], [1, 2, 4]]; minsup=1, variant)
        @test patterns[(1, 2, 4)] == 3
        @test patterns == brute_force_supports([[1, 2, 3, 4], [1, 2, 4], [1, 2, 4]], 1)
    end
    @testset "Canonical keys" begin
        patterns = mine([[5, 1, 3], [3, 5], [1, 5, 3, 9]]; minsup=1, variant)
        @test all(key -> issorted(key; lt=<=), keys(patterns))
        @test all(!isempty, keys(patterns))
    end
    @testset "Independent of transaction order" begin
        rng = Xoshiro(DEFAULT_SEED)
        transactions = [rand(rng, 1:8, rand(rng, 0:6)) for _ in 1:30]
        expected = mine(transactions; minsup=3, variant)
        @test mine(shuffle(rng, transactions); minsup=3, variant) == expected
    end
    @testset "Random databases match the brute-force oracle" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:300
            transactions = [rand(rng, 0:11, rand(rng, 0:9)) for _ in 1:rand(rng, 0:20)]
            min_count = rand(rng, 1:5)
            @test mine(transactions; minsup=min_count, variant) ==
                  brute_force_supports(unique.(transactions), min_count)
        end
    end
    @testset "Type stability" begin
        @test @inferred(mine([[1, 2], [2]]; minsup=1, variant)) isa SupportMap
    end
end
