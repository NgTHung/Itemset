@testset "Shared table tools" begin
    @testset "write_rows" begin
        mktempdir() do dir
            path = joinpath(dir, "rows.csv")
            Experiments.write_rows(path, ["a", "b"], [(a=1, b="x,y"), Dict("a" => 2, "b" => missing)])
            @test Experiments.read_csv_rows(path) == [Dict("a" => "1", "b" => "x,y"), Dict("a" => "2", "b" => "")]
            @test countlines(path) == 3
        end
    end

    @testset "A bad row leaves no file and names the row and the field" begin
        mktempdir() do dir
            path = joinpath(dir, "never.csv")
            err = try
                Experiments.write_rows(path, ["a", "b"], [(a=1, b=2), (a=3,)])
                nothing
            catch e
                e
            end
            @test err isa ArgumentError && occursin("row 2", err.msg) && occursin("b", err.msg)
            @test_throws ArgumentError Experiments.write_rows(path, ["a"], [Dict("z" => 1)])
            @test !ispath(path)
        end
    end

    @testset "for_each_point visits each threshold from the highest down" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            config = toy_config(; series=[Dict("dataset" => "baskets", "minsup" => [0.5, 0.75, 0.25])])
            points = Experiments.for_each_point(identity, config, manifest, data)
            @test [(p.dataset, p.minsup_relative, p.minsup_count) for p in points] ==
                  [("baskets", "0.75", 3), ("baskets", "0.5", 2), ("baskets", "0.25", 1)]
            @test all(p -> p.path == joinpath(data, "baskets.txt"), points)
            @test all(p -> p.transactions === nothing, points)
            kept = Experiments.for_each_point(identity, config, manifest, data; keep=true)
            @test all(p -> p.transactions == read_transactions(joinpath(data, "baskets.txt")), kept)
            @test Experiments.for_each_point(p -> p.minsup_count, config, manifest, data) == [3, 2, 1]
            missing_set = toy_config(; series=[Dict("dataset" => "nope", "minsup" => [0.5])])
            @test_throws ArgumentError Experiments.for_each_point(identity, missing_set, manifest, data)
        end
    end

    @testset "for_each_point takes the transaction count from the manifest unless it must keep the database" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            entry = manifest["baskets"]
            stats = Experiments.DatasetStats(transactions=100, items=3, total_items=9, max_width=3, min_item=1, max_item=3)
            stated = Dict("baskets" => Experiments.DatasetEntry(name=entry.name, version=entry.version, file=entry.file,
                                                                sha256=entry.sha256, sources=entry.sources, stats=stats))
            config = toy_config(; series=[Dict("dataset" => "baskets", "minsup" => [0.5])])
            # The manifest says 100 transactions and the file holds 4, so which one is used shows in the count.
            @test only(Experiments.for_each_point(p -> p.minsup_count, config, stated, data)) == 50
            @test only(Experiments.for_each_point(p -> p.minsup_count, config, stated, data; keep=true)) == 2
            unstated = Dict("baskets" => Experiments.DatasetEntry(name=entry.name, version=entry.version, file=entry.file,
                                                                  sha256=entry.sha256, sources=entry.sources, stats=nothing))
            @test only(Experiments.for_each_point(p -> p.minsup_count, config, unstated, data)) == 2
        end
    end

    @testset "A table of a summary or of ratios leaves no partial file" begin
        mktempdir() do dir
            path = joinpath(dir, "summary.csv")
            bad = [Dict("dataset" => "d")]
            @test_throws Exception Experiments.write_summary(bad, path)
            @test !ispath(path)
        end
    end

    @testset "Command-line options" begin
        usage = "USAGE"
        parse = (args; kw...) -> Experiments.parse_table_args(args, usage, "data"; kw...)
        ok = parse(["--out", "o", "config.toml"])
        @test ok.out == "o" && ok.config == "config.toml" && ok.manifest == joinpath("data", "manifest.toml")
        @test ok.repeats === nothing
        both = parse(["config.toml", "--manifest", "m.toml", "--out", "o", "--repeats", "3"]; repeats=true)
        @test both.manifest == "m.toml" && both.repeats == 3
        for bad in (String[], ["config.toml"], ["--out", "o"], ["--out", "o", "a.toml", "b.toml"],
                    ["--out", "o", "--bogus", "c.toml"], ["--out"], ["--out", "o", "--manifest"],
                    ["--out", "o", "--repeats", "2", "c.toml"])
            @test_throws ArgumentError parse(bad)
        end
        for bad in (["--out", "o", "--repeats", "0", "c.toml"], ["--out", "o", "--repeats", "x", "c.toml"],
                    ["--out", "o", "--repeats", "--manifest", "c.toml"])
            @test_throws ArgumentError parse(bad; repeats=true)
        end
        err = try
            parse(String[])
        catch e
            e
        end
        @test occursin("USAGE", err.msg)
    end
end
