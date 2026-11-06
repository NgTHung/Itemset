@testset "Frozen image encoding" begin
    pixels = zeros(UInt8, 16, 16)
    pixels[1, 1:4] .= 1
    images = [SemeionPilot.DigitImage(42, 3, pixels),
              SemeionPilot.DigitImage(7, 0, zeros(UInt8, 16, 16))]
    settings = SemeionPilot.EncodingSettings(vocabulary_size=1)
    encoding = SemeionPilot.prepare_encoding(images; settings)
    repeated = SemeionPilot.prepare_encoding(images; settings)
    @test encoding.transactions == [[1], Int[]]
    @test encoding.codebook == repeated.codebook
    @test [image.id for image in encoding.images] == [42, 7]
    @test_throws ArgumentError SemeionPilot.prepare_encoding([images[1], images[1]]; settings)
    @test_throws ArgumentError SemeionPilot.prepare_encoding(images; settings=SemeionPilot.EncodingSettings(min_ink=17))
    @test_throws ArgumentError SemeionPilot.prepare_encoding(images; settings=SemeionPilot.EncodingSettings(vocabulary_size=1, iterations=0))
    centers = zeros(16, 1)
    centers[1, 1] = 1.0
    @test SemeionPilot.encode_images([images[2]], centers; min_ink=0, max_distance2=1.0) == [[1]]
    @test SemeionPilot.encode_images([images[2]], centers; min_ink=0, max_distance2=prevfloat(1.0)) == [Int[]]
    @test isempty(first(SemeionPilot.extract_patches(images; min_ink=16)))
    vertical = zeros(UInt8, 16, 16)
    vertical[1:4, 1] .= 1
    rejected = SemeionPilot.prepare_encoding([images[1], SemeionPilot.DigitImage(7, 0, vertical)];
        settings=SemeionPilot.EncodingSettings(vocabulary_size=1, max_distance2=0.0))
    @test all(isempty, rejected.transactions)
    @test isempty(rejected.examples)
    mktempdir() do dir
        output = joinpath(dir, "encoding")
        source_sha = repeat("a", 64)
        SemeionPilot.write_encoding(output, encoding; source_sha, revision="fixture", command="encode fixture")
        manifest = TOML.parsefile(joinpath(output, "manifest.toml"))
        @test manifest["settings"]["seed"] == DEFAULT_SEED
        @test manifest["statistics"]["transaction_density"] == 0.5
        @test manifest["statistics"]["widths_median"] == 0.5
        @test manifest["statistics"]["empty_transactions"] == 1
        @test manifest["statistics"]["label_counts_0_to_9"] == [1,0,0,1,0,0,0,0,0,0]
        @test manifest["source_sha256"] == source_sha
        @test manifest["git_revision"] == "fixture"
        @test readlines(joinpath(output, "transactions.tsv")) == ["image_id\tlabel\twords", "42\t3\t1", "7\t0\t"]
        @test readlines(joinpath(output, "widths.tsv")) == ["width\timages", "0\t1", "1\t1"]
        for (file, expected) in manifest["artifact_sha256"]
            @test Experiments.file_sha256(joinpath(output, file)) == expected
        end
        @test_throws ArgumentError SemeionPilot.write_encoding(output, encoding; source_sha, revision="fixture", command="fixture")
        push!(encoding.transactions[1], 2)
        invalid = joinpath(dir, "invalid")
        @test_throws ArgumentError SemeionPilot.write_encoding(invalid, encoding; source_sha, revision="fixture", command="fixture")
        @test !ispath(invalid)
        SemeionPilot.write_encoding(invalid, rejected; source_sha, revision="fixture", command="fixture")
        @test occursin("No accepted words", read(joinpath(invalid, "visual_words.svg"), String))
        @test_throws ArgumentError SemeionPilot.write_encoding(joinpath(dir, "sha"), rejected;
            source_sha="wrong", revision="fixture", command="fixture")
    end
end
