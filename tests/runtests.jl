using Test
using Random
using ItemsetMining

include("fixtures.jl")
include("oracle.jl")
include(joinpath(dirname(@__DIR__), "tools", "spmf", "compare.jl"))
include(joinpath(dirname(@__DIR__), "experiments", "Experiments.jl"))
include(joinpath(dirname(@__DIR__), "applications", "image_patterns", "SemeionPilot.jl"))
include(joinpath(dirname(@__DIR__), "applications", "market_basket", "MarketBasket.jl"))

@testset "Itemset setup" begin
    @testset "Support thresholds" begin
        @test support_threshold(2, 3) == 2
        @test support_threshold(1.0, 3) == 3
        @test support_threshold(0.5, 3) == 2
        @test support_threshold(0.07, 100) == 7
        @test support_threshold(0.1, 0) == 1
        for bad in (0, -1, 0.0, 1.1, NaN, Inf, true)
            @test_throws ArgumentError support_threshold(bad, 3)
        end
    end
    @testset "Mining input validation" begin
        for variant in (:baseline, :optimized),
            bad in ([[-1]], [[true]], [[1.5]], [[1], [typemax(UInt)]], [1, 2, 3], [[1], nothing], ["12"])
            @test_throws ArgumentError mine(bad; minsup=1, variant)
        end
        @test_throws "transaction 2" mine([[1], [-1]]; minsup=1)
        @test_throws ArgumentError mine([[1]]; minsup=1, variant=:unknown)
    end
    @testset "Item labels" begin
        transactions, labels = encode_transactions([["milk", "bread"], ["bread", "bread"], String[], ["beer"]])
        @test labels == ["beer", "bread", "milk"]
        @test transactions == [[2, 3], [2], Int[], [1]]
        @test decode_itemset(labels, (2, 3)) == ["bread", "milk"]
        @test_throws "4" decode_itemset(labels, (4,))
        @test_throws "row 2" encode_transactions([["a"], ["b", missing]])
    end
    @testset "SPMF input and fixture integrity" begin
        @test read_transactions(IOBuffer("@ITEM=0=zero\n% comment\n# comment\n\n2 0 2\n2 0\n")) == [[0,2], [0,2]]
        @test_throws "line 1" read_transactions(IOBuffer("1 -1\n"))
        for case in MINING_CASES
            transactions = read_transactions(joinpath(TOY_DIR, case.name * ".txt"))
            min_count = support_threshold(case.minsup, length(transactions))
            @test brute_force_supports(transactions, min_count) == case.expected
            expected_path = joinpath(TOY_DIR, case.name * ".expected.txt")
            @test sprint(write_itemsets, case.expected) ==
                  (isfile(expected_path) ? replace(read(expected_path, String), "\r\n"=>"\n") : "")
        end
        boundary = read_transactions(joinpath(TOY_DIR, "boundary.txt"))
        @test brute_force_supports(boundary, 1) == BOUNDARY_LOW_EXPECTED
        @test sprint(write_itemsets, BOUNDARY_LOW_EXPECTED) ==
              replace(read(joinpath(TOY_DIR, "boundary-count-1.expected.txt"), String), "\r\n"=>"\n")
        c = IMAGE_CASE
        n = length(c.transactions)
        @test brute_force_supports(c.transactions, support_threshold(c.minsup, n)) == c.expected
        @test brute_force_supports(c.transactions, support_threshold(c.sensitive_minsup, n)) == c.sensitive_expected
    end
    @testset "SPMF itemset records" begin
        text = "@FILETYPE=x\n% header\n\n2 1 #SUP: 3\n1 #SUP: 4\n1 2 #SUP: 5\n"
        @test read_itemset_records(IOBuffer(text)) == [
            (itemset=(1, 2), support=3, line=4),
            (itemset=(1,), support=4, line=5),
            (itemset=(1, 2), support=5, line=6),
        ]
        for bad in ("1 2 #SUP: x", "-1 #SUP: 2", "1 1 #SUP: 2", "#SUP: 1", "1 #SUP: 0", "1 2")
            @test_throws "line 2" read_itemset_records(IOBuffer("% header\n$bad\n"))
        end
    end
    include("spmf_compare.jl")
    @testset "SPMF transaction output" begin
        text = sprint(io -> write_transactions(io, [[2, 1], [2]]; labels=["beer", "bread"]))
        @test text == "@CONVERTED_FROM_TEXT\n@ITEM=1=beer\n@ITEM=2=bread\n1 2\n2\n"
        @test read_transactions(IOBuffer(text)) == [[1, 2], [2]]
        @test_throws ArgumentError write_transactions(IOBuffer(), [[1]]; labels=["a\nb"])
        # Digit counts from 1 to 19, a line longer than one write buffer, and many lines.
        rng = Xoshiro(DEFAULT_SEED)
        database = [[[0, 9, 10, 99, 1_048_575, 1_048_576, typemax(Int)], collect(0:20_000)];
                    [rand(rng, 0:2_000_000, rand(rng, 1:12)) for _ in 1:20_000]]
        text = sprint(write_transactions, database)
        @test text == join((join(sort!(unique(t)), ' ') * '\n' for t in database))
        @test read_transactions(IOBuffer(text)) == canonical_transaction.(database)
    end
    @testset "Writers validate before touching a file" begin
        path = tempname()
        write(path, "keep\n")
        @test_throws "transaction 2" write_transactions(path, [[1], Int[]])
        @test read(path, String) == "keep\n"
        for bad in (Dict((2, 1)=>2), Dict((1,)=>0), Dict(()=>1), Dict((true,)=>1), Dict((-1,)=>1), Dict((1, 1)=>1),
                    Dict([1, 2]=>1), Dict((1,)=>true), Dict((1,)=>1.0), Dict((1, typemax(UInt))=>1))
            @test_throws ArgumentError write_itemsets(path, bad)
            @test read(path, String) == "keep\n"
        end
    end
    @testset "Support map output order is numeric" begin
        @test sprint(write_itemsets, SupportMap((10,)=>1, (2,)=>1, (1, 10)=>1, (1, 2)=>1)) ==
              "1 2 #SUP: 1\n1 10 #SUP: 1\n2 #SUP: 1\n10 #SUP: 1\n"
        @test sprint(write_itemsets, Dict{Any,Any}((Int32(1), Int32(10))=>Int32(2))) == "1 10 #SUP: 2\n"
        rng = Xoshiro(DEFAULT_SEED)
        many = mine_packed([rand(rng, 0:30, rand(rng, 0:12)) for _ in 1:400]; minsup=2)
        @test sprint(write_itemsets, support_map(many)) == sprint(write_itemsets, many)
    end
    include("eclat.jl")
    include("eclat_optimized.jl")
    include("frequent_itemsets.jl")
    include("itemset_order.jl")
    include("transaction_reader.jl")
    include("itemset_record_reader.jl")
    include("cli.jl")
    include("precompile.jl")
    include("benchmark_data.jl")
    include("image_patterns.jl")
    include("image_encoding.jl")
    include("image_mining.jl")
    include("image_pilot_cli.jl")
    include("harness.jl")
    include("measurement_stages.jl")
    include("revisions.jl")
    include("runtime_curves.jl")
    include("join_work.jl")
    include("market_basket.jl")
    include("market_basket_rules.jl")
    include("market_basket_scripts.jl")
end
