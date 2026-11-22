@testset "Stage profile of the optimized CLI path" begin
    @testset "A stack goes to the group of its innermost known function" begin
        group = Experiments.stage_group
        @test group([:intersect_bitsets!, :join_members!, :eclat_search!]) == "bitset joins"
        @test group([:getindex, :count_items, :mine_optimized]) == "item counts"
        # The innermost frame wins, so a sort called from the writer counts as the sort.
        @test group([:sort!, :lexicographic_order, :write_itemsets]) == "sort"
        @test group([:put_digits!, :print_packed, :write_itemsets]) == "format"
        @test group([:jl_gc_collect, :mine_packed]) == "other"
        @test group(Symbol[]) == "other"
    end

    @testset "Idle threads are dropped, not counted as other" begin
        @test Experiments.stage_group([:ZwWaitForAlertByThreadId, :SleepConditionVariableCS]) === nothing
        @test Experiments.stage_group([:pthread_cond_wait, :uv_cond_wait]) === nothing
    end

    @testset "Every group names a function the package defines" begin
        defined = String.(names(ItemsetMining; all=true, imported=false))
        for (label, pattern) in Experiments.STAGE_GROUPS
            @test any(name -> occursin(pattern, name), defined)
        end
        @test allunique(first.(Experiments.STAGE_GROUPS))
        @test !any(label -> label == "other", first.(Experiments.STAGE_GROUPS))
    end

    @testset "Shares count samples, not idle time" begin
        stacks = [[:intersect_bitsets!], [:intersect_bitsets!], [:count_items], [:ZwWaitForAlertByThreadId], [:mystery]]
        shares = Experiments.stage_shares(stacks)
        @test shares["bitset joins"] == 0.5
        @test shares["item counts"] == 0.25
        @test shares["other"] == 0.25
        @test sum(values(shares)) ≈ 1
        none = Experiments.stage_shares([[:ZwWaitForAlertByThreadId]])
        @test all(iszero, values(none))
        @test keys(none) == keys(shares)
    end

    @testset "Rows for a configured experiment" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            config = toy_config(; series=[Dict("dataset" => "baskets", "minsup" => [0.5, 0.75])])
            rows = Experiments.stage_profile_rows(config, manifest, data; repeats=2)
            @test [(r.dataset, r.minsup_relative, r.minsup_count) for r in rows] ==
                  [("baskets", "0.75", 3), ("baskets", "0.5", 2)]
            @test rows[2].transactions == 4 && rows[2].itemsets == 6 && rows[1].itemsets == 3
            for r in rows
                @test r.read_seconds >= 0 && r.mine_seconds >= 0 && r.write_seconds >= 0 && r.gc_seconds >= 0
                @test r.samples >= 0
                shares = [getfield(r, Symbol(f)) for f in Experiments.STAGE_PROFILE_FIELDS if startswith(f, "share_")]
                @test length(shares) == length(Experiments.STAGE_GROUPS) + 1
                @test sum(shares) ≈ (r.samples == 0 ? 0 : 1)
            end
            missing_set = toy_config(; series=[Dict("dataset" => "nope", "minsup" => [0.5])])
            @test_throws ArgumentError Experiments.stage_profile_rows(missing_set, manifest, data; repeats=1)
            @test_throws ArgumentError Experiments.stage_profile_rows(config, manifest, data; repeats=0)
        end
    end

    @testset "Table file" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            rows = Experiments.stage_profile_rows(toy_config(), manifest, data; repeats=1)
            path = joinpath(dir, "stage-profile.csv")
            Experiments.write_stage_profile(path, rows)
            back = Experiments.read_csv_rows(path)
            @test length(back) == 1
            @test collect(keys(only(back))) |> sort == sort(Experiments.STAGE_PROFILE_FIELDS)
            @test only(back)["itemsets"] == "6" && only(back)["dataset"] == "baskets"
        end
    end

    @testset "The committed configuration names verified benchmark files" begin
        config = Experiments.load_run_config(joinpath(dirname(@__DIR__), "experiments", "configs", "stage-profile.toml"))
        manifest = Experiments.load_manifest(joinpath(dirname(@__DIR__), "data", "benchmark", "manifest.toml"))
        @test !isempty(config.series)
        @test all(s -> haskey(manifest, s.dataset), config.series)
    end
end

module StageProfileScript
include(joinpath(dirname(@__DIR__), "scripts", "stage_profile.jl"))
end

@testset "Stage profile script" begin
    quiet(f) = redirect_stdout(f, devnull)
    mktempdir() do dir
        config = joinpath(dir, "config.toml")
        write(config, """
        name = "toy"
        variants = ["optimized"]
        repeats = 1
        timeout_seconds = 60
        [[series]]
        dataset = "baskets"
        minsup = [0.5]
        """)
        manifest, data = toy_benchmark(dir)
        @testset "Usage and bad arguments change nothing" begin
            @test quiet(() -> StageProfileScript.main(["-h"])) == 0
            @test quiet(() -> StageProfileScript.main(["--help"])) == 0
            fresh = joinpath(dir, "fresh")
            for bad in (String[], [config], ["--out", fresh], ["--out", fresh, config, config],
                        ["--out", fresh, "--bogus", config], ["--out"], ["--out", fresh, "--repeats", "0", config],
                        ["--out", fresh, "--repeats", "x", config], ["--out", fresh, "--repeats"],
                        ["--out", fresh, joinpath(dir, "missing.toml")])
                @test_throws ArgumentError quiet(() -> StageProfileScript.main(bad))
            end
            @test !ispath(fresh)
        end
        @testset "A manifest beside the benchmark one profiles a width database" begin
            settings = Experiments.WidthSettings(transactions=50, items=8, widths=[3])
            width_dir = mkpath(joinpath(dir, "width-data"))
            width_manifest = joinpath(dir, "width-manifest.toml")
            Experiments.freeze_width_manifest(width_manifest, settings, width_dir)
            width_config = joinpath(dir, "width.toml")
            write(width_config, """
            name = "width"
            variants = ["optimized"]
            repeats = 1
            timeout_seconds = 60
            [[series]]
            dataset = "width-w03"
            minsup = [0.5]
            """)
            out = joinpath(dir, "width-out")
            @test quiet(() -> StageProfileScript.main(["--out", out, "--repeats", "2", "--manifest", width_manifest,
                                                       width_config]; data_dir=width_dir)) == 0
            rows = Experiments.read_csv_rows(joinpath(out, "stage-profile.csv"))
            database = Experiments.width_database(settings, 3)
            @test only(rows)["dataset"] == "width-w03"
            @test parse(Int, only(rows)["itemsets"]) == Experiments.output_count(database, support_threshold(0.5, 50))
            @test_throws ArgumentError quiet(() -> StageProfileScript.main(
                ["--out", joinpath(dir, "never"), "--manifest", joinpath(dir, "missing.toml"), width_config]))
            @test !ispath(joinpath(dir, "never"))
        end
    end
end
