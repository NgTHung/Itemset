@testset "A cold CLI run compiles nothing" begin
    # --trace-compile lists every method a fresh process compiles at run time, so an
    # empty list means the graded CLI path runs from the package image.
    root = dirname(@__DIR__)
    mktempdir() do dir
        trace = joinpath(dir, "trace.jl")
        output = joinpath(dir, "patterns.txt")
        printed = joinpath(dir, "stdout.txt")
        @testset "$variant $threshold_args to $destination" for variant in ("baseline", "optimized"),
                threshold_args in (["--minsup", "0.5"], ["--min-count", "2"]), destination in ("--output", "stdout")
            output_args = destination == "--output" ? ["--output", output] : String[]
            args = [threshold_args; "--variant"; variant; output_args; joinpath(TOY_DIR, "baskets.txt")]
            command = `$(Base.julia_cmd()) --startup-file=no --project=$root --trace-compile=$trace
                       $(joinpath(root, "demo.jl")) $args`
            rm(trace; force=true)
            rm(output; force=true)
            run(pipeline(command; stdout=printed))
            # Julia creates the trace file only when it compiles something.
            @test (isfile(trace) ? readlines(trace) : String[]) == String[]
            @test read(destination == "--output" ? output : printed, String) == replace(read(joinpath(TOY_DIR, "baskets.expected.txt"), String), "\r\n"=>"\n")
        end
    end
end
