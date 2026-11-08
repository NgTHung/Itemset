@testset "A cold CLI run compiles nothing" begin
    # --trace-compile lists every method a fresh process compiles at run time, so an
    # empty list means the graded CLI path runs from the package image.
    root = dirname(@__DIR__)
    mktempdir() do dir
        trace = joinpath(dir, "trace.jl")
        output = joinpath(dir, "patterns.txt")
        for variant in ("baseline", "optimized")
            args = ["--minsup", "0.5", "--variant", variant, "--output", output, joinpath(TOY_DIR, "baskets.txt")]
            command = `$(Base.julia_cmd()) --startup-file=no --project=$root --trace-compile=$trace
                       $(joinpath(root, "demo.jl")) $args`
            rm(trace; force=true)
            run(pipeline(command; stdout=devnull))
            # Julia creates the trace file only when it compiles something.
            @test (isfile(trace) ? readlines(trace) : String[]) == String[]
        end
    end
end
