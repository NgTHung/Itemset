using Test
using Random
using ItemsetMining

include("fixtures.jl")
include("oracle.jl")
include(joinpath(dirname(@__DIR__), "experiments", "Experiments.jl"))

@testset "Itemset setup" begin
    @testset "Transaction and support contract" begin
        @test canonical_transaction([2, 1, 2, 0]) == [0, 1, 2]
        @test_throws ArgumentError canonical_transaction([-1])
        @test_throws ArgumentError canonical_transaction([true])
        @test support_threshold(2, 3) == 2
        @test support_threshold(1, 3) == 1
        @test support_threshold(1.0, 3) == 3
        @test support_threshold(0.5, 3) == 2
        @test support_threshold(0.07, 100) == 7
        @test support_threshold(0.1, 0) == 1
        @test support_threshold(5, 3) == 5
        for bad in (0, -1, 0.0, -0.1, 1.1, NaN, Inf, true)
            @test_throws ArgumentError support_threshold(bad, 3)
        end
        @test_throws ArgumentError support_threshold(1, -1)
    end
    @testset "Mining input validation" begin
        @test ItemsetMining.canonical_database([[2, 1, 2], Int[], (3,)]) == [[1, 2], Int[], [3]]
        @test ItemsetMining.canonical_database([[2, 1]]) isa Vector{Vector{Int}}
        @test_throws "-1" canonical_transaction([-1])
        @test_throws ArgumentError canonical_transaction([typemax(UInt)])
        for variant in (:baseline, :optimized), bad in ([[-1]], [[true]], [[1.5]], [[1], [typemax(UInt)]])
            @test_throws ArgumentError mine(bad; minsup=1, variant)
        end
        @test_throws "transaction 2" mine([[1], [-1]]; minsup=1)
        for bad in ([1, 2, 3], [[1], nothing], [[1], missing], ["12"])
            @test_throws ArgumentError mine(bad; minsup=1)
        end
        @test_throws "transaction 2" mine([[1], nothing]; minsup=1)
    end
    @testset "Item labels" begin
        rows = [["milk", "bread"], ["bread", "bread"], String[], ["beer"]]
        transactions, labels = encode_transactions(rows)
        @test labels == ["beer", "bread", "milk"]
        @test transactions == [[2, 3], [2], Int[], [1]]
        @test encode_transactions(reverse(rows)) == (reverse(transactions), labels)
        @test decode_itemset(labels, (2, 3)) == ["bread", "milk"]
        @test [decode_itemset(labels, t) for t in transactions] == [sort(unique(r)) for r in rows]
        @test_throws ArgumentError decode_itemset(labels, (0,))
        @test_throws "4" decode_itemset(labels, (4,))
        @test_throws "row 2" encode_transactions([["a"], ["b", missing]])
        @test_throws ArgumentError encode_transactions([[nothing]])
        @test_throws "row 1" encode_transactions(["bread", "milk"])
        @test_throws "row 2" encode_transactions([["a"], missing])
        @test_throws "row 2" encode_transactions([["a"], ["b", " "]])
        single_pass_rows = (split(l, ",") for l in eachline(IOBuffer("bread,milk\nbeer\n")))
        @test encode_transactions(single_pass_rows) == ([[2, 3], [1]], ["beer", "bread", "milk"])
    end
    @testset "Brute-force oracle" begin
        @test brute_force_supports([[1, 2], [2]], 1) == SupportMap((1,)=>1, (2,)=>2, (1,2)=>1)
        @test brute_force_supports([[1, 2], [2]], 2) == SupportMap((2,)=>2)
        @test brute_force_supports(Vector{Int}[], 1) == SupportMap()
        @test brute_force_supports([[0], Int[]], 1) == SupportMap((0,)=>1)
        @test_throws ArgumentError brute_force_supports([collect(1:17)], 1)
        for case in MINING_CASES, key in keys(case.expected), drop in eachindex(key)
            length(key) > 1 && @test haskey(case.expected, Tuple(deleteat!(collect(key), drop)))
        end
    end
    @testset "SPMF input and fixture integrity" begin
        @test read_transactions(IOBuffer("@ITEM=0=zero\n% comment\n# comment\n\n2 0 2\n2 0\n")) == [[0,2], [0,2]]
        @test_throws ArgumentError read_transactions(IOBuffer("1 -1\n"))
        @test_throws ArgumentError read_transactions(IOBuffer("1 x\n"))
        @test length(MINING_CASES) == 6
        for case in MINING_CASES
            transactions = read_transactions(joinpath(TOY_DIR, case.name * ".txt"))
            min_count = support_threshold(case.minsup, length(transactions))
            @test brute_force_supports(transactions, min_count) == case.expected
            io = IOBuffer()
            write_itemsets(io, case.expected)
            actual = String(take!(io))
            expected_path = joinpath(TOY_DIR, case.name * ".expected.txt")
            @test actual == (isfile(expected_path) ? replace(read(expected_path, String), "\r\n"=>"\n") : "")
        end
    end
    @testset "Market basket fixture" begin
        transactions, labels = encode_transactions(GROCERY_ROWS)
        @test labels == ["beer", "bread", "butter", "milk"]
        path = joinpath(TOY_DIR, "groceries.txt")
        @test transactions == read_transactions(path)
        @test replace(read(path, String), "\r\n"=>"\n") == sprint(io -> write_transactions(io, transactions; labels))
        patterns = only(c for c in MINING_CASES if c.name == "groceries").expected
        n = length(transactions)
        for r in GROCERY_RULES
            union_key = Tuple(sort([r.antecedent..., r.consequent...]))
            @test r.support == patterns[union_key]
            @test r.confidence == r.support // patterns[r.antecedent]
            @test r.lift == r.confidence / (patterns[r.consequent] // n)
        end
        @test length(GROCERY_RULES) == sum(2^length(k) - 2 for k in keys(patterns) if length(k) >= 2)
    end
    @testset "Image-pattern fixture" begin
        c = IMAGE_CASE
        @test [findall(row) for row in eachrow(c.presence)] == c.transactions
        n = length(c.transactions)
        @test brute_force_supports(c.transactions, support_threshold(c.minsup, n)) == c.expected
        @test keys(c.supporting_images) == keys(c.expected)
        for (k, images) in c.supporting_images
            @test images == findall(t -> issubset(k, t), c.transactions)
            @test length(images) == c.expected[k]
        end
        @test brute_force_supports(c.transactions, support_threshold(c.sensitive_minsup, n)) == c.sensitive_expected
        @test_throws ArgumentError write_transactions(IOBuffer(), c.transactions)
        kept = filter(!isempty, c.transactions)
        @test brute_force_supports(kept, support_threshold(c.sensitive_minsup, length(kept))) == c.expected
    end
    @testset "SPMF transaction output" begin
        io = IOBuffer()
        write_transactions(io, [[3, 1], [2]])
        @test String(take!(io)) == "1 3\n2\n"
        io = IOBuffer()
        write_transactions(io, [[2, 1]]; labels=["beer", "bread"])
        text = String(take!(io))
        @test text == "@CONVERTED_FROM_TEXT\n@ITEM=1=beer\n@ITEM=2=bread\n1 2\n"
        @test read_transactions(IOBuffer(text)) == [[1, 2]]
        io = IOBuffer()
        @test_throws "transaction 2" write_transactions(io, [[1], Int[]])
        @test position(io) == 0
        @test_throws ArgumentError write_transactions(IOBuffer(), [[3]]; labels=["a"])
        @test_throws ArgumentError write_transactions(IOBuffer(), [[0]]; labels=["a"])
        @test_throws ArgumentError write_transactions(IOBuffer(), [[1]]; labels=["a\nb"])
    end
    @testset "Writers keep files on invalid input" begin
        path = tempname()
        write(path, "keep\n")
        @test_throws ArgumentError write_transactions(path, [[1], Int[]])
        @test read(path, String) == "keep\n"
        @test_throws ArgumentError write_itemsets(path, Dict((2, 1)=>2))
        @test read(path, String) == "keep\n"
    end
    include("eclat.jl")
    @testset "Invalid output and unfinished miner" begin
        @test_throws ArgumentError write_itemsets(IOBuffer(), Dict((2,1)=>2))
        @test_throws ArgumentError write_itemsets(IOBuffer(), Dict((1,)=>0))
        @test_throws ArgumentError write_itemsets(IOBuffer(), Dict(()=>1))
        io = IOBuffer()
        write_itemsets(io, SupportMap((10,)=>1, (2,)=>1, (1, 10)=>1, (1, 2)=>1))
        @test String(take!(io)) == "1 2 #SUP: 1\n1 10 #SUP: 1\n2 #SUP: 1\n10 #SUP: 1\n"
        @test_throws ArgumentError mine([[1]]; minsup=1, variant=:unknown)
        @test_throws ErrorException mine([[1]]; minsup=1, variant=:optimized)
    end
    @testset "CLI" begin
        include(joinpath(dirname(@__DIR__), "demo.jl"))
        @test main(["--help"]) == 0
        @test main(["--check-input", joinpath(TOY_DIR, "baskets.txt")]) == 0
        @test_throws ArgumentError main(["--unknown"])
        @test_throws ArgumentError main(["--minsup"])
        @test_throws ArgumentError main(["--check-input"])
        mktempdir() do dir
            output = joinpath(dir, "patterns.txt")
            for case in MINING_CASES
                input = joinpath(TOY_DIR, case.name * ".txt")
                threshold = case.minsup isa Integer ? "--min-count" : "--minsup"
                @test main([threshold, string(case.minsup), "--variant", "baseline", "--output", output, input]) == 0
                @test read(output, String) == sprint(write_itemsets, case.expected)
            end
            baskets = joinpath(TOY_DIR, "baskets.txt")
            @test main(["--minsup", "0.5", "--output", output, baskets]) == 0
            @test read(output, String) == replace(read(joinpath(TOY_DIR, "baskets.expected.txt"), String), "\r\n"=>"\n")
            @test_throws "exactly one support threshold" main(["--minsup", "0.5", "--min-count", "2", "--output", output, baskets])
            @test_throws "are required" main(["--minsup", "0.5", baskets])
            @test_throws "must differ" main(["--min-count", "2", "--output", baskets, baskets])
            @test_throws "only one input" main(["--min-count", "2", "--output", output, baskets, baskets])
            @test_throws "variant must be" main(["--min-count", "2", "--variant", "fast", "--output", output, baskets])
            @test_throws ArgumentError main(["--minsup", "2", "--output", output, baskets])
            @test_throws ArgumentError main(["--min-count", "0.5", "--output", output, baskets])
        end
    end
    include("benchmark_data.jl")
end
