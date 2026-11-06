two_revisions(other; kw...) = toy_config(; revisions=[
    Dict("stage" => "control", "project" => Experiments.REPO_ROOT),
    Dict("stage" => "candidate", "project" => other)], kw...)

@testset "Revisions alternate within one run" begin
    @testset "A config names each revision by stage and checkout" begin
        mktempdir() do other
            config = two_revisions(other)
            @test config.revisions == [Experiments.Revision("control", Experiments.REPO_ROOT),
                                       Experiments.Revision("candidate", other)]
            @test toy_config().revisions == [Experiments.Revision("baseline", Experiments.REPO_ROOT)]
            @test only(toy_config(; stage="precompile").revisions).stage == "precompile"
            same = [Dict("stage" => "control", "project" => other), Dict("stage" => "control", "project" => other)]
            @test_throws "distinct" toy_config(; revisions=same)
            @test_throws ArgumentError toy_config(; revisions=[])
            @test_throws ArgumentError toy_config(; revisions=[Dict("stage" => "a b", "project" => other)])
            @test_throws ArgumentError toy_config(; revisions=[Dict("stage" => "a", "project" => joinpath(other, "missing"))])
            @test_throws "either" toy_config(; stage="x", revisions=[Dict("stage" => "a", "project" => other)])
            @test_throws "either" toy_config(; project=other, revisions=[Dict("stage" => "a", "project" => other)])
        end
    end

    @testset "Each repeat reverses the revision order" begin
        mktempdir() do dir
            manifest, _ = toy_benchmark(dir)
            config = two_revisions(Experiments.REPO_ROOT; repeats=2, variants=["baseline", "prepost"])
            attempts = Experiments.plan_attempts(config, manifest)
            @test [(a.repeat, a.stage, a.variant) for a in attempts] ==
                  [(1, "control", :baseline), (1, "candidate", :baseline), (1, "", :prepost),
                   (2, "candidate", :baseline), (2, "control", :baseline), (2, "", :prepost)]
            @test allunique(a.id for a in attempts)
            @test attempts[1].id == "baskets-m0.5-r1-control-baseline"
            @test attempts[3].id == "baskets-m0.5-r1-prepost"
            single = only(Experiments.plan_attempts(toy_config(), manifest))
            @test single.id == "baskets-m0.5-r1-baseline"
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

    @testset "Rows and archives name their revision" begin
        mktempdir() do dir
            manifest, data = toy_benchmark(dir)
            out = joinpath(dir, "run")
            config = two_revisions(Experiments.REPO_ROOT; mode="cli")
            rows = Experiments.run_experiment(config, manifest; data_dir=data, out_dir=out)
            @test [r["stage"] for r in rows] == ["control", "candidate"]
            @test all(r -> r["status"] == "ok" && !isempty(r["code_revision"]), rows)
            env = TOML.parsefile(joinpath(out, "environment.toml"))
            @test sort(collect(keys(env["code_revisions"]))) == ["candidate", "control"]
            checksums = TOML.parsefile(joinpath(out, "source-checksums.toml"))
            @test haskey(checksums, "package-control") && haskey(checksums, "package-candidate")
            @test isfile(joinpath(out, "package-candidate-worktree.patch"))
            summary = Experiments.summarize_rows(rows)
            @test sort([s["stage"] for s in summary]) == ["candidate", "control"]
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
