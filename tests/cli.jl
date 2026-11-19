main(args) = ItemsetMining.cli_main(args)

threshold_flag(minsup) = minsup isa Integer ? "--min-count" : "--minsup"

@testset "CLI" begin
    @test main(["--check-input", joinpath(TOY_DIR, "baskets.txt")]) == 0
    mktempdir() do dir
        output = joinpath(dir, "patterns.txt")
        baskets = joinpath(TOY_DIR, "baskets.txt")
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
        @testset "Argument errors" begin
            @test_throws "exactly one support threshold" main(["--minsup", "0.5", "--min-count", "2", "--output", output, baskets])
            @test_throws "are required" main(["--minsup", "0.5", baskets])
            @test_throws "must differ" main(["--min-count", "2", "--output", baskets, baskets])
            @test_throws "variant must be" main(["--min-count", "2", "--variant", "fast", "--output", output, baskets])
            @test_throws "--minsup needs a value" main(["--minsup", "--output", output, baskets])
        end
        @testset "A failed process exits 1 and leaves existing output untouched" begin
            root = dirname(@__DIR__)
            demo = `$(Base.julia_cmd()) --startup-file=no --project=$root $(joinpath(root, "demo.jl"))`
            write(output, "keep\n")
            err = IOBuffer()
            process = run(pipeline(ignorestatus(`$demo --min-count 2 --output $output $malformed`); stderr=err))
            @test process.exitcode == 1
            @test occursin("line 2", String(take!(err)))
            @test read(output, String) == "keep\n"
        end
    end
end
