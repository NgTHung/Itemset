const CURVE_HEADER = ["attempt_id", "dataset", "minsup_relative", "minsup_count", "variant", "stage", "mode",
                       "timing_scope", "status", "correctness_status", "elapsed_seconds", "output_count"]

function curve_row(dataset, minsup, count, variant, seconds; stage="s", mode="cli", scope="process",
                   status="ok", correctness="exact", output="10", id="a")
    return Dict("attempt_id"=>id, "dataset"=>dataset, "minsup_relative"=>minsup, "minsup_count"=>string(count),
                "variant"=>variant, "stage"=>stage, "mode"=>mode, "timing_scope"=>scope, "status"=>status,
                "correctness_status"=>correctness, "elapsed_seconds"=>string(seconds), "output_count"=>output)
end

"""Write `rows` as `runs.csv` in a fresh run folder under `dir` and return the folder."""
function curve_run(dir, name, rows)
    run = mkpath(joinpath(dir, name))
    open(joinpath(run, "runs.csv"), "w") do io
        println(io, join(CURVE_HEADER, ','))
        for row in rows
            println(io, join((Experiments.csv_field(row[h]) for h in CURVE_HEADER), ','))
        end
    end
    return run
end

@testset "Runtime curves" begin
    @testset "CSV reader" begin
        mktempdir() do dir
            path = joinpath(dir, "x.csv")
            write(path, "\ufeffa,b,c\r\n1,\"x,y\",\"say \"\"hi\"\"\"\r\n2,\"two\nlines\",z\r\n")
            @test Experiments.read_csv_rows(path) ==
                  [Dict("a"=>"1", "b"=>"x,y", "c"=>"say \"hi\""), Dict("a"=>"2", "b"=>"two\nlines", "c"=>"z")]
            write(path, "a,b\n")
            @test Experiments.read_csv_rows(path) == Dict{String,String}[]
            write(path, "a,b\n1,2\n\n3,4\n")
            @test length(Experiments.read_csv_rows(path)) == 2
            write(path, "a,b\n1,2\n3\n")
            err = try Experiments.read_csv_rows(path) catch e e end
            @test err isa ArgumentError && occursin("line 3", err.msg) && occursin("2 fields", err.msg)
            write(path, "a,b\n1,\"open\n")
            err = try Experiments.read_csv_rows(path) catch e e end
            @test err isa ArgumentError && occursin("unterminated", err.msg) && occursin("line 2", err.msg)
            write(path, "")
            @test_throws ArgumentError Experiments.read_csv_rows(path)
            @test_throws ArgumentError Experiments.read_csv_rows(joinpath(dir, "missing.csv"))
        end
    end

    @testset "Series specifications" begin
        spec = Experiments.parse_series_spec("Optimized=runs/final:optimized@dense#cli")
        @test (spec.label, spec.run, spec.variant, spec.stage, spec.mode) == ("Optimized", "runs/final", "optimized", "dense", "cli")
        spec = Experiments.parse_series_spec("Base=C:\\data\\run 1:baseline")
        @test (spec.label, spec.run, spec.variant, spec.stage, spec.mode) == ("Base", "C:\\data\\run 1", "baseline", "", "")
        spec = Experiments.parse_series_spec("SPMF=r:spmf#cold")
        @test (spec.variant, spec.stage, spec.mode) == ("spmf", "", "cold")
        for bad in ("nolabel", "A=norun", "A=run:", "=run:x", "A=run:@s", "A=run:x#")
            @test_throws ArgumentError Experiments.parse_series_spec(bad)
        end
    end

    @testset "Aggregate samples and keep every failure visible" begin
        mktempdir() do dir
            rows = [curve_row("toy", "0.5", 2, "baseline", t; id="ok$t") for t in 1:5]
            # Phase rows and other variants are not part of a process curve.
            push!(rows, curve_row("toy", "0.5", 2, "baseline", 99; scope="mine"),
                        curve_row("toy", "0.5", 2, "spmf", 99; stage=""))
            append!(rows, [curve_row("toy", "0.25", 1, "baseline", t; output="30", id="p$t") for t in (10, 20)])
            push!(rows,
                curve_row("toy", "0.25", 1, "baseline", 300; status="timeout", correctness="not_checked", output=""),
                curve_row("toy", "0.25", 1, "baseline", 5; correctness="failed", status="error", output=""),
                curve_row("toy", "0.25", 1, "baseline", 5; correctness="not_checked", output=""),
                curve_row("toy", "0.25", 1, "baseline", 5; status="interrupted", correctness="not_checked", output=""),
                curve_row("toy", "0.25", 1, "baseline", 5; status="error", correctness="not_checked", output=""),
                curve_row("toy", "0.25", 1, "baseline", 5; status="skipped", correctness="not_checked", output=""))
            run = curve_run(dir, "run", rows)
            spec = Experiments.parse_series_spec("Base=$run:baseline")
            high, low = Experiments.curve_points(spec)
            @test (high.series, high.dataset, high.minsup_relative, high.minsup_count) == ("Base", "toy", "0.5", 2)
            @test (high.exact_samples, high.total_samples, high.output_count) == (5, 5, 10)
            @test (high.q1, high.median, high.q3) == (2.0, 3.0, 4.0)
            @test (low.exact_samples, low.total_samples, low.output_count) == (2, 8, 30)
            @test (low.q1, low.median, low.q3) == (12.5, 15.0, 17.5)
            @test (low.timeouts, low.correctness_failures, low.unverified, low.interrupted, low.other_incomplete) == (1, 1, 1, 1, 2)
            @test low.exact_samples + low.timeouts + low.correctness_failures + low.unverified +
                  low.interrupted + low.other_incomplete == low.total_samples
            # Interpolated quartiles agree with the harness summary.
            four = [curve_row("toy", "0.5", 2, "baseline", t) for t in 1:4]
            point = only(Experiments.curve_points(Experiments.parse_series_spec(
                "B=$(curve_run(dir, "four", four)):baseline")))
            @test (point.q1, point.median, point.q3) == (1.75, 2.5, 3.25)
        end
    end

    @testset "A point with no exact sample has no time" begin
        mktempdir() do dir
            rows = [curve_row("toy", "0.5", 2, "baseline", 300; status="timeout", correctness="not_checked", output="")]
            point = only(Experiments.curve_points(Experiments.parse_series_spec(
                "B=$(curve_run(dir, "run", rows)):baseline")))
            @test isnan(point.median) && isnan(point.q1) && isnan(point.q3)
            @test point.output_count === nothing && point.timeouts == 1
        end
    end

    @testset "Stage and mode selection" begin
        mktempdir() do dir
            rows = [curve_row("toy", "0.5", 2, "optimized", t; stage=stage, mode=mode)
                    for (stage, mode, t) in (("a", "cli", 1), ("a", "cold", 2), ("b", "cli", 3))]
            run = curve_run(dir, "run", rows)
            pick(text) = Experiments.curve_points(Experiments.parse_series_spec("O=$run:$text"))
            @test only(pick("optimized@a#cli")).median == 1.0
            @test only(pick("optimized@a#cold")).median == 2.0
            @test only(pick("optimized@b")).median == 3.0
            err = try pick("optimized") catch e e end
            @test err isa ArgumentError && occursin("stages", err.msg) && occursin("@STAGE", err.msg)
            err = try pick("optimized@a") catch e e end
            @test err isa ArgumentError && occursin("modes", err.msg) && occursin("#MODE", err.msg)
            err = try pick("baseline") catch e e end
            @test err isa ArgumentError && occursin("no process rows", err.msg)
            @test_throws ArgumentError Experiments.curve_points(Experiments.parse_series_spec("O=$(joinpath(dir, "none")):optimized"))
        end
    end

    @testset "Runs lacking a required column are rejected" begin
        mktempdir() do dir
            run = mkpath(joinpath(dir, "run"))
            write(joinpath(run, "runs.csv"), "dataset,variant\ntoy,baseline\n")
            err = try Experiments.curve_points(Experiments.parse_series_spec("B=$run:baseline")) catch e e end
            @test err isa ArgumentError && occursin("elapsed_seconds", err.msg) && occursin("minsup_relative", err.msg)
        end
    end

    @testset "Two thresholds with one count are never merged" begin
        mktempdir() do dir
            rows = [curve_row("toy", "0.25", 1, "baseline", 2), curve_row("toy", "0.1", 1, "baseline", 5)]
            err = try
                Experiments.curve_points(Experiments.parse_series_spec("B=$(curve_run(dir, "run", rows)):baseline"))
            catch e
                e
            end
            @test err isa ArgumentError && occursin("0.25", err.msg) && occursin("0.1", err.msg)
        end
    end

    @testset "Contenders at one point must report the same output count" begin
        mktempdir() do dir
            a = curve_run(dir, "a", [curve_row("toy", "0.5", 2, "baseline", 1; output="10")])
            b = curve_run(dir, "b", [curve_row("toy", "0.5", 2, "spmf", 1; stage="", output="10")])
            c = curve_run(dir, "c", [curve_row("toy", "0.5", 2, "prepost", 1; stage="", output="11")])
            series(run, variant) = Experiments.curve_points(Experiments.parse_series_spec("$variant=$run:$variant"))
            @test Experiments.check_agreement([series(a, "baseline"); series(b, "spmf")]) === nothing
            err = try Experiments.check_agreement([series(a, "baseline"); series(c, "prepost")]) catch e e end
            @test err isa ArgumentError && occursin("toy", err.msg) && occursin("10", err.msg) && occursin("11", err.msg)
            within = [curve_row("toy", "0.5", 2, "baseline", 1; output="10"),
                      curve_row("toy", "0.5", 2, "baseline", 2; output="12")]
            @test_throws ArgumentError Experiments.curve_points(Experiments.parse_series_spec(
                "B=$(curve_run(dir, "w", within)):baseline"))
        end
    end

    @testset "Median ratios and geometric mean" begin
        mktempdir() do dir
            rows(variant, times) = [curve_row("toy", m, c, variant, t; stage="") for (m, c, t) in times]
            base = curve_run(dir, "base", rows("baseline", [("0.5", 4, 8), ("0.25", 2, 2), ("0.1", 1, 5)]))
            fast = curve_run(dir, "fast", rows("optimized", [("0.5", 4, 2), ("0.25", 2, 1)]))
            points = [Experiments.curve_points(Experiments.parse_series_spec("Base=$base:baseline"));
                      Experiments.curve_points(Experiments.parse_series_spec("Fast=$fast:optimized"))]
            ratios = Experiments.median_ratios(points, "Base", "Fast")
            @test [(r.minsup_relative, r.ratio) for r in ratios] == [("0.5", 4.0), ("0.25", 2.0)]
            @test Experiments.geometric_mean([r.ratio for r in ratios]) ≈ sqrt(8)
            @test isempty(Experiments.median_ratios(points, "Base", "Missing"))
            @test_throws ArgumentError Experiments.geometric_mean(Float64[])
            @test_throws ArgumentError Experiments.geometric_mean([1.0, -2.0])
        end
    end

    @testset "Write the tidy curve table" begin
        mktempdir() do dir
            rows = [curve_row("toy", "0.5", 2, "baseline", t) for t in 1:5]
            push!(rows, curve_row("toy", "0.5", 2, "baseline", 300; status="timeout", correctness="not_checked", output=""))
            points = Experiments.curve_points(Experiments.parse_series_spec("Base=$(curve_run(dir, "run", rows)):baseline"))
            out = joinpath(dir, "curves.csv")
            Experiments.write_curves(out, points)
            back = only(Experiments.read_csv_rows(out))
            @test back["series"] == "Base" && back["dataset"] == "toy" && back["minsup_relative"] == "0.5"
            @test back["output_count"] == "10" && back["exact_samples"] == "5" && back["total_samples"] == "6"
            @test back["timeouts"] == "1" && back["median_seconds"] == "3.0"
            @test back["q1_seconds"] == "2.0" && back["q3_seconds"] == "4.0"
            blank = Experiments.CurvePoint("B", "toy", "0.5", 2, nothing, 0, 1, 1, 0, 0, 0, 0, NaN, NaN, NaN)
            Experiments.write_curves(out, [blank])
            back = only(Experiments.read_csv_rows(out))
            @test back["median_seconds"] == "" && back["output_count"] == ""
        end
    end
