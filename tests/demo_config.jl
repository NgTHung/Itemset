@testset "The demo config sweeps Mushroom against SPMF" begin
    root = dirname(@__DIR__)
    config = Experiments.load_run_config(joinpath(root, "experiments", "configs", "demo-mushroom.toml"))
    manifest = Experiments.load_manifest(joinpath(root, "data", "benchmark", "manifest.toml"))
    @test config.name == "demo-mushroom"
    @test config.variants == [:baseline, :optimized, :spmf]
    @test config.mode == :cli
    @test config.repeats == 1
    @test config.verify_outputs
    @test [(s.dataset, s.minsup) for s in config.series] == [("mushroom", [0.5, 0.4, 0.3, 0.2, 0.1])]
    # Planning rejects any threshold where SPMF and support_threshold disagree.
    @test length(Experiments.plan_attempts(config, manifest)) == 15
end
