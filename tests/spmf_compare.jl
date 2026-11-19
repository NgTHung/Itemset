@testset "SPMF output comparator" begin
    @testset "Exact complete-map comparison" begin
        reference = parse_itemsets(IOBuffer("@ITEM=1=one\n% reference\n1 2 #SUP: 2\n1 #SUP: 3\n"))
        result = compare_itemsets(reference, parse_itemsets(IOBuffer("1 #SUP: 3\n2 1 #SUP: 2\n")))
        @test result.matches && result.match_rate == 1.0
    end
    @testset "Missing, extra, and mismatched entries" begin
        reference = parse_itemsets(IOBuffer("1 #SUP: 3\n2 #SUP: 2\n"))
        candidate = parse_itemsets(IOBuffer("1 #SUP: 4\n3 #SUP: 1\n"))
        result = compare_itemsets(reference, candidate)
        @test !result.matches
        @test result.missing == [(2,)]
        @test result.extra == [(3,)]
        @test result.support_mismatches == [((1,), 3, 4)]
    end
    @testset "Duplicate keys never match" begin
        parsed = parse_itemsets(IOBuffer("2 1 #SUP: 2\n1 2 #SUP: 5\n"))
        @test parsed.duplicates == [(itemset=(1, 2), support=5, line=2)]
        @test !compare_itemsets(parse_itemsets(IOBuffer("1 2 #SUP: 2\n")), parsed).matches
    end
    @testset "Command exit codes" begin
        mktempdir() do dir
            file(name, text) = (path = joinpath(dir, name); write(path, text); path)
            good = file("good.txt", "1 #SUP: 3\n")
            compare(candidate) = spmf_main([good, candidate]; out=IOBuffer(), err=IOBuffer())
            @test compare(good) == 0
            @test compare(file("wrong.txt", "1 #SUP: 4\n")) == 1
            @test compare(file("malformed.txt", "1 #SUP: x\n")) == 2
        end
    end
    @testset "Reference thresholds give SPMF's count" begin
        @test length(unique(r.input for r in SPMF_TOY_RUNS)) >= 5
        for r in SPMF_TOY_RUNS
            n = length(read_transactions(joinpath(TOY_DIR, r.input)))
            @test support_threshold(r.minsup, n) == r.count
            @test Experiments.threshold_agrees(r.minsup, n)
        end
    end
    @testset "Correctness database reference" begin
        @test !isempty(SPMF_CORRECTNESS_RUNS)
        for r in SPMF_CORRECTNESS_RUNS
            path = joinpath(CORRECTNESS_DIR, r.input)
            @test Experiments.file_sha256(path) == r.input_sha256
            n = length(read_transactions(path))
            @test support_threshold(r.minsup, n) == r.count
            @test Experiments.threshold_agrees(r.minsup, n)
        end
    end
end
