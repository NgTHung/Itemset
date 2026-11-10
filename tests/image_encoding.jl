@testset "Frozen image encoding" begin
    pixels = zeros(UInt8, 16, 16)
    pixels[1, 1:4] .= 1
    images = [SemeionPilot.DigitImage(42, 3, pixels),
              SemeionPilot.DigitImage(7, 0, zeros(UInt8, 16, 16))]
    settings = SemeionPilot.EncodingSettings(vocabulary_size=1)
    encoding = SemeionPilot.prepare_encoding(images; settings)
    @test encoding.transactions == [[1], Int[]]
    @test encoding.codebook == SemeionPilot.prepare_encoding(images; settings).codebook
    @test_throws ArgumentError SemeionPilot.prepare_encoding([images[1], images[1]]; settings)
    centers = zeros(16, 1)
    centers[1, 1] = 1.0
    # The distance cutoff is inclusive.
    @test SemeionPilot.encode_images([images[2]], centers; min_ink=0, max_distance2=1.0) == [[1]]
    @test SemeionPilot.encode_images([images[2]], centers; min_ink=0, max_distance2=prevfloat(1.0)) == [Int[]]
    mktempdir() do dir
        output = joinpath(dir, "encoding")
        source_sha = repeat("a", 64)
        SemeionPilot.write_encoding(output, encoding; source_sha, revision="fixture", command="encode fixture")
        manifest = TOML.parsefile(joinpath(output, "manifest.toml"))
        @test manifest["settings"]["seed"] == DEFAULT_SEED
        @test manifest["source_sha256"] == source_sha
        @test readlines(joinpath(output, "transactions.tsv")) == ["image_id\tlabel\twords", "42\t3\t1", "7\t0\t"]
        for (file, expected) in manifest["artifact_sha256"]
            @test Experiments.file_sha256(joinpath(output, file)) == expected
        end
        @test_throws ArgumentError SemeionPilot.write_encoding(output, encoding; source_sha, revision="fixture", command="fixture")
        push!(encoding.transactions[1], 2)
        invalid = joinpath(dir, "invalid")
        @test_throws ArgumentError SemeionPilot.write_encoding(invalid, encoding; source_sha, revision="fixture", command="fixture")
        @test !ispath(invalid)
    end
end
