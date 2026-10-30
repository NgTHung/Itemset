@testset "Semeion image pilot" begin
    @testset "Shared transaction frequencies" begin
        @test item_frequencies([[1, 1, 2], Int[], [2]]) == Dict(1 => 1, 2 => 2)
        @test item_frequencies(Vector{Int}[]) == Dict{Int,Int}()
        @test_throws ArgumentError item_frequencies([[-1]])
        @test_throws ArgumentError item_frequencies([1])
    end
    @testset "Dataset parsing" begin
        row = join(vcat(fill("0.0000", 256), ["0", "0", "1"], fill("0", 7)), " ")
        images = SemeionPilot.read_semeion(IOBuffer(row * "\n"))
        @test length(images) == 1
        @test images[1].id == 1
        @test images[1].label == 2
        @test size(images[1].pixels) == (16, 16)
        @test all(iszero, images[1].pixels)
        @test_throws "line 1" SemeionPilot.read_semeion(IOBuffer("0 1\n"))
        @test_throws "line 2" SemeionPilot.read_semeion(IOBuffer(row * "\n" * replace(row, "0.0000" => "2.0000", count=1) * "\n"))
        @test_throws "line 1" SemeionPilot.read_semeion(IOBuffer(replace(row, "0 0 1" => "0 0 0", count=1) * "\n"))
    end

    @testset "Patch codebook and transaction contract" begin
        blank = SemeionPilot.DigitImage(1, 0, zeros(UInt8, 16, 16))
        stroke_pixels = zeros(UInt8, 16, 16)
        stroke_pixels[1:4, 1] .= 1
        stroke_pixels[5, 5:8] .= 1
        stroke = SemeionPilot.DigitImage(2, 1, stroke_pixels)
        images = [blank, stroke]
        patches, refs = SemeionPilot.extract_patches(images; min_ink=2)
        @test length(patches) == 2
        @test [(ref.image_id, ref.row, ref.col) for ref in refs] == [(2, 1, 1), (2, 5, 5)]
        @test all(sum(patch) == 4 for patch in patches)

        first_fit = SemeionPilot.fit_codebook(patches, 2; rng=Xoshiro(DEFAULT_SEED))
        second_fit = SemeionPilot.fit_codebook(patches, 2; rng=Xoshiro(DEFAULT_SEED))
        @test first_fit == second_fit
        transactions = SemeionPilot.encode_images(images, first_fit; min_ink=2, max_distance2=0.0)
        @test transactions[1] == Int[]
        @test transactions[2] == [1, 2]
        @test SemeionPilot.supporting_images(transactions, (1, 2)) == [2]
        @test SemeionPilot.supporting_images(IMAGE_CASE.transactions, (1, 2)) == IMAGE_CASE.supporting_images[(1, 2)]
        examples = SemeionPilot.representative_patches(patches, refs, first_fit)
        @test [example.word for example in examples] == [1, 2]
        @test all(example.ref.image_id == 2 && example.distance2 == 0.0 for example in examples)
        mktempdir() do dir
            digit_path = joinpath(dir, "digits.svg")
            word_path = joinpath(dir, "words.svg")
            SemeionPilot.write_digit_montage_svg(digit_path, images)
            SemeionPilot.write_word_montage_svg(word_path, examples)
            @test occursin("<svg", read(digit_path, String))
            @test occursin("digit 0", read(digit_path, String))
            @test occursin("word 1", read(word_path, String))
            @test occursin("image 2", read(word_path, String))
        end
        @test_throws ArgumentError SemeionPilot.fit_codebook(patches, 3; rng=Xoshiro(DEFAULT_SEED))
        @test_throws ArgumentError SemeionPilot.encode_images(images, first_fit; max_distance2=-1.0)
        invalid_codebook = copy(first_fit)
        invalid_codebook[1, 1] = NaN
        @test_throws ArgumentError SemeionPilot.encode_images(images, invalid_codebook)
        @test_throws ArgumentError SemeionPilot.representative_patches(patches, refs, invalid_codebook)
    end

    @testset "Representatives follow accepted assignments" begin
        patch = ntuple(_ -> UInt8(0), 16)
        refs = [SemeionPilot.PatchRef(42, 1, 1)]
        centers = hcat(zeros(16), fill(0.1, 16))
        examples = SemeionPilot.representative_patches([patch], refs, centers; max_distance2=0.0)
        @test [example.word for example in examples] == [1]
        @test only(examples).ref.image_id == 42
        @test isempty(SemeionPilot.representative_patches([patch], refs, fill(1.0, 16, 1); max_distance2=1.0))
        @test_throws ArgumentError SemeionPilot.representative_patches([patch], refs, centers; max_distance2=NaN)
        tied = SemeionPilot.representative_patches([patch], refs, zeros(16, 2); max_distance2=0.0)
        @test [example.word for example in tied] == [1]
    end

    @testset "Supporting montage uses source IDs" begin
        images = [SemeionPilot.DigitImage(id, label, zeros(UInt8, 16, 16))
                  for (id, label) in [(10, 0), (42, 1)]]
        mktempdir() do dir
            path = joinpath(dir, "support.svg")
            SemeionPilot.write_supporting_images_svg(path, images, [Int[], [2]], (2,))
            svg = read(path, String)
            @test occursin("image 42, label 1", svg)
            @test !occursin("image 10", svg)
            @test_throws ArgumentError SemeionPilot.write_supporting_images_svg(path, images, [[2]], (2,))
            @test read(path, String) == svg
        end
    end
end
