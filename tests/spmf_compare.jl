@testset "SPMF output comparator" begin
    @testset "Canonical parsing and metadata" begin
        parsed = parse_itemsets(IOBuffer("@ITEM=1=one\n% reference\n# comment\n2 1 #SUP: 3\n\n"))
        @test parsed.itemsets == SupportMap((1, 2)=>3)
        @test isempty(parsed.duplicates)
    end
    @testset "Exact complete-map comparison" begin
        reference = parse_itemsets(IOBuffer("1 2 #SUP: 2\n1 #SUP: 3\n"))
        candidate = parse_itemsets(IOBuffer("1 #SUP: 3\n2 1 #SUP: 2\n"))
        result = compare_itemsets(reference, candidate)
        @test result.matches
        @test result.match_rate == 1.0
        @test isempty(result.missing)
        @test isempty(result.extra)
        @test isempty(result.support_mismatches)
    end
    @testset "Missing, extra, and mismatched entries" begin
        reference = parse_itemsets(IOBuffer("1 #SUP: 3\n2 #SUP: 2\n"))
        candidate = parse_itemsets(IOBuffer("1 #SUP: 4\n3 #SUP: 1\n"))
        result = compare_itemsets(reference, candidate)
        @test !result.matches
        @test result.missing == [(2,)]
        @test result.extra == [(3,)]
        @test result.support_mismatches == [((1,), 3, 4)]
        @test result.match_rate == 0.0
    end
    @testset "Duplicate keys are retained as diagnostics" begin
        parsed = parse_itemsets(IOBuffer("2 1 #SUP: 2\n1 2 #SUP: 2\n"))
        @test parsed.itemsets == SupportMap((1, 2)=>2)
        @test parsed.duplicates == [((1, 2), 2)]
        @test !compare_itemsets(parsed, parsed).matches
    end
    @testset "Malformed output identifies its line" begin
        for bad in ("1 2 #SUP: x", "-1 #SUP: 2", "1 1 #SUP: 2", "#SUP: 1", "1 #SUP: 0")
            @test_throws "line 2" parse_itemsets(IOBuffer("% header\n$bad\n"))
        end
    end
    @testset "Empty maps compare exactly" begin
        result = compare_itemsets(parse_itemsets(IOBuffer("")), parse_itemsets(IOBuffer("% no patterns\n")))
        @test result.matches
        @test result.match_rate == 1.0
    end
end
