@testset "Semeion image pilot" begin
    @testset "Shared transaction frequencies" begin
        @test item_frequencies([[1, 1, 2], Int[], [2]]) == Dict(1 => 1, 2 => 2)
        @test_throws ArgumentError item_frequencies([[-1]])
    end

    @testset "Dataset parsing" begin
        row = join(vcat(fill("0.0000", 256), ["0", "0", "1"], fill("0", 7)), " ")
        image = only(SemeionPilot.read_semeion(IOBuffer(row * "\n")))
        @test (image.id, image.label, size(image.pixels)) == (1, 2, (16, 16))
        @test_throws "line 1" SemeionPilot.read_semeion(IOBuffer("0 1\n"))
        @test_throws "line 2" SemeionPilot.read_semeion(IOBuffer(row * "\n" * replace(row, "0.0000" => "2.0000", count=1) * "\n"))
        @test_throws "line 1" SemeionPilot.read_semeion(IOBuffer(replace(row, "0 0 1" => "0 0 0", count=1) * "\n"))
    end

    @testset "Seeded codebook and transaction contract" begin
        blank = SemeionPilot.DigitImage(1, 0, zeros(UInt8, 16, 16))
        stroke_pixels = zeros(UInt8, 16, 16)
        stroke_pixels[1:4, 1] .= 1
        stroke_pixels[5, 5:8] .= 1
        images = [blank, SemeionPilot.DigitImage(2, 1, stroke_pixels)]
        patches, refs = SemeionPilot.extract_patches(images; min_ink=2)
        @test [(ref.image_id, ref.row, ref.col) for ref in refs] == [(2, 1, 1), (2, 5, 5)]
        codebook = SemeionPilot.fit_codebook(patches, 2; rng=Xoshiro(DEFAULT_SEED))
        @test codebook == SemeionPilot.fit_codebook(patches, 2; rng=Xoshiro(DEFAULT_SEED))
        @test SemeionPilot.encode_images(images, codebook; min_ink=2, max_distance2=0.0) == [Int[], [1, 2]]
        @test_throws ArgumentError SemeionPilot.fit_codebook(patches, 3; rng=Xoshiro(DEFAULT_SEED))
        codebook[1, 1] = NaN
        @test_throws ArgumentError SemeionPilot.encode_images(images, codebook)
    end

    @testset "Supporting montage uses source IDs" begin
        images = [SemeionPilot.DigitImage(id, label, zeros(UInt8, 16, 16)) for (id, label) in [(10, 0), (42, 1)]]
        mktempdir() do dir
            path = joinpath(dir, "support.svg")
            SemeionPilot.write_supporting_images_svg(path, images, [Int[], [2]], (2,))
            svg = read(path, String)
            @test occursin("image 42, label 1", svg) && !occursin("image 10", svg)
        end
    end
end
