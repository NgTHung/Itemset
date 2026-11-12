using SHA: sha256

const TINY_WIDTH = Experiments.WidthSettings(transactions=5, items=10, widths=[3])

@testset "Transaction width databases" begin
    @testset "SplitMix64 matches the published algorithm" begin
        # Known answers from an independent Python implementation of SplitMix64.
        rng = Experiments.SplitMix64(UInt64(0))
        @test [Experiments.next!(rng) for _ in 1:3] == [0xe220a8397b1dcdaf, 0x6e789e6aa1b965f4, 0x06c45d188009454f]
        rng = Experiments.SplitMix64(UInt64(42))
        @test [Experiments.next!(rng) for _ in 1:3] == [0xbdd732262feb6e95, 0x28efe333b266f103, 0x47526757130f9f52]
        rng = Experiments.SplitMix64(UInt64(7))
        draws = [Experiments.below!(rng, 6) for _ in 1:2000]
        @test minimum(draws) == 0 && maximum(draws) == 5
        @test_throws ArgumentError Experiments.below!(rng, 0)
    end

    @testset "Databases follow the stated model" begin
        @test Experiments.width_seed(TINY_WIDTH, 3) == (UInt64(42) << 32) | UInt64(3)
        db = Experiments.width_database(TINY_WIDTH, 3)
        # Same rows as an independent Python implementation of the generator.
        @test db == [[4, 5, 6], [1, 4, 7], [3, 5, 9], [4, 8, 9], [2, 5, 10]]
        @test Experiments.width_database(TINY_WIDTH, 3) == db
        settings = Experiments.WidthSettings(transactions=3000, items=40, widths=[4, 8])
        for w in settings.widths
            rows = Experiments.width_database(settings, w)
            @test length(rows) == 3000
            @test all(r -> length(r) == w && issorted(r) && allunique(r) && all(in(1:40), r), rows)
            supports = zeros(Int, 40)
            foreach(r -> foreach(i -> supports[i] += 1, r), rows)
            p = w / 40
            sigma = sqrt(3000 * p * (1 - p))
            @test all(s -> abs(s - 3000 * p) <= 5 * sigma, supports)
        end
        @test Experiments.width_database(settings, 4) != Experiments.width_database(settings, 8)
        other_seed = Experiments.WidthSettings(transactions=3000, items=40, widths=[4, 8], seed=7)
        @test Experiments.width_database(other_seed, 4) != Experiments.width_database(settings, 4)
        for bad in (0, -1, 11)
            @test_throws ArgumentError Experiments.width_database(TINY_WIDTH, bad)
        end
    end

    @testset "Settings are validated" begin
        for bad in (Experiments.WidthSettings(transactions=0), Experiments.WidthSettings(items=0),
                    Experiments.WidthSettings(widths=Int[]), Experiments.WidthSettings(widths=[5, 5]),
                    Experiments.WidthSettings(widths=[10, 5]), Experiments.WidthSettings(items=10, widths=[5, 11]),
                    Experiments.WidthSettings(widths=[0, 5]), Experiments.WidthSettings(seed=-1))
            @test_throws ArgumentError Experiments.check_settings(bad)
        end
        @test Experiments.check_settings(Experiments.WidthSettings()) === nothing
        @test Experiments.WidthSettings().widths == [5, 10, 15, 20, 25, 30, 35, 40]
    end

    @testset "Expected supports have a closed form" begin
        # Subsets of 3 of 6 items: a given pair lies in C(4,1) of C(6,3) = 20 subsets.
        @test Experiments.expected_support(6, 3, 1) == 0.5
        @test Experiments.expected_support(6, 3, 2) ≈ 4 / 20
        @test Experiments.expected_support(6, 3, 3) ≈ 1 / 20
        @test Experiments.expected_support(6, 3, 4) == 0.0
        @test Experiments.expected_support(100, 40, 3) ≈ 40 * 39 * 38 / (100 * 99 * 98)
        @test_throws ArgumentError Experiments.expected_support(6, 3, 0)
    end

    @testset "Density statistics" begin
        db = Experiments.width_database(TINY_WIDTH, 3)
        stats = Experiments.density_stats(TINY_WIDTH, 3, db)
        @test stats.width == 3 && stats.density == 0.3
        @test (stats.item_support_min, stats.item_support_max) == (1, 3)
        @test stats.expected_item_support ≈ 1.5
        @test stats.expected_pair_support ≈ 5 * (3 / 10) * (2 / 9)
        @test stats.expected_triple_support ≈ 5 * 6 / 720
    end

    @testset "Files are byte-identical across languages and platforms" begin
        mktempdir() do dir
            path = joinpath(dir, "tiny.txt")
            Experiments.write_width_database(path, TINY_WIDTH, 3)
            @test read(path, String) == "4 5 6\n1 4 7\n3 5 9\n4 8 9\n2 5 10\n"
            @test bytes2hex(sha256(read(path))) == "8848ec60c8054b7fac59fb13146a4f92892eefa2deed652ce1f105ddd7740416"
            # The full-size file of the experiment's narrowest width, from the Python implementation.
            big = joinpath(dir, "big.txt")
            Experiments.write_width_database(big, Experiments.WidthSettings(), 5)
            @test bytes2hex(sha256(read(big))) == "01701afd66270088b02e12c91eb79312893694e2f2c56b90d82bee57beb204be"
            @test read_transactions(path) == Experiments.width_database(TINY_WIDTH, 3)
        end
    end

    @testset "The manifest freezes the datasets" begin
        mktempdir() do dir
            manifest_path = joinpath(dir, "manifest.toml")
            settings = Experiments.WidthSettings(transactions=50, items=12, widths=[2, 4])
            Experiments.freeze_width_manifest(manifest_path, settings, dir)
            manifest = Experiments.load_manifest(manifest_path)
            @test sort!(collect(keys(manifest))) == ["width-w02", "width-w04"]
            entry = manifest["width-w04"]
            @test entry.file == "width-w04.txt" && isempty(entry.sources) && length(entry.sha256) == 64
            @test entry.stats == Experiments.dataset_stats(Experiments.width_database(settings, 4))
            @test Experiments.mean_width(entry.stats) == 4.0 && entry.stats.transactions == 50
            @test isfile(joinpath(dir, "width-w04.txt")) && isfile(joinpath(dir, "width-w02.txt"))

            # A missing or damaged file is regenerated, and a present one is left alone.
            rm(joinpath(dir, "width-w02.txt"))
            write(joinpath(dir, "width-w04.txt"), "1 2\n")
            Experiments.ensure_width_databases(dir, manifest, settings)
            @test Experiments.file_sha256(joinpath(dir, "width-w02.txt")) == manifest["width-w02"].sha256
            @test Experiments.file_sha256(joinpath(dir, "width-w04.txt")) == entry.sha256
            before = stat(joinpath(dir, "width-w02.txt")).mtime
            Experiments.ensure_width_databases(dir, manifest, settings)
            @test stat(joinpath(dir, "width-w02.txt")).mtime == before
            @test isempty(filter(f -> !endswith(f, ".txt") && !endswith(f, ".toml"), readdir(dir)))

            # Changed settings no longer reproduce the recorded bytes, so nothing is replaced.
            changed = Experiments.WidthSettings(transactions=50, items=12, widths=[2, 4], seed=1)
            rm(joinpath(dir, "width-w02.txt"))
            rm(joinpath(dir, "width-w04.txt"))
            err = try Experiments.ensure_width_databases(dir, manifest, changed) catch e e end
            @test err isa ErrorException && occursin("width-w02", err.msg) && occursin("SHA-256", err.msg)
            @test !isfile(joinpath(dir, "width-w02.txt")) && !isfile(joinpath(dir, "width-w04.txt"))
            missing_entry = Experiments.WidthSettings(transactions=50, items=12, widths=[2, 4, 6])
            @test_throws ArgumentError Experiments.ensure_width_databases(dir, manifest, missing_entry)
        end
    end
