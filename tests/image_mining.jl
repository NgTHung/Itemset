@testset "Visual-word mining evidence" begin
    runs = @inferred SemeionPilot.mine_visual_patterns(IMAGE_CASE.transactions; levels=(0.5, 0.6))
    @test runs[1].patterns == IMAGE_CASE.expected
    @test runs[2].patterns == IMAGE_CASE.sensitive_expected
    @test runs[1].min_count == 2 && runs[2].min_count == 3
    pixels = zeros(UInt8, 16, 16)
    pixels[1, 1:4] .= 1
    images = [SemeionPilot.DigitImage(42, 3, pixels),
              SemeionPilot.DigitImage(7, 3, zeros(UInt8, 16, 16))]
    encoding = SemeionPilot.prepare_encoding(images;
        settings=SemeionPilot.EncodingSettings(vocabulary_size=1))
    evidence = SemeionPilot.pattern_evidence(encoding, (1,); limit=1)
    @test evidence.supporting == [1]
    @test evidence.matching == [1] && evidence.nonmatching == [2]
    @test_throws ArgumentError SemeionPilot.pattern_evidence(encoding, (2,))
    mktempdir() do dir
        output = joinpath(dir, "mining")
        SemeionPilot.write_mining_run(output, encoding;
            source_sha=repeat("a", 64), revision="fixture", command="fixture", levels=(0.5, 1.0))
        manifest = TOML.parsefile(joinpath(output, "mining_manifest.toml"))
        @test read_itemset_records(joinpath(output, "patterns-0.5.txt")) == [(itemset=(1,), support=1, line=1)]
        @test isempty(read(joinpath(output, "patterns-1.0.txt"), String))
        for (file, expected) in manifest["artifact_sha256"]
            @test Experiments.file_sha256(joinpath(output, file)) == expected
        end
    end
end
