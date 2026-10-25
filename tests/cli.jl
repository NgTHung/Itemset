include(joinpath(dirname(@__DIR__), "demo.jl"))

threshold_flag(minsup) = minsup isa Integer ? "--min-count" : "--minsup"

@testset "CLI" begin
    @test main(["--help"]) == 0
    @test main(["--check-input", joinpath(TOY_DIR, "baskets.txt")]) == 0
    @test_throws "unknown option --unknown" main(["--unknown"])
    @test_throws "--minsup needs a value" main(["--minsup"])
    @test_throws "exactly one path" main(["--check-input"])
    mktempdir() do dir
        output = joinpath(dir, "patterns.txt")
        baskets = joinpath(TOY_DIR, "baskets.txt")
        baskets_expected = replace(read(joinpath(TOY_DIR, "baskets.expected.txt"), String), "\r\n"=>"\n")
        malformed = joinpath(dir, "malformed.txt")
        write(malformed, "1 2\n1 x\n")
        @testset "Toy fixtures with $variant" for variant in MINED_VARIANTS
            for case in MINING_CASES
                input = joinpath(TOY_DIR, case.name * ".txt")
                args = [threshold_flag(case.minsup), string(case.minsup), "--variant", string(variant), "--output", output, input]
                @test main(args) == 0
                @test read(output, String) == sprint(write_itemsets, case.expected)
            end
        end
        @testset "SPMF reference outputs with $variant" for variant in MINED_VARIANTS
            for r in SPMF_TOY_RUNS
                input = joinpath(TOY_DIR, r.input)
                @test main([threshold_flag(r.minsup), string(r.minsup), "--variant", string(variant), "--output", output, input]) == 0
                reference = open(parse_itemsets, joinpath(SPMF_TOY_DIR, r.output))
                @test compare_itemsets(reference, open(parse_itemsets, output)).matches
            end
        end
        @testset "Default variant and argument errors" begin
            @test main(["--minsup", "0.5", "--output", output, baskets]) == 0
            @test read(output, String) == baskets_expected
            @test_throws "exactly one support threshold" main(["--minsup", "0.5", "--min-count", "2", "--output", output, baskets])
            @test_throws "are required" main(["--minsup", "0.5", baskets])
            @test_throws "must differ" main(["--min-count", "2", "--output", baskets, baskets])
            @test_throws "only one input" main(["--min-count", "2", "--output", output, baskets, baskets])
            @test_throws "variant must be" main(["--min-count", "2", "--variant", "fast", "--output", output, baskets])
            @test_throws "\"0.5\"" main(["--min-count", "0.5", "--output", output, baskets])
            @test_throws ArgumentError main(["--minsup", "2", "--output", output, baskets])
        end
        @testset "An option never takes the next option as its value" begin
            @test_throws "--output needs a value" main(["--minsup", "0.5", "--output", "--variant", "baseline", baskets])
            @test_throws "--minsup needs a value" main(["--minsup", "--output", output, baskets])
        end
        @testset "Failures leave existing output untouched" begin
            write(output, "keep\n")
            @test_throws "line 2" main(["--min-count", "1", "--output", output, malformed])
            @test read(output, String) == "keep\n"
            for variant in setdiff((:baseline, :optimized), MINED_VARIANTS)
                @test_throws "not implemented" main(["--min-count", "2", "--variant", string(variant), "--output", output, baskets])
                @test read(output, String) == "keep\n"
            end
        end
        @testset "Process exit codes and stderr" begin
            root = dirname(@__DIR__)
            demo = `$(Base.julia_cmd()) --startup-file=no --project=$root $(joinpath(root, "demo.jl"))`
            function run_demo(args...)
                out, err = IOBuffer(), IOBuffer()
                process = run(pipeline(ignorestatus(`$demo $(collect(args))`); stdout=out, stderr=err))
                return (code=process.exitcode, out=String(take!(out)), err=String(take!(err)))
            end
            success = run_demo("--min-count", "2", "--output", output, baskets)
            @test success.code == 0
            @test isempty(success.err)
            @test read(output, String) == baskets_expected
            write(output, "keep\n")
            failure = run_demo("--min-count", "2", "--output", output, malformed)
            @test failure.code == 1
            @test startswith(failure.err, "ERROR: ")
            @test occursin("line 2", failure.err) && occursin("\"x\"", failure.err)
            @test read(output, String) == "keep\n"
        end
    end
end
