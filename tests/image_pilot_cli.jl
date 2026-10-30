module ImagePilotCLI
include(joinpath(dirname(@__DIR__), "scripts", "image_pilot.jl"))
end

@testset "Image pilot command" begin
    @test_throws ArgumentError ImagePilotCLI.main(String[])
    @test_throws ArgumentError ImagePilotCLI.main(["one", "two", "three"])
    @test ImagePilotCLI.median_width([1, 4]) == 2.5
    @test ImagePilotCLI.median_width([1, 4, 5]) == 4.0
    mktempdir() do dir
        input = joinpath(dir, "semeion.data")
        output = joinpath(dir, "run")
        pixels = zeros(Int, 256)
        pixels[1:4] .= 1
        row = join(vcat(string.(pixels), ["1"], fill("0", 9)), " ") * "\n"
        entry = ImagePilotCLI.Experiments.DatasetEntry(name="semeion", version="test",
            file="semeion.data", sha256=bytes2hex(ImagePilotCLI.sha256(row)), stats=nothing,
            sources=[ImagePilotCLI.Experiments.DatasetSource(url="test", format=:text)])
        calls = Ref(0)
        fetch = (url, path) -> (calls[] += 1; write(path, row); path)
        @test ImagePilotCLI.main([input, output]; entry, fetch, vocabulary_size=1) == output
        @test calls[] == 1
        @test readlines(joinpath(output, "transactions.tsv")) == ["image_id\tlabel\twords", "1\t0\t1"]
        @test readlines(joinpath(output, "word_frequencies.tsv")) == ["word\timage_count", "1\t1"]
        @test startswith(read(joinpath(output, "representatives.tsv"), String), "word\timage_id\trow\tcol\tdistance2\tpatch_row_major\n1\t1\t1\t1\t0.0\t1111")
        @test startswith(read(joinpath(output, "codebook.tsv"), String), "word\tpixel_1")
        center = split(last(readlines(joinpath(output, "codebook.tsv"))), '\t')
        @test parse.(Float64, center[2:end]) == vcat(ones(4), zeros(12))
        @test occursin("widths_median=1.0", read(joinpath(output, "summary.txt"), String))
        for level in ImagePilotCLI.SUPPORT_LEVELS
            @test read_itemset_records(joinpath(output, "patterns-$level.txt"))[1].support == 1
            @test occursin("image 1", read(joinpath(output, "supporting-$level.svg"), String))
        end
        @test occursin("0.2\t1\t1\t1\t0", read(joinpath(output, "supporting_images.tsv"), String))
        @test_throws ArgumentError ImagePilotCLI.main([input, output]; entry, fetch, vocabulary_size=1)
        @test calls[] == 1
        @test ImagePilotCLI.main([input, joinpath(dir, "cached")]; entry, fetch, vocabulary_size=1) == joinpath(dir, "cached")
        @test calls[] == 1
        @test_throws ArgumentError ImagePilotCLI.main([joinpath(dir, "wrong.data"), joinpath(dir, "wrong")]; entry, fetch)
        write(input, "corrupted")
        bad_output = joinpath(dir, "bad")
        bad_fetch = (url, path) -> write(path, "<html>error</html>")
        @test_throws ErrorException ImagePilotCLI.main([input, bad_output]; entry, fetch=bad_fetch, vocabulary_size=1)
        @test !ispath(bad_output)
        @test read(input, String) == "corrupted"
        @test ImagePilotCLI.main([input, bad_output]; entry, fetch, vocabulary_size=1) == bad_output
        @test read(input, String) == row
    end
end
