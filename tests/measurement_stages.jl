@testset "Comparable optimization measurements" begin
    @testset "Complete maps, duplicates, and malformed output" begin
        mktempdir() do dir
            reference, candidate = joinpath.(dir, ("reference.txt", "candidate.txt"))
            write(reference, "1 #SUP: 3\n1 2 #SUP: 2\n")
            write(candidate, "2 1 #SUP: 2\n1 #SUP: 3\n")
            result = Experiments.verify_output(reference, candidate, joinpath(dir, "equal.toml"))
            @test result["correctness_status"] == "exact"
            for text in ("1 #SUP: 3\n1 #SUP: 3\n", "1 #SUP: 2\n1 2 #SUP: 2\n",
                         "1 #SUP: 3\n", "1 #SUP: 3\n1 2 #SUP: 2\n3 #SUP: 1\n", "1 #SUP:")
                write(candidate, text)
                result = Experiments.verify_output(reference, candidate, joinpath(dir, "bad.toml"))
                @test result["correctness_status"] == "failed"
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
        @test result["gate_eligible"] == "false"
    end

    @testset "Workers verify after timing" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            reference = joinpath(dir, "reference.txt")
            write_itemsets(reference, brute_force_supports(read_transactions(joinpath(data, "baskets.txt")), 2))
            run_rows(mode, out) = begin
                config = toy_config(; mode, verify_outputs=true)
                attempt = only(Experiments.plan_attempts(config, manifest))
                base = merge(Dict(field => "" for field in Experiments.RESULT_FIELDS),
                             Dict("mode"=>mode, "correctness_status"=>"not_checked"))
                Experiments.run_attempt(attempt, config, joinpath(data, "baskets.txt"),
                    joinpath(dir, out), base; reference=() -> reference)
            end
            for mode in ("cold", "warm", "cli")
                @test all(r -> r["status"] == "ok" && r["correctness_status"] == "exact", run_rows(mode, mode))
            end
            write(reference, "1 #SUP: 999\n")
            @test all(r -> r["status"] == "error" && r["correctness_status"] == "failed", run_rows("cold", "mismatch"))
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
