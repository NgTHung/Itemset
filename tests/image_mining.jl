@testset "Visual-word mining evidence" begin
    runs = SemeionPilot.mine_visual_patterns(IMAGE_CASE.transactions; levels=(0.5, 0.6))
    @test runs[1].patterns == IMAGE_CASE.expected
    @test (@inferred SemeionPilot.mine_visual_patterns(IMAGE_CASE.transactions; levels=(0.5,)))[1].patterns == IMAGE_CASE.expected
    @test runs[2].patterns == IMAGE_CASE.sensitive_expected
    @test runs[1].min_count == 2 && runs[2].min_count == 3
    @test all(run -> run.elapsed >= 0, runs)
    @test_throws ArgumentError SemeionPilot.mine_visual_patterns(IMAGE_CASE.transactions; levels=())
    @test SemeionPilot.select_patterns(IMAGE_CASE.expected) == [(2,), (1, 2)]
    pixels = zeros(UInt8, 16, 16)
    pixels[1, 1:4] .= 1
    images = [SemeionPilot.DigitImage(42, 3, pixels),
              SemeionPilot.DigitImage(7, 3, zeros(UInt8, 16, 16))]
    encoding = SemeionPilot.prepare_encoding(images;
        settings=SemeionPilot.EncodingSettings(vocabulary_size=1))
    evidence = SemeionPilot.pattern_evidence(encoding, (1,); limit=1)
    @test evidence.supporting == [1]
    @test evidence.matching == [1] && evidence.nonmatching == [2]
    @test evidence.label_counts == [0,0,0,1,0,0,0,0,0,0]
    @test_throws ArgumentError SemeionPilot.pattern_evidence(encoding, (2,))
    mktempdir() do dir
        output = joinpath(dir, "mining")
        SemeionPilot.write_mining_run(output, encoding;
            source_sha=repeat("a", 64), revision="fixture", command="fixture", levels=(0.5, 1.0))
        manifest = TOML.parsefile(joinpath(output, "mining_manifest.toml"))
        @test manifest["variant"] == "baseline"
        @test manifest["runs"][1]["min_count"] == 1
        @test manifest["runs"][2]["itemsets"] == 0
        @test read_itemset_records(joinpath(output, "patterns-0.5.txt")) == [(itemset=(1,), support=1, line=1)]
        @test isempty(read(joinpath(output, "patterns-1.0.txt"), String))
        @test occursin("support\t42\t3\t1\t", read(joinpath(output, "examples.tsv"), String))
        @test occursin("nonmatch\t7\t3\t\t1", read(joinpath(output, "examples.tsv"), String))
        @test occursin("42\t1\t1\t1\t0.0\t1111", read(joinpath(output, "example_patches.tsv"), String))
        svg = read(joinpath(output, "supporting-0.5.svg"), String)
        @test occursin("image 42", svg) && occursin("image 7", svg)
        @test occursin("missing word 1", svg)
        for (file, expected) in manifest["artifact_sha256"]
            @test Experiments.file_sha256(joinpath(output, file)) == expected
        end
        @test_throws ArgumentError SemeionPilot.write_mining_run(output, encoding;
            source_sha=repeat("a", 64), revision="fixture", command="fixture")
        @test !isfile(joinpath(output, "supporting-1.0.svg"))
    end
end
