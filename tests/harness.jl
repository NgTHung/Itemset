using TOML: TOML

const MEASURE_SCRIPT = joinpath(dirname(@__DIR__), "experiments", "measure.jl")
const RESULT_FIELDS_PATH = joinpath(dirname(@__DIR__), "experiments", "result-fields.txt")

function measured(code; timeout=60)
    mktempdir() do dir
        out, err, report = joinpath.(dir, ("stdout.txt", "stderr.txt", "report.toml"))
        child = `$(Base.julia_cmd()) --startup-file=no -e $code`
        run(`$(Base.julia_cmd()) --startup-file=no $MEASURE_SCRIPT --timeout $timeout
             --stdout $out --stderr $err --report $report -- $child`)
        return TOML.parsefile(report), read(out, String)
    end
end

"""A one-dataset manifest and data folder holding the toy baskets database."""
function toy_benchmark(dir)
    data = mkpath(joinpath(dir, "data"))
    cp(joinpath(TOY_DIR, "baskets.txt"), joinpath(data, "baskets.txt"))
    manifest = Dict("baskets" => Experiments.DatasetEntry(
        name="baskets", version="toy", file="baskets.txt",
        sha256=Experiments.file_sha256(joinpath(data, "baskets.txt")), sources=Experiments.DatasetSource[],
        stats=Experiments.dataset_stats(read_transactions(joinpath(data, "baskets.txt")))))
    return manifest, data
end

toy_config(; kw...) = Experiments.parse_run_config(merge(Dict{String,Any}(
    "name" => "toy", "variants" => ["baseline"], "repeats" => 1, "timeout_seconds" => 300,
    "series" => [Dict("dataset" => "baskets", "minsup" => [0.5])]),
    Dict{String,Any}(string(k) => v for (k, v) in kw)))

