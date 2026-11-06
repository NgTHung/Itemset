@testset "Package image covers the public mining calls" begin
    # --trace-compile lists every method a fresh process compiles at run time, so an
    # empty ItemsetMining list means the cold CLI path runs from the package image.
    root = dirname(@__DIR__)
    script = """
    using ItemsetMining
    input, output = ARGS
    transactions = read_transactions(input)
    for minsup in (0.5, 2), variant in (:baseline, :optimized)
        write_itemsets(output, mine_packed(transactions; minsup, variant))
        write_itemsets(output, mine(transactions; minsup, variant))
    end
    """
    mktempdir() do dir
        trace = joinpath(dir, "trace.jl")
        output = joinpath(dir, "patterns.txt")
        command = `$(Base.julia_cmd()) --startup-file=no --project=$root --trace-compile=$trace
                   -e $script $(joinpath(TOY_DIR, "baskets.txt")) $output`
        run(command)
        @test filter(contains("ItemsetMining"), readlines(trace)) == String[]
        @test read(output, String) == sprint(write_itemsets, MINING_CASES[1].expected)
    end
end

@testset "A cold CLI run compiles nothing" begin
    # The CLI's own code must come from the package image too, or every run pays for it.
    root = dirname(@__DIR__)
    mktempdir() do dir
        trace = joinpath(dir, "trace.jl")
        output = joinpath(dir, "patterns.txt")
        for args in (["--min-count", "2", "--variant", "optimized", "--output", output, joinpath(TOY_DIR, "baskets.txt")],
                     ["--check-input", joinpath(TOY_DIR, "baskets.txt")])
            command = `$(Base.julia_cmd()) --startup-file=no --project=$root --trace-compile=$trace
                       $(joinpath(root, "demo.jl")) $args`
            rm(trace; force=true)
            run(pipeline(command; stdout=devnull))
            # Julia creates the trace file only when it compiles something.
            @test (isfile(trace) ? readlines(trace) : String[]) == String[]
        end
        @test read(output, String) == sprint(write_itemsets, MINING_CASES[1].expected)
    end
end
