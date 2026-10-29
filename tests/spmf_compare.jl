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
    @testset "Duplicate keys keep their supports and never match" begin
        parsed = parse_itemsets(IOBuffer("2 1 #SUP: 2\n1 2 #SUP: 5\n"))
        @test parsed.itemsets == SupportMap((1, 2)=>2)
        @test parsed.duplicates == [(itemset=(1, 2), support=5, line=2)]
        result = compare_itemsets(parse_itemsets(IOBuffer("1 2 #SUP: 2\n")), parsed)
        @test !result.matches
        @test result.match_rate == 0.0
        @test occursin("(1, 2) support 5 at line 2", sprint(print_comparison, result))
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
    @testset "Command exit codes" begin
        mktempdir() do dir
            file(name, text) = (path = joinpath(dir, name); write(path, text); path)
            good = file("good.txt", "1 #SUP: 3\n")
            wrong = file("wrong.txt", "1 #SUP: 4\n")
            duplicated = file("duplicated.txt", "1 #SUP: 3\n1 #SUP: 5\n")
            malformed = file("malformed.txt", "1 #SUP: x\n")
            function compare_files(reference, candidate)
                out, err = IOBuffer(), IOBuffer()
                code = spmf_main([reference, candidate]; out, err)
                return (code, String(take!(out)), String(take!(err)))
            end
            code, out, _ = compare_files(good, good)
            @test code == 0
            @test occursin("Exact-map match rate: 100.0%", out)
            code, out, _ = compare_files(good, wrong)
            @test code == 1
            @test occursin("Support mismatches: ((1,), 3, 4)", out)
            @test compare_files(good, duplicated)[1] == 1
            code, out, err = compare_files(good, malformed)
            @test code == 2
            @test isempty(out)
            @test occursin(malformed, err) && occursin("line 1", err)
            @test_throws ArgumentError spmf_main([good])
            @test_throws SystemError spmf_main([good, joinpath(dir, "absent.txt")]; err=IOBuffer())
            script = joinpath(dirname(@__DIR__), "tools", "spmf", "compare.jl")
            command = `$(Base.julia_cmd()) --startup-file=no --project=$(dirname(@__DIR__)) $script $good`
            @test run(pipeline(ignorestatus(command); stderr=devnull)).exitcode == 3
        end
    end
    @testset "Reference thresholds give SPMF's count" begin
        @test length(SPMF_TOY_RUNS) == 8
        @test length(unique(r.input for r in SPMF_TOY_RUNS)) >= 5
        for r in SPMF_TOY_RUNS
            n = length(read_transactions(joinpath(TOY_DIR, r.input)))
            @test support_threshold(r.minsup, n) == r.count
            @test Experiments.threshold_agrees(r.minsup, n)
            @test isempty(open(parse_itemsets, joinpath(SPMF_TOY_DIR, r.output)).duplicates)
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
            reference = open(parse_itemsets, joinpath(SPMF_CORRECTNESS_DIR, r.output))
            @test isempty(reference.duplicates)
            # The database exists to reach depths and sizes the toy fixtures cannot.
            @test length(reference.itemsets) >= 10_000
            @test maximum(length, keys(reference.itemsets)) >= 10
            @test count(==(r.count), values(reference.itemsets)) >= 100
        end
    end
end
