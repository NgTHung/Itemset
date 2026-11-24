using Profile: Profile

function stage_test_busy(seconds)
    deadline = time() + seconds
    total = 0
    while time() < deadline
        total += sum(i -> i % 7, 1:1000)
    end
    return total
end

frames(names...) = [(Symbol(name), :unknown_file) for name in names]
info(group, read=false) = Experiments.IPInfo(group, read)

@testset "Stage profile of the optimized CLI path" begin
    @testset "A stack goes to the group of its innermost known function" begin
        group = Experiments.stage_group
        @test group(frames("intersect_bitsets!", "join_members!", "eclat_search!")) == "bitset joins"
        @test group(frames("getindex", "count_items", "mine_optimized")) == "item counts"
        # The innermost frame wins, so a sort called from the writer counts as the sort.
        @test group(frames("sort!", "lexicographic_order", "write_itemsets")) == "sort"
        @test group(frames("put_digits!", "print_packed", "write_itemsets")) == "format"
        @test group(frames("jl_gc_collect", "mine_packed")) == "other"
        @test group(Tuple{Symbol,Symbol}[]) == "other"
        # A name that only starts like a listed one is not that function.
        @test group(frames("intersect_bitsets_copy")) == "other"
    end

    @testset "Expanding a node is not formatting, and the reader's check is reading" begin
        group = Experiments.stage_group
        # write_itemset! copies one itemset into the node result; the SPMF writer never calls it.
        @test group(frames("write_itemset!", "write_subsets!", "expand_nodes")) == "expand"
        @test group(frames("is_canonical", "canonical_database", "mine_packed")) == "canonical check"
        @test group(frames("is_canonical", "canonical_copy", "read_transactions")) == "read"
        @test group(frames("is_canonical", "read_transactions", "cli_main")) == "read"
    end

    @testset "A method is told apart by its file when its name is shared" begin
        group = Experiments.stage_group
        method(file) = [(:may_be_frequent, Symbol(file)), (:mine_optimized, Symbol("eclat_optimized.jl"))]
        @test group(method("pair_counts.jl")) == "pair counts"
        @test group(method("block_counts.jl")) == "block counts"
        @test group(method("elsewhere.jl")) == "other"
    end

    @testset "Every listed name is a function the package defines, once" begin
        defined = Set(names(ItemsetMining; all=true, imported=false))
        sources = joinpath(dirname(pathof(ItemsetMining)), "algorithm")
        listed = String[name for (_, group) in Experiments.STAGE_GROUPS for name in group]
        for entry in listed
            name, file = occursin('@', entry) ? split(entry, '@') : (entry, "")
            @test Symbol(name) in defined
            isempty(file) || @test isfile(joinpath(sources, file))
        end
        @test allunique(listed)
        @test allunique(first.(Experiments.STAGE_GROUPS))
        @test !any(label -> label == "other", first.(Experiments.STAGE_GROUPS))
    end

    @testset "A sample takes the first group on its stack, and reading overrides it" begin
        block_group = Experiments.block_group
        @test block_group([info(nothing), info("bitset joins"), info("search")]) == "bitset joins"
        @test block_group([info(nothing), info(nothing)]) == "other"
        @test block_group(Experiments.IPInfo[]) == "other"
        @test block_group([info("canonical check"), info(nothing, true)]) == "read"
        info_of = Experiments.ip_info
        @test info_of(frames("count_items", "mine")) == info("item counts")
        @test info_of(frames("is_canonical", "read_transactions")) == info("canonical check", true)
    end

    @testset "Counts and shares" begin
        counts = Experiments.stage_counts(["bitset joins", "bitset joins", "item counts", "other"])
        @test counts["bitset joins"] == 2 && counts["item counts"] == 1 && counts["other"] == 1
        @test sum(values(counts)) == 4
        shares = Experiments.stage_shares(counts)
        @test shares["bitset joins"] == 0.5 && shares["item counts"] == 0.25 && shares["other"] == 0.25
        @test sum(values(shares)) ≈ 1
        none = Experiments.stage_shares(Experiments.stage_counts(String[]))
        @test all(iszero, values(none))
        @test keys(none) == keys(shares)
    end

    @testset "Only the samples of the running thread count, found by their index range" begin
        # Two samples of thread 1 around one sample of thread 2, in the layout of Profile.fetch:
        # the pointers, then thread, task, clock, sleep state, and two zeros.
        data = UInt[11, 12, 1, 7, 100, 1, 0, 0,
                    21, 2, 8, 101, 2, 0, 0,
                    31, 1, 7, 102, 2, 0, 0]
        @test Experiments.thread_blocks(data, 1) == [1:2, 16:16]
        @test Experiments.thread_blocks(data, 2) == [9:9]
        @test isempty(Experiments.thread_blocks(data, 3))
        # A sample that sleeps on the running thread is kept, since the wait is part of the run.
        @test 16:16 in Experiments.thread_blocks(data, 1)
        @test isempty(Experiments.thread_blocks(UInt[], 1))
        @test_throws ArgumentError Experiments.thread_blocks(UInt[1, 2, 3], 1)
    end

    @testset "A metadata layout that shifted is an error, not wrong shares" begin
        # The thread field holds a clock value, as it would if the fields moved by one place.
        shifted = UInt[11, 12, 123_456_789_012, 1, 7, 1, 0, 0]
        err = try
            Experiments.thread_blocks(shifted, 1)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError && occursin("layout", err.msg)
        @test_throws ArgumentError Experiments.thread_blocks(UInt[11, 12, 99_999_999, 7, 100, 1, 0, 0], 1)
    end

    @testset "A real profile holds the running thread's work" begin
        counts = Experiments.with_profiler() do
            Experiments.profile_counts(() -> stage_test_busy(0.3))
        end
        total = sum(values(counts))
        @test total > 10
        @test counts["other"] >= 0.8 * total
    end

    @testset "A full profiler buffer is an error that names the point" begin
        err = try
            Experiments.with_profiler(; n=1_000, delay=0.0005) do
                Experiments.profile_counts(() -> stage_test_busy(0.3); label="busy at 0.5")
            end
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("buffer", err.msg) && occursin("busy at 0.5", err.msg)
    end

    @testset "The profiler settings are restored" begin
        before = Profile.init()
        inside = Experiments.with_profiler(; n=2_000_000, delay=0.002) do
            Profile.init()
        end
        @test inside == (2_000_000, 0.002)
        @test Profile.init() == before
        @test_throws ErrorException Experiments.with_profiler(() -> error("boom"); n=2_000_000, delay=0.002)
        @test Profile.init() == before
    end

    @testset "Rows for a configured experiment" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            config = toy_config(; series=[Dict("dataset" => "baskets", "minsup" => [0.5, 0.75])], repeats=2)
            before = Profile.init()
            rows = Experiments.stage_profile_rows(config, manifest, data)
            @test Profile.init() == before
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
            @test Profile.init() == before
        end
    end

    @testset "The repeats default to those of the configuration" begin
        config = toy_config(; repeats=3)
        @test Experiments.stage_repeats(config, nothing) == 3
        @test Experiments.stage_repeats(config, 7) == 7
        @test_throws ArgumentError Experiments.stage_repeats(config, 0)
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
        @test config.repeats == 5
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
        @testset "The manifest of the data folder is the default" begin
            settings = Experiments.WidthSettings(transactions=50, items=8, widths=[3])
            width_dir = mkpath(joinpath(dir, "width-data"))
            Experiments.freeze_width_manifest(joinpath(width_dir, "manifest.toml"), settings, width_dir)
            width_config = joinpath(dir, "width.toml")
            write(width_config, """
            name = "width"
            variants = ["optimized"]
            repeats = 2
            timeout_seconds = 60
            [[series]]
            dataset = "width-w03"
            minsup = [0.5]
            """)
            out = joinpath(dir, "width-out")
            # No --repeats: the two repeats of the configuration apply.
            @test quiet(() -> StageProfileScript.main(["--out", out, width_config]; data_dir=width_dir)) == 0
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
