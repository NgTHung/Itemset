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
