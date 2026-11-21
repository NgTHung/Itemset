module ImagePilotCLI
include(joinpath(dirname(@__DIR__), "scripts", "image_pilot.jl"))
end

@testset "Image pilot command" begin
    @test_throws ArgumentError ImagePilotCLI.main(String[])
    @test_throws ArgumentError ImagePilotCLI.main(["one", "two", "three"])
    @test_throws ArgumentError ImagePilotCLI.main(["one", "two", "--minsup", "0.1,0.1"])
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
        @test readlines(joinpath(output, "transactions.tsv")) == ["image_id\tlabel\twords", "1\t0\t1"]
        for level in ImagePilotCLI.SUPPORT_LEVELS
            @test read_itemset_records(joinpath(output, "patterns-$level.txt"))[1].support == 1
        end
        @test occursin("0.2\t1\t1\t1\t0", read(joinpath(output, "supporting_images.tsv"), String))
        sensitivity = joinpath(dir, "sensitivity")
        @test ImagePilotCLI.main([input, sensitivity, "--vocabulary-size", "1", "--minsup", "0.055,0.06"]; entry, fetch) == sensitivity
        sensitivity_manifest = TOML.parsefile(joinpath(sensitivity, "mining_manifest.toml"))
        @test [r["minsup"] for r in sensitivity_manifest["runs"]] == [0.055, 0.06]
        @test occursin("--vocabulary-size", join(sensitivity_manifest["command"], " "))
        @test_throws ArgumentError ImagePilotCLI.main([input, output]; entry, fetch, vocabulary_size=1)
        # A corrupted cached input is fetched again; a failed fetch leaves no output folder.
        write(input, "corrupted")
        bad_output = joinpath(dir, "bad")
        bad_fetch = (url, path) -> write(path, "<html>error</html>")
        @test_throws ErrorException ImagePilotCLI.main([input, bad_output]; entry, fetch=bad_fetch, vocabulary_size=1)
        @test !ispath(bad_output)
        @test ImagePilotCLI.main([input, bad_output]; entry, fetch, vocabulary_size=1) == bad_output
        @test calls[] == 2
    end
end