end

module CurvesScript
include(joinpath(dirname(@__DIR__), "scripts", "runtime_curves.jl"))
end

@testset "Runtime curves script" begin
    quiet(f) = redirect_stdout(f, devnull)
    mktempdir() do dir
        rows(variant, times; stage="") = [curve_row("toy", m, c, variant, t; stage=stage, output=o)
                                          for (m, c, t, o) in times]
        base = curve_run(dir, "base", rows("baseline", [("0.5", 4, 8, "5"), ("0.25", 2, 4, "9")]))
        fast = curve_run(dir, "fast", rows("optimized", [("0.5", 4, 2, "5"), ("0.25", 2, 1, "9")]; stage="x"))
        slow_run = [curve_row("toy", "0.5", 4, "spmf", 300; status="timeout", correctness="not_checked", output=""),
                    curve_row("toy", "0.25", 2, "spmf", 6; output="9")]
        ref = curve_run(dir, "ref", slow_run)
        out = joinpath(dir, "out")
        specs = ["Baseline=$base:baseline", "Optimized=$fast:optimized@x", "SPMF=$ref:spmf"]

        @testset "Writes the curve and ratio tables and reports limits" begin
            text = mktemp() do path, io
                redirect_stdout(io) do
                    @test CurvesScript.main(["--out", out, "--ratio", "Baseline/Optimized", "--ratio", "SPMF/Optimized", specs...]) == 0
                end
                close(io)
                read(path, String)
            end
            curves = Experiments.read_csv_rows(joinpath(out, "curves.csv"))
            @test length(curves) == 6 && Set(r["series"] for r in curves) == Set(["Baseline", "Optimized", "SPMF"])
            ratios = Experiments.read_csv_rows(joinpath(out, "ratios.csv"))
            @test [(r["numerator"], r["denominator"], r["minsup_relative"], r["ratio"]) for r in ratios] ==
                  [("Baseline", "Optimized", "0.5", "4.0"), ("Baseline", "Optimized", "0.25", "4.0"),
                   ("SPMF", "Optimized", "0.25", "6.0")]
            @test occursin("Baseline/Optimized", text) && occursin("geometric mean 4.0", text)
            @test occursin("SPMF", text) && occursin("1 timeout", text) && occursin("0.5", text)
        end

        @testset "Prints usage for -h and rejects bad arguments before writing" begin
            @test quiet(() -> CurvesScript.main(["-h"])) == 0
            @test quiet(() -> CurvesScript.main(["--help"])) == 0
            fresh = joinpath(dir, "fresh")
            for bad in (String[], ["--out", fresh], ["--out", fresh, "--bogus", specs[1]], ["--out"],
                        ["--out", fresh, "--ratio", "Baseline", specs[1]],
                        ["--out", fresh, "--ratio", "Baseline/Missing", specs[1]],
                        ["--out", fresh, specs[1], specs[1]], ["--out", fresh, "nolabel"],
                        ["--out", fresh, "A=$(joinpath(dir, "none")):baseline"],
                        ["--out", fresh, "-x", specs[1]])
                @test_throws ArgumentError quiet(() -> CurvesScript.main(bad))
            end
            @test !ispath(fresh)
            disagree = curve_run(dir, "disagree", rows("prepost", [("0.5", 4, 1, "6")]))
            @test_throws ArgumentError quiet(() -> CurvesScript.main(["--out", fresh, specs[1], "P=$disagree:prepost"]))
            @test !ispath(fresh)
        end
    end
end
