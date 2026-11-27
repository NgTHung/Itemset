"""A curve point carrying only what the output-size checks read."""
size_point(dataset, count, output; series="Optimized") = Experiments.CurvePoint(series, dataset, "0.5", count,
    output, 1, 1, 0, 0, 0, 0, 0, NaN, NaN, NaN)

@testset "Output size" begin
    @testset "Counts never fall when the threshold falls" begin
        points = [size_point("chess", 30, 10), size_point("chess", 20, 25), size_point("chess", 10, 25),
                  size_point("retail", 9, 4), size_point("retail", 5, 100), size_point("chess", 40, nothing)]
        @test Experiments.check_monotone_counts(points) === nothing
        shrinking = [size_point("chess", 30, 10), size_point("chess", 20, 9)]
        err = try Experiments.check_monotone_counts(shrinking) catch e e end
        @test err isa ArgumentError && occursin("chess", err.msg) && occursin("20", err.msg) && occursin("30", err.msg)
    end

    @testset "Itemset length profile" begin
        mktempdir() do dir
            path = joinpath(dir, "out.txt")
            write(path, "1 #SUP: 4\n2 #SUP: 3\n1 2 #SUP: 3\n1 2 3 #SUP: 2\n")
            @test Experiments.itemset_length_counts(path) == [2, 1, 1]
        end
    end

    @testset "Outputs nest across thresholds" begin
        mktempdir() do dir
            transactions = read_transactions(joinpath(TOY_DIR, "groceries.txt"))
            high, low = joinpath(dir, "high.txt"), joinpath(dir, "low.txt")
            write_itemsets(high, mine(transactions; minsup=0.6))
            write_itemsets(low, mine(transactions; minsup=0.2))
            high_count = support_threshold(0.6, length(transactions))
            @test Experiments.check_nested_outputs(high, low, high_count) === nothing

            # A support that differs between thresholds means one run counted wrong.
            lines = readlines(high)
            write(high, join([replace(lines[1], r"#SUP: (\d+)" => s -> "#SUP: $(parse(Int, s[7:end]) + 1)");
                              lines[2:end]], '\n') * "\n")
            @test_throws "support" Experiments.check_nested_outputs(high, low, high_count)

            # Dropping an itemset from the high output leaves the low output with one too many above it.
            write(high, join(lines[2:end], '\n') * "\n")
            @test_throws "missing" Experiments.check_nested_outputs(high, low, high_count)
        end
    end
end
