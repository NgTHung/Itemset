# Variants with an implementation; every case below runs against each of them.
const MINED_VARIANTS = (:baseline, :optimized)

@testset "Bottom-Up search is type-stable" begin
    class = ItemsetMining.to_class([[1, 2, 3], [1, 2], [2, 3]])
    prefix = Int[]
    patterns = @inferred ItemsetMining.bottom_up!(class, prefix, 2, FrequentItemsets())
    @test support_map(patterns) == SupportMap((1,)=>2, (2,)=>3, (3,)=>2, (1, 2)=>2, (2, 3)=>2)
    # The prefix is a shared stack, so every search must leave it as it found it.
    @test isempty(prefix)
end

@testset "Eclat $variant" for variant in MINED_VARIANTS
    @testset "SPMF reference outputs" begin
        for r in SPMF_TOY_RUNS
            transactions = read_transactions(joinpath(TOY_DIR, r.input))
            reference = open(parse_itemsets, joinpath(SPMF_TOY_DIR, r.output)).itemsets
            @test mine(transactions; minsup=r.minsup, variant) == reference
        end
    end
    @testset "SPMF correctness database" begin
        for r in SPMF_CORRECTNESS_RUNS
            transactions = read_transactions(joinpath(CORRECTNESS_DIR, r.input))
            reference = open(parse_itemsets, joinpath(SPMF_CORRECTNESS_DIR, r.output))
            mined = ParsedItemsets(mine(transactions; minsup=r.minsup, variant), DuplicateRecord[])
            result = compare_itemsets(reference, mined)
            # Counts instead of maps, so a failure prints three numbers, not 14,000 itemsets.
            @test (missing=length(result.missing), extra=length(result.extra),
                   mismatched=length(result.support_mismatches)) == (missing=0, extra=0, mismatched=0)
            @test result.matches
        end
    end
    @testset "Empty transactions count toward a relative threshold" begin
        c = IMAGE_CASE
        @test mine(c.transactions; minsup=c.minsup, variant) == c.expected
        @test mine(c.transactions; minsup=c.sensitive_minsup, variant) == c.sensitive_expected
    end
    @testset "Type stability" begin
        @test @inferred(mine([[1, 2], [2]]; minsup=1, variant)) isa SupportMap
    end
end
