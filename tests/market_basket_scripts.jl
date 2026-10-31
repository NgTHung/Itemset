module PrepareScript
include(joinpath(dirname(@__DIR__), "applications", "market_basket", "prepare.jl"))
end

module AnalyzeScript
include(joinpath(dirname(@__DIR__), "applications", "market_basket", "analyze.jl"))
end

@testset "Market basket scripts" begin
    @testset "Output folder argument" begin
        usage = "Usage: x"
        @test MarketBasket.output_folder(String[], "default", usage) == "default"
        @test MarketBasket.output_folder(["out"], "default", usage) == "out"
        for bad in (["-h"], ["--hepl"], ["-x"], ["--out=1"], ["a", "b"])
            @test_throws ArgumentError MarketBasket.output_folder(bad, "default", usage)
        end
        err = try
            MarketBasket.output_folder(["--bogus"], "default", usage)
        catch e
            e
        end
        @test occursin("--bogus", err.msg) && occursin(usage, err.msg)
        @test MarketBasket.is_help(["-h"]) && MarketBasket.is_help(["--help"])
        @test !MarketBasket.is_help(String[]) && !MarketBasket.is_help(["help"]) && !MarketBasket.is_help(["-h", "x"])
    end

    @testset "$name prints usage for -h and rejects other options before any work" for (name, script) in
            (("prepare.jl", PrepareScript), ("analyze.jl", AnalyzeScript))
        mktempdir() do dir
            cd(dir) do
                for help in (["-h"], ["--help"])
                    @test redirect_stdout(() -> script.main(help), devnull) == 0
                end
                for bad in (["-x"], ["--bogus"], ["one", "two"])
                    @test_throws ArgumentError script.main(bad)
                end
                @test isempty(readdir(dir))
            end
        end
    end
end
