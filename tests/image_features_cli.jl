module ImageFeaturesCLI
include(joinpath(dirname(@__DIR__), "scripts", "image_features.jl"))
end

@testset "Image feature matrix command" begin
    @test_throws ArgumentError ImageFeaturesCLI.main(String[])
    mktempdir() do dir
        input = joinpath(dir, "semeion.data")
        pixels = zeros(Int, 256)
        pixels[1:4] .= 1
        row = join(vcat(string.(pixels), ["1"], fill("0", 9)), " ") * "\n"
        entry = ImageFeaturesCLI.Experiments.DatasetEntry(name="semeion", version="test",
            file="semeion.data", sha256=bytes2hex(ImageFeaturesCLI.sha256(row)), stats=nothing,
            sources=[ImageFeaturesCLI.Experiments.DatasetSource(url="test", format=:text)])
        fetch = (url, path) -> (write(path, row); path)
        output = joinpath(dir, "features")
        @test ImageFeaturesCLI.main([input, output]; entry, fetch, vocabulary_size=1) == output
        @test readlines(joinpath(output, "image_features.tsv")) == ["image_id\tlabel\t1", "1\t0\t1"]
        @test isfile(joinpath(output, "patterns-0.05.txt"))
        @test_throws ArgumentError ImageFeaturesCLI.main([input, output]; entry, fetch, vocabulary_size=1)
    end
end