end

@testset "Matching the output volume across widths" begin
    # Counts 1 to 4 give 6, 4, 2, and 0 itemsets: {1} 3, {2} 3, {3} 2, {12} 2, {13} 1, {23} 1.
    db = [[1, 2], [1, 2], [1, 3], [2, 3]]
    @test [Experiments.output_count(db, t) for t in 1:4] == [6, 4, 2, 0]
    @test Experiments.matched_count(db, 6) == 1
    @test Experiments.matched_count(db, 5) == 1
    @test Experiments.matched_count(db, 4) == 2
    @test Experiments.matched_count(db, 3) == 2
    @test Experiments.matched_count(db, 2) == 3
    @test Experiments.matched_count(db, 1) == 3
    err = try Experiments.matched_count(db, 7) catch e e end
    @test err isa ArgumentError && occursin("7", err.msg) && occursin("6", err.msg)
    @test_throws ArgumentError Experiments.matched_count(db, 0)
    @test_throws ArgumentError Experiments.matched_count(Vector{Int}[], 1)
    # One 40-item transaction holds 2^40 itemsets at count 1, so a search that mines low counts never returns.
    wide = [collect(1:40), [1], [1], [1]]
    @test Experiments.matched_count(wide, 1) == 4
    # The result is the largest count that still reaches the target, on a database with many levels.
    settings = Experiments.WidthSettings(transactions=400, items=20, widths=[4, 8])
    for w in settings.widths
        rows = Experiments.width_database(settings, w)
        t = Experiments.matched_count(rows, 60)
        @test Experiments.output_count(rows, t) >= 60
        @test Experiments.output_count(rows, t + 1) < 60
    end