@testset "Measurement harness" begin
    @testset "Measure one process" begin
        report, out = measured("println(\"hi\")")
        @test report["status"] == "ok" && report["exit_code"] == 0
        @test out == "hi\n"
        @test report["elapsed_seconds"] > 0
        @test report["peak_rss_bytes"] > 0
        @test !isempty(report["memory_tool"])

        # Touch every page so the allocation is resident, not only reserved.
        big, _ = measured("x = fill(UInt8(1), 400_000_000); println(sum(x))")
        small, _ = measured("println(1)")
        @test big["peak_rss_bytes"] - small["peak_rss_bytes"] > 300_000_000

        failed, _ = measured("exit(3)")
        @test failed["status"] == "error" && failed["exit_code"] == 3

        slow, _ = measured("sleep(60)"; timeout=2)
        @test slow["status"] == "timeout"
        @test 2 <= slow["elapsed_seconds"] < 30
    end

    @testset "Run configuration" begin
        config = toy_config(; repeats=2, variants=["baseline", "spmf"])
        @test config.repeats == 2 && config.variants == [:baseline, :spmf]
        @test config.series[1].minsup == [0.5]
        @test_throws ArgumentError toy_config(; variants=["fast"])
        @test_throws ArgumentError toy_config(; repeats=0)
        @test_throws ArgumentError toy_config(; series=[Dict("dataset" => "baskets", "minsup" => [1.5])])
        @test_throws ArgumentError toy_config(; series=[Dict("dataset" => "baskets", "minsup" => Any[])])
        mktempdir() do dir
            manifest, _ = toy_benchmark(dir)
            missing_set = toy_config(; series=[Dict("dataset" => "nope", "minsup" => [0.5])])
            @test_throws ArgumentError Experiments.plan_attempts(missing_set, manifest)
        end
    end

    @testset "Thresholds SPMF rounds differently are rejected" begin
        # SPMF computes ceil(minsup * N) in Float64, so 0.07 of 100 becomes 8
        # while support_threshold gives 7; the two maps would differ for a reason
        # unrelated to correctness.
        @test Experiments.float_support_count(0.07, 100) == 8
        @test support_threshold(0.07, 100) == 7
        @test Experiments.threshold_agrees(0.5, 4)
        @test !Experiments.threshold_agrees(0.07, 100)
        hundred = Experiments.DatasetEntry(name="h", version="t", file="h.txt", sha256="0"^64,
            sources=Experiments.DatasetSource[], stats=Experiments.DatasetStats(
                transactions=100, items=1, total_items=100, max_width=1, min_item=1, max_item=1))
        config = toy_config(; series=[Dict("dataset" => "h", "minsup" => [0.07])])
        err = try
            Experiments.plan_attempts(config, Dict("h" => hundred))
        catch e
            e
        end
        @test err isa ArgumentError && occursin("0.07", err.msg)
    end

    @testset "Attempt order" begin
        mktempdir() do dir
            manifest, _ = toy_benchmark(dir)
            config = toy_config(; repeats=2, variants=["baseline", "spmf"],
                series=[Dict("dataset" => "baskets", "minsup" => [0.5, 0.75])])
            plan = Experiments.plan_attempts(config, manifest)
            @test [(a.minsup, a.repeat, a.variant) for a in plan] == [
                (0.75, 1, :baseline), (0.75, 1, :spmf), (0.75, 2, :baseline), (0.75, 2, :spmf),
                (0.5, 1, :baseline), (0.5, 1, :spmf), (0.5, 2, :baseline), (0.5, 2, :spmf)]
            @test all(a -> a.minsup_count == support_threshold(a.minsup, 4), plan)
            @test length(unique(a.id for a in plan)) == length(plan)
        end
    end

    @testset "CSV rows" begin
        @test Experiments.RESULT_FIELDS == split(strip(read(RESULT_FIELDS_PATH, String)), ',')
        @test Experiments.csv_field("plain") == "plain"
        @test Experiments.csv_field("a,b") == "\"a,b\""
        @test Experiments.csv_field("say \"hi\"") == "\"say \"\"hi\"\"\""
        @test Experiments.csv_field("two\nlines") == "\"two\nlines\""
        @test Experiments.csv_field(missing) == ""
        @test_throws ArgumentError Experiments.csv_line(Dict("dataset" => "x"))
    end

    @testset "Java version line" begin
        # Java on Windows ends its lines with CRLF; the recorded version must not keep the CR.
        @test Experiments.first_line("openjdk version \"25.0.4.1\"\r\nOpenJDK Runtime\r\n") ==
              "openjdk version \"25.0.4.1\""
        @test Experiments.first_line("openjdk 25\nOpenJDK") == "openjdk 25"
    end

    @testset "SPMF statistics" begin
        stdout_text = """
        =============  ECLAT v2.65 - STATS =============
         Transactions count from database : 5
         Frequent itemsets count : 15
         Total time ~ 12 ms
         Maximum memory usage : 12.9 mb
        ===================================================
        """
        @test Experiments.parse_spmf_stats(stdout_text) ==
              (transactions=5, itemsets=15, total_seconds=0.012)
        @test_throws ArgumentError Experiments.parse_spmf_stats("no stats here")
        mktempdir() do dir
            path = joinpath(dir, "out.txt")
            write(path, "@FILETYPE=\"Frequent itemsets\"\n@SOURCE=\"x\"\n1 #SUP: 3\n1 2 #SUP: 2\n")
            @test Experiments.count_itemset_lines(path) == 2
        end
    end

    @testset "Failures stay in the results" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            # 0.2 s cannot fit Julia startup, so the first attempt times out and
            # the lower threshold, which can only be slower, is skipped.
            config = toy_config(; timeout_seconds=0.2,
                series=[Dict("dataset" => "baskets", "minsup" => [0.5, 0.75])])
            out = joinpath(dir, "run")
            rows = Experiments.run_experiment(config, manifest; data_dir=data, out_dir=out)
            @test [(r["minsup_relative"], r["status"]) for r in rows] ==
                  [("0.75", "timeout"), ("0.5", "skipped")]
            @test all(r -> r["elapsed_seconds"] != "0", rows)
            @test countlines(joinpath(out, "runs.csv")) == 1 + length(rows)
            @test isfile(joinpath(out, "environment.toml"))
        end
    end

    @testset "Mine the toy database end to end" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            out = joinpath(dir, "run")
            rows = Experiments.run_experiment(toy_config(), manifest; data_dir=data, out_dir=out)
            @test [r["timing_scope"] for r in rows] == ["process", "read", "mine", "write"]
            for row in rows
                @test row["status"] == "ok" && isempty(row["error"])
                @test !isempty(row["run_id"]) && !isempty(row["code_revision"])
                @test row["minsup_count"] == "2" && row["transactions"] == "4"
                @test row["seed"] == string(DEFAULT_SEED)
                @test row["output_count"] == "6"
                @test parse(Int, row["peak_rss_bytes"]) > 0
                @test parse(Float64, row["elapsed_seconds"]) >= 0
            end
            @test parse(Int, rows[3]["allocated_bytes"]) > 0
            @test isfile(joinpath(out, "attempts", rows[1]["attempt_id"], "command.txt"))
        end
    end
end
