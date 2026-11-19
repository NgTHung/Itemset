module PrepareScript
include(joinpath(dirname(@__DIR__), "applications", "market_basket", "prepare.jl"))
end

module AnalyzeScript
include(joinpath(dirname(@__DIR__), "applications", "market_basket", "analyze.jl"))
end

@testset "$name prints usage for -h and rejects other options before any work" for (name, script) in
        (("prepare.jl", PrepareScript), ("analyze.jl", AnalyzeScript))
    mktempdir() do dir
        cd(dir) do
            @test redirect_stdout(() -> script.main(["-h"]), devnull) == 0
            for bad in (["--bogus"], ["one", "two"])
                @test_throws ArgumentError script.main(bad)
            end
            @test isempty(readdir(dir))
        end
    end
end