end

@testset "Pilot table" begin
    settings = Experiments.WidthSettings(transactions=400, items=20, widths=[4, 8])
    databases = Dict(w => Experiments.width_database(settings, w) for w in settings.widths)
    rows = Experiments.pilot_rows(settings, databases; fixed_count=20, target=60)
    @test [r.width for r in rows] == [4, 8]
    for r in rows
        rows_w = databases[r.width]
        @test r.density == r.width / 20
        @test r.fixed_count == 20 && r.fixed_output == Experiments.output_count(rows_w, 20)
        @test r.matched_count == Experiments.matched_count(rows_w, 60)
        @test r.matched_output == Experiments.output_count(rows_w, r.matched_count) >= 60
        @test r.item_support_min <= r.expected_item_support <= r.item_support_max
    end
    @test_throws ArgumentError Experiments.pilot_rows(settings, Dict(4 => databases[4]); fixed_count=20, target=60)
    @test_throws ArgumentError Experiments.pilot_rows(settings, databases; fixed_count=0, target=60)
    mktempdir() do dir
        path = joinpath(dir, "pilot.csv")
        Experiments.write_pilot(path, rows)
        back = Experiments.read_csv_rows(path)
        @test [r["width"] for r in back] == ["4", "8"]
        @test back[1]["matched_count"] == string(rows[1].matched_count)
        @test back[2]["fixed_output"] == string(rows[2].fixed_output)
        @test haskey(back[1], "expected_pair_support") && haskey(back[1], "density")
    end
end

module WidthScript
include(joinpath(dirname(@__DIR__), "scripts", "width_experiment.jl"))
end

@testset "Width experiment script" begin
    quiet(f) = redirect_stdout(f, devnull)
    # The script loads its own copy of the experiments module, so its settings type is its own.
    settings = WidthScript.WidthSettings(transactions=200, items=15, widths=[3, 6])
    mktempdir() do dir
        manifest_path = joinpath(dir, "manifest.toml")
        data_dir = joinpath(dir, "data")
        main(args) = quiet(() -> WidthScript.main(args; settings, manifest_path, data_dir))

        @testset "Usage and bad arguments change nothing" begin
            @test main(["-h"]) == 0
            @test main(["--help"]) == 0
            for bad in (String[], ["bogus"], ["freeze", "extra"], ["pilot", "--bogus", "1"], ["pilot", "--target"],
                        ["pilot", "--target", "x"], ["run"], ["run", "a", "b"], ["run", joinpath(dir, "none.toml")],
                        ["run", "--out"], ["pilot"])
                @test_throws ArgumentError main(bad)
            end
            @test !ispath(manifest_path) && !ispath(data_dir)
        end

        @testset "Freeze writes the manifest once" begin
            @test main(["freeze"]) == 0
            manifest = Experiments.load_manifest(manifest_path)
            @test sort!(collect(keys(manifest))) == ["width-w03", "width-w06"]
            @test all(isfile(joinpath(data_dir, e.file)) for e in values(manifest))
            frozen = read(manifest_path, String)
            err = try main(["freeze"]) catch e e end
            @test err isa ArgumentError && occursin("exists", err.msg)
            @test read(manifest_path, String) == frozen
        end

        @testset "Pilot restores missing databases and writes the table" begin
            rm(joinpath(data_dir, "width-w03.txt"))
            out = joinpath(dir, "pilot")
            @test main(["pilot", "--fixed-count", "10", "--target", "20", "--out", out]) == 0
            rows = Experiments.read_csv_rows(joinpath(out, "pilot.csv"))
            @test [r["width"] for r in rows] == ["3", "6"]
            @test all(r -> parse(Int, r["matched_output"]) >= 20, rows)
            @test isfile(joinpath(data_dir, "width-w03.txt"))
        end

        @testset "Run measures through the common harness" begin
            config = joinpath(dir, "config.toml")
            write(config, """
            name = "width-test"
            variants = ["baseline"]
            repeats = 1
            timeout_seconds = 120
            verify_outputs = false
            [[series]]
            dataset = "width-w06"
            minsup = [0.25]
            """)
            out = joinpath(dir, "run")
            @test main(["run", config, "--out", out]) == 0
            rows = Experiments.read_csv_rows(joinpath(out, "runs.csv"))
            @test !isempty(rows) && all(r -> r["dataset"] == "width-w06" && r["status"] == "ok", rows)
            @test only(unique(r["transactions"] for r in rows)) == "200"
            @test_throws ArgumentError main(["run", config, "--out", out])
        end
    end
end
