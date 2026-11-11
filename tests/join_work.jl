using Random: Xoshiro

@testset "Intersection work of the baseline search" begin
    @testset "Hand-counted baskets" begin
        # Root class: tids of 1, 2, 3 have 3 entries each. The joins are
        # 1 with 2 (3+3, frequent), 1 with 3 (3+3, frequent), and inside class (1)
        # 2 with 3 (2+2, only tid 1: infrequent), then 2 with 3 at the root (3+3, frequent).
        work = Experiments.join_work(read_transactions(joinpath(TOY_DIR, "baskets.txt")), 2)
        @test work == (itemsets=6, frequent_items=3, joins=4, successful_joins=3, merged_elements=22)
    end

    @testset "Edges" begin
        none = (itemsets=0, frequent_items=0, joins=0, successful_joins=0, merged_elements=0)
        @test Experiments.join_work(Vector{Int}[], 1) == none
        @test Experiments.join_work([[1, 2], [1, 3]], 3) == none
        # One transaction: every join merges two one-tid lists, 4 joins of 2 elements.
        @test Experiments.join_work([[1, 2, 3]], 1) ==
              (itemsets=7, frequent_items=3, joins=4, successful_joins=4, merged_elements=8)
        @test_throws ArgumentError Experiments.join_work([[1]], 0)
        @test_throws ArgumentError Experiments.join_work([[1, -1]], 1)
    end

    @testset "Counts agree with the miner on random databases" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:80
            n = rand(rng, 1:14)
            transactions = [sort!(unique(rand(rng, 1:7, rand(rng, 0:5)))) for _ in 1:n]
            minsup = rand(rng, 1:max(1, n ÷ 2))
            work = Experiments.join_work(transactions, minsup)
            @test work.itemsets == length(mine(transactions; minsup))
            # Every itemset longer than one item comes from exactly one successful join.
            @test work.itemsets == work.frequent_items + work.successful_joins
            @test work.successful_joins <= work.joins
            # A frequent join read two lists that each held at least minsup tids.
            @test work.merged_elements >= 2 * minsup * work.successful_joins
        end
    end

    @testset "Rows for a configured experiment" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            config = toy_config(; series=[Dict("dataset" => "baskets", "minsup" => [0.5, 0.75])])
            rows = Experiments.join_work_rows(config, manifest, data)
            @test [(r.dataset, r.minsup_relative, r.minsup_count) for r in rows] ==
                  [("baskets", "0.75", 3), ("baskets", "0.5", 2)]
            @test rows[2].itemsets == 6 && rows[2].joins == 4 && rows[2].merged_elements == 22
            @test rows[1].itemsets == 3 && rows[1].joins == 3 && rows[1].successful_joins == 0
            missing_set = toy_config(; series=[Dict("dataset" => "nope", "minsup" => [0.5])])
            @test_throws ArgumentError Experiments.join_work_rows(missing_set, manifest, data)
        end
    end

    @testset "Table file" begin
        mktempdir() do dir
            rows = [(dataset="d", minsup_relative="0.5", minsup_count=2, itemsets=6, frequent_items=3,
                     joins=4, successful_joins=3, merged_elements=22)]
            path = joinpath(dir, "join-work.csv")
            Experiments.write_join_work(path, rows)
            @test Experiments.read_csv_rows(path) == [Dict("dataset"=>"d", "minsup_relative"=>"0.5", "minsup_count"=>"2",
                "itemsets"=>"6", "frequent_items"=>"3", "joins"=>"4", "successful_joins"=>"3", "merged_elements"=>"22")]
        end
    end
end

module JoinWorkScript
include(joinpath(dirname(@__DIR__), "scripts", "join_work.jl"))
end

@testset "Join work script" begin
    quiet(f) = redirect_stdout(f, devnull)
    mktempdir() do dir
        config = joinpath(dir, "config.toml")
        write(config, """
        name = "toy"
        variants = ["baseline"]
        repeats = 1
        timeout_seconds = 60
        [[series]]
        dataset = "baskets"
        minsup = [0.5]
        """)
        manifest, data = toy_benchmark(dir)
        @testset "Usage and bad arguments change nothing" begin
            @test quiet(() -> JoinWorkScript.main(["-h"])) == 0
            @test quiet(() -> JoinWorkScript.main(["--help"])) == 0
            fresh = joinpath(dir, "fresh")
            for bad in (String[], [config], ["--out", fresh], ["--out", fresh, config, config],
                        ["--out", fresh, "--bogus", config], ["--out"], ["--out", fresh, "-x"],
                        ["--out", fresh, joinpath(dir, "missing.toml")])
                @test_throws ArgumentError quiet(() -> JoinWorkScript.main(bad))
            end
            @test !ispath(fresh)
        end
    end
end
