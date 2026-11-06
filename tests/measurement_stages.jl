@testset "Comparable optimization measurements" begin
    @testset "PrePost+ statistics and incomplete output" begin
        text = """
        Minsup = 2
        ============= PrePost+ - STATS =============
        Number of transactions: 4
        Number of frequent  itemsets: 6
        Total time ~: 17 ms
        """
        @test Experiments.parse_prepost_stats(text) ==
              (transactions=4, itemsets=6, total_seconds=0.017, minsup_count=2)
        for field in ("Minsup = 2", "Number of transactions: 4",
                      "Number of frequent  itemsets: 6", "Total time ~: 17 ms")
            @test_throws ArgumentError Experiments.parse_prepost_stats(replace(text, field => ""))
        end
    end

    @testset "Modes, stages, and required points" begin
        config = toy_config(; variants=["baseline", "spmf", "prepost"], mode="cold", stage="B0")
        @test config.mode == :cold && only(config.revisions).stage == "B0"
        @test !config.skip_after_timeout
        @test toy_config(; mode="warm").mode == :warm
        @test toy_config(; mode="cli", variants=["baseline", "prepost"]).mode == :cli
        @test_throws ArgumentError toy_config(; mode="hot")
        @test_throws ArgumentError toy_config(; mode="warm", variants=["prepost"])
        @test_throws ArgumentError toy_config(; stage="")
        mktempdir() do dir
            manifest, _ = toy_benchmark(dir)
            attempt = last(Experiments.plan_attempts(config, manifest))
            command = string(Experiments.measured_command(attempt, config, "in", "out", "report"))
            @test occursin("PrePost+", command)
            cli = toy_config(; mode="cli")
            command = string(Experiments.measured_command(first(Experiments.plan_attempts(cli, manifest)),
                                                          cli, "in", "out", "report"))
            @test occursin(joinpath(only(cli.revisions).project, "demo.jl"), command)
            @test !occursin("eclat_worker", command) && !occursin("report", command)
        end
    end

    @testset "Complete maps, duplicates, and malformed output" begin
        mktempdir() do dir
            reference, candidate = joinpath.(dir, ("reference.txt", "candidate.txt"))
            write(reference, "1 #SUP: 3\n1 2 #SUP: 2\n")
            write(candidate, "2 1 #SUP: 2\n1 #SUP: 3\n")
            result = Experiments.verify_output(reference, candidate, joinpath(dir, "equal.toml"))
            @test result["correctness_status"] == "exact"
            @test result["match_rate"] == "1.0"
            for text in ("1 #SUP: 3\n1 #SUP: 3\n", "1 #SUP: 2\n1 2 #SUP: 2\n",
                         "1 #SUP: 3\n", "1 #SUP: 3\n1 2 #SUP: 2\n3 #SUP: 1\n", "1 #SUP:")
                write(candidate, text)
                result = Experiments.verify_output(reference, candidate, joinpath(dir, "bad.toml"))
                @test result["correctness_status"] == "failed"
                @test isfile(joinpath(dir, "bad.toml"))
            end
        end
    end

    @testset "Summary excludes failures without hiding them" begin
        rows = [Dict("dataset"=>"toy", "minsup_count"=>"2", "variant"=>"baseline",
                     "stage"=>"B0", "mode"=>"cold", "timing_scope"=>"process",
                     "status"=>"ok", "correctness_status"=>"exact", "elapsed_seconds"=>string(t),
                     "peak_rss_bytes"=>"100", "allocated_bytes"=>"", "gc_seconds"=>"") for t in (1, 2, 3, 4, 5)]
        push!(rows, merge(first(rows), Dict("status"=>"timeout", "elapsed_seconds"=>"300")))
        result = only(Experiments.summarize_rows(rows))
        @test result["median_seconds"] == "3.0"
        @test result["iqr_seconds"] == "2.0"
        @test result["successful_samples"] == "5" && result["failed_samples"] == "1"
        @test result["samples_seconds"] == "1.0;2.0;3.0;4.0;5.0"
        @test result["gate_eligible"] == "false"
    end

    @testset "Workers and the CLI verify after timing" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            reference = joinpath(dir, "reference.txt")
            write_itemsets(reference, brute_force_supports(read_transactions(joinpath(data, "baskets.txt")), 2))
            for mode in ("cold", "warm")
                config = toy_config(; mode, verify_outputs=true)
                attempt = only(Experiments.plan_attempts(config, manifest))
                base = Dict(field => "" for field in Experiments.RESULT_FIELDS)
                merge!(base, Dict("mode"=>mode, "correctness_status"=>"not_checked"))
                rows = Experiments.run_attempt(attempt, config, joinpath(data, "baskets.txt"),
                    joinpath(dir, mode), base; reference=() -> reference)
                @test all(r -> r["status"] == "ok" && r["correctness_status"] == "exact", rows)
                @test rows[2]["warmup_policy"] == (mode == "cold" ? "cold-call" : "dataset-warmup")
                @test all(r -> parse(Int, r["allocated_bytes"]) > 0, rows[2:end])
                @test isfile(joinpath(dir, mode, "comparison.toml"))
            end
            config = toy_config(; mode="cli", verify_outputs=true)
            attempt = only(Experiments.plan_attempts(config, manifest))
            base = Dict(field => "" for field in Experiments.RESULT_FIELDS)
            merge!(base, Dict("mode"=>"cli", "correctness_status"=>"not_checked"))
            rows = Experiments.run_attempt(attempt, config, joinpath(data, "baskets.txt"),
                joinpath(dir, "cli"), base; reference=() -> reference)
            row = only(rows)
            @test row["timing_scope"] == "process" && row["warmup_policy"] == "cold-process"
            @test row["status"] == "ok" && row["correctness_status"] == "exact"
            @test row["output_count"] == "6"
            @test !isfile(joinpath(dir, "cli", "worker.toml"))
            write(reference, "1 #SUP: 999\n")
            config = toy_config(; verify_outputs=true)
            attempt = only(Experiments.plan_attempts(config, manifest))
            base = Dict(field => "" for field in Experiments.RESULT_FIELDS)
            base["mode"] = "cold"
            rows = Experiments.run_attempt(attempt, config, joinpath(data, "baskets.txt"),
                joinpath(dir, "mismatch"), base; reference=() -> reference)
            @test all(r -> r["status"] == "error" && r["correctness_status"] == "failed", rows)
            @test isfile(joinpath(dir, "mismatch", "output.txt"))
        end
    end

    @testset "Missing output is a recorded validation error" begin
        mktempdir() do dir
            manifest, _ = toy_benchmark(dir)
            attempt = only(Experiments.plan_attempts(toy_config(), manifest))
            @test_throws ArgumentError Experiments.completed_rows(attempt, Dict{String,String}(),
                Dict("output.txt" => joinpath(dir, "missing.txt")))
        end
    end

    @testset "Required attempts continue after timeout" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            config = toy_config(; timeout_seconds=0.2, repeats=2,
                series=[Dict("dataset"=>"baskets", "minsup"=>[0.5, 0.75])])
            rows = Experiments.run_experiment(config, manifest; data_dir=data, out_dir=joinpath(dir, "run"))
            @test length(rows) == 4
            @test all(r -> r["status"] == "timeout", rows)
            @test isfile(joinpath(dir, "run", "source-checksums.toml"))
        end
    end

    @testset "PrePost+ count disagreement invalidates the row" begin
        mktempdir() do dir
            manifest, _ = toy_benchmark(dir)
            attempt = only(Experiments.plan_attempts(toy_config(; variants=["prepost"]), manifest))
            output, stdout = joinpath.(dir, ("output.txt", "stdout.txt"))
            write(output, "1 #SUP: 3\n")
            write(stdout, "Minsup = 3\nNumber of transactions: 4\nNumber of frequent  itemsets: 1\nTotal time ~: 1 ms\n")
            @test_throws "PrePost+ used count 3" Experiments.completed_rows(attempt,
                Dict{String,String}(), Dict("output.txt"=>output, "stdout.txt"=>stdout))
        end
    end
end
