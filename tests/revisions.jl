two_revisions(other; kw...) = toy_config(; revisions=[
    Dict("stage" => "control", "project" => Experiments.REPO_ROOT),
    Dict("stage" => "candidate", "project" => other)], kw...)

@testset "Revisions alternate within one run" begin
    @testset "Each repeat reverses the revision order" begin
        mktempdir() do dir
            manifest, _ = toy_benchmark(dir)
            config = two_revisions(Experiments.REPO_ROOT; repeats=2, variants=["baseline", "prepost"])
            attempts = Experiments.plan_attempts(config, manifest)
            @test [(a.repeat, a.stage, a.variant) for a in attempts] ==
                  [(1, "control", :baseline), (1, "candidate", :baseline), (1, "", :prepost),
                   (2, "candidate", :baseline), (2, "control", :baseline), (2, "", :prepost)]
            @test allunique(a.id for a in attempts)
        end
    end

    @testset "Commands run the attempt's own checkout" begin
        mktempdir() do other
            manifest, _ = toy_benchmark(other)
            for mode in ("cold", "cli")
                config = two_revisions(other; mode)
                candidate = Experiments.plan_attempts(config, manifest)[2]
                command = string(Experiments.measured_command(candidate, config, "in", "out", "report"))
                @test occursin("--project=$other", command)
                @test occursin(joinpath(other, "demo.jl"), command) == (mode == "cli")
            end
        end
    end

    @testset "A revision that cannot load stops the run before timing" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            empty = mkpath(joinpath(dir, "empty"))
            out = joinpath(dir, "run")
            @test_throws "candidate" Experiments.run_experiment(two_revisions(empty), manifest;
                                                                data_dir=data, out_dir=out)
            @test !isfile(joinpath(out, "runs.csv"))
        end
    end
end
