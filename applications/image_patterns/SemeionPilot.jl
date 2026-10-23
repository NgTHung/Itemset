module SemeionPilot

using Random

const Patch = NTuple{16,UInt8}

"""
    DigitImage(id, label, pixels)

One Semeion image with a 0-based digit label and a binary 16×16 pixel matrix.
Invalid dimensions, pixels, IDs, or labels throw `ArgumentError`.
"""
struct DigitImage
    id::Int
    label::Int
    pixels::Matrix{UInt8}

    function DigitImage(id::Int, label::Int, pixels::Matrix{UInt8})
        id >= 1 || throw(ArgumentError("image ID must be positive: $id"))
        0 <= label <= 9 || throw(ArgumentError("digit label must be 0:9: $label"))
        size(pixels) == (16, 16) || throw(ArgumentError("image $id has size $(size(pixels)), expected (16, 16)"))
        all(pixel -> pixel <= 1, pixels) || throw(ArgumentError("image $id contains a nonbinary pixel"))
        new(id, label, pixels)
    end
end

"""
    PatchRef(image_id, row, col)

Location of a 4×4 patch in the original 16×16 image; row and col are 1-based.
"""
struct PatchRef
    image_id::Int
    row::Int
    col::Int
end

"""
    read_semeion(io) -> Vector{DigitImage}

Read UCI's Semeion text rows as 256 binary pixels followed by a ten-column
one-hot digit label. Invalid rows throw `ArgumentError` with a line number.
"""
function read_semeion(io::IO)
    images = DigitImage[]
    for (line_number, line) in enumerate(eachline(io))
        fields = split(line)
        length(fields) == 266 ||
            throw(ArgumentError("line $line_number has $(length(fields)) fields, expected 266"))
        pixels = Matrix{UInt8}(undef, 16, 16)
        for index in 1:256
            value = tryparse(Float64, fields[index])
            (value === 0.0 || value === 1.0) ||
                throw(ArgumentError("line $line_number has invalid pixel $(fields[index]) at column $index"))
            pixels[div(index - 1, 16) + 1, mod(index - 1, 16) + 1] = UInt8(value)
        end
        label_bits = Vector{Int}(undef, 10)
        for index in 1:10
            value = tryparse(Int, fields[256 + index])
            (value === 0 || value === 1) ||
                throw(ArgumentError("line $line_number has invalid label $(fields[256 + index])"))
            label_bits[index] = value
        end
        sum(label_bits) == 1 || throw(ArgumentError("line $line_number has a non-one-hot digit label"))
        label = (findfirst(==(1), label_bits)::Int) - 1
        push!(images, DigitImage(length(images) + 1, label, pixels))
    end
    isempty(images) && throw(ArgumentError("Semeion input contains no images"))
    images
end

read_semeion(path::AbstractString) = open(read_semeion, path)

function patch_at(image::DigitImage, row::Int, col::Int)::Patch
    ntuple(16) do index
        image.pixels[row + div(index - 1, 4), col + mod(index - 1, 4)]
    end
end

"""
    extract_patches(images; min_ink=2) -> (patches, references)

Extract nonoverlapping 4×4 patches in image/row/column order. Patches with
fewer than `min_ink` foreground pixels are excluded.
"""
function extract_patches(images::AbstractVector{DigitImage}; min_ink::Int=2)
    0 <= min_ink <= 16 || throw(ArgumentError("min_ink must be 0:16: $min_ink"))
    patches = Patch[]
    references = PatchRef[]
    for image in images, row in 1:4:13, col in 1:4:13
        patch = patch_at(image, row, col)
        if sum(patch) >= min_ink
            push!(patches, patch)
            push!(references, PatchRef(image.id, row, col))
        end
    end
    patches, references
end

function nearest_word(patch::Patch, centers::Matrix{Float64})
    best_word = 1
    best_distance2 = Inf
    for word in axes(centers, 2)
        candidate = patch_distance2(patch, centers, word)
        if candidate < best_distance2
            best_word = word
            best_distance2 = candidate
        end
    end
    best_word, best_distance2
end

function patch_distance2(patch::Patch, centers::Matrix{Float64}, word::Int)
    distance2 = 0.0
    for index in 1:16
        difference = Float64(patch[index]) - centers[index, word]
        distance2 += difference * difference
    end
    distance2
end

"""
    fit_codebook(patches, vocabulary_size; rng, iterations=25) -> Matrix{Float64}

Fit a fixed-seed k-means codebook to 4×4 binary patches. Columns are visual
words. `rng` is required; invalid sizes or an empty patch set throw
`ArgumentError`.
"""
function fit_codebook(patches::AbstractVector{Patch}, vocabulary_size::Int;
                      rng::AbstractRNG, iterations::Int=25)
    vocabulary_size >= 1 || throw(ArgumentError("vocabulary_size must be positive: $vocabulary_size"))
    iterations >= 1 || throw(ArgumentError("iterations must be positive: $iterations"))
    unique_patches = unique(patches)
    vocabulary_size <= length(unique_patches) ||
        throw(ArgumentError("vocabulary_size $vocabulary_size exceeds $(length(unique_patches)) distinct patches"))
    centers = Matrix{Float64}(undef, 16, vocabulary_size)
    for (word, source) in enumerate(randperm(rng, length(unique_patches))[1:vocabulary_size])
        for index in 1:16
            centers[index, word] = unique_patches[source][index]
        end
    end
    sums = zeros(Float64, 16, vocabulary_size)
    counts = zeros(Int, vocabulary_size)
    for _ in 1:iterations
        fill!(sums, 0.0)
        fill!(counts, 0)
        for patch in patches
            word, _ = nearest_word(patch, centers)
            counts[word] += 1
            for index in 1:16
                sums[index, word] += patch[index]
            end
        end
        updated = false
        for word in 1:vocabulary_size
            counts[word] == 0 && continue
            for index in 1:16
                value = sums[index, word] / counts[word]
                updated |= value != centers[index, word]
                centers[index, word] = value
            end
        end
        !updated && break
    end
    centers
end

"""
    encode_images(images, codebook; min_ink=2, max_distance2=4.0)

Encode each image as sorted distinct 1-based visual-word IDs. An image whose
patches miss the threshold stays as an empty transaction.
"""
function encode_images(images::AbstractVector{DigitImage}, codebook::Matrix{Float64};
                       min_ink::Int=2, max_distance2::Float64=4.0)
    size(codebook, 1) == 16 && size(codebook, 2) >= 1 ||
        throw(ArgumentError("codebook must have 16 rows and at least one word: $(size(codebook))"))
    all(isfinite, codebook) || throw(ArgumentError("codebook contains a nonfinite center"))
    isfinite(max_distance2) && max_distance2 >= 0 ||
        throw(ArgumentError("max_distance2 must be finite and nonnegative: $max_distance2"))
    patches, references = extract_patches(images; min_ink)
    image_positions = Dict{Int,Int}()
    for (position, image) in enumerate(images)
        haskey(image_positions, image.id) && throw(ArgumentError("duplicate image ID $(image.id)"))
        image_positions[image.id] = position
    end
    transactions = [Int[] for _ in images]
    for (patch, reference) in zip(patches, references)
        word, distance2 = nearest_word(patch, codebook)
        if distance2 <= max_distance2
            push!(transactions[image_positions[reference.image_id]], word)
        end
    end
    for transaction in transactions
        sort!(transaction)
        unique!(transaction)
    end
    transactions
end

"""
    supporting_images(transactions, itemset) -> Vector{Int}

Return the 1-based image positions whose transactions contain every item.
The input itemset must be nonempty.
"""
function supporting_images(transactions::AbstractVector{<:AbstractVector{Int}}, itemset)
    isempty(itemset) && throw(ArgumentError("itemset must be nonempty"))
    [index for (index, transaction) in enumerate(transactions)
     if all(item -> item in transaction, itemset)]
end

"""
    WordExample(word, patch, ref, distance2)

An observed patch nearest to one codebook word, with its source image position.
"""
struct WordExample
    word::Int
    patch::Patch
    ref::PatchRef
    distance2::Float64
end

"""
    representative_patches(patches, references, codebook) -> Vector{WordExample}

Select an actual observed patch nearest to each codebook center. Equal distances
choose the first patch in dataset order.
"""
function representative_patches(patches::AbstractVector{Patch},
                                references::AbstractVector{PatchRef},
                                codebook::Matrix{Float64})
    length(patches) == length(references) ||
        throw(ArgumentError("patch and reference counts differ: $(length(patches)) and $(length(references))"))
    isempty(patches) && throw(ArgumentError("no patches available for representatives"))
    size(codebook, 1) == 16 && size(codebook, 2) >= 1 ||
        throw(ArgumentError("codebook must have 16 rows and at least one word: $(size(codebook))"))
    all(isfinite, codebook) || throw(ArgumentError("codebook contains a nonfinite center"))
    examples = WordExample[]
    for word in axes(codebook, 2)
        best_index = 1
        best_distance2 = Inf
        for index in eachindex(patches)
            candidate = patch_distance2(patches[index], codebook, word)
            if candidate < best_distance2
                best_index = index
                best_distance2 = candidate
            end
        end
        push!(examples, WordExample(word, patches[best_index], references[best_index], best_distance2))
    end
    examples
end

function svg_start!(io::IO, width::Int, height::Int)
    println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
    println(io, "<rect width=\"$width\" height=\"$height\" fill=\"white\"/>")
end

function svg_digit!(io::IO, pixels::Matrix{UInt8}, x::Int, y::Int)
    for row in 1:16, col in 1:16
        if pixels[row, col] == 1
            println(io, "<rect x=\"$(x + 4 * (col - 1))\" y=\"$(y + 4 * (row - 1))\" width=\"4\" height=\"4\" fill=\"black\"/>")
        end
    end
end

function svg_patch!(io::IO, patch::Patch, x::Int, y::Int)
    for row in 1:4, col in 1:4
        if patch[4 * (row - 1) + col] == 1
            println(io, "<rect x=\"$(x + 12 * (col - 1))\" y=\"$(y + 12 * (row - 1))\" width=\"12\" height=\"12\" fill=\"black\"/>")
        end
    end
end

"""
    write_digit_montage_svg(path, images)

Write the first image for each digit label as a deterministic SVG montage.
Throws `ArgumentError` if `images` is empty.
"""
function write_digit_montage_svg(path::AbstractString, images::AbstractVector{DigitImage})
    isempty(images) && throw(ArgumentError("cannot draw an empty image collection"))
    first_by_label = Dict{Int,DigitImage}()
    for image in images
        get!(first_by_label, image.label, image)
    end
    labels = sort!(collect(keys(first_by_label)))
    io = IOBuffer()
    svg_start!(io, 80 * length(labels), 100)
    for (position, label) in enumerate(labels)
        x = 8 + 80 * (position - 1)
        println(io, "<text x=\"$x\" y=\"14\" font-size=\"12\">digit $label</text>")
        svg_digit!(io, first_by_label[label].pixels, x, 22)
    end
    println(io, "</svg>")
    write(path, String(take!(io)))
    path
end

"""
    write_word_montage_svg(path, examples)

Write one observed 4×4 patch per visual word as a deterministic SVG montage.
Throws `ArgumentError` if `examples` is empty.
"""
function write_word_montage_svg(path::AbstractString, examples::AbstractVector{WordExample})
    isempty(examples) && throw(ArgumentError("cannot draw an empty word collection"))
    columns = min(length(examples), 8)
    rows = cld(length(examples), columns)
    io = IOBuffer()
    svg_start!(io, 100 * columns, 90 * rows)
    for (index, example) in enumerate(examples)
        x = 8 + 100 * mod(index - 1, columns)
        y = 90 * div(index - 1, columns)
        println(io, "<text x=\"$x\" y=\"$(y + 14)\" font-size=\"11\">word $(example.word)</text>")
        svg_patch!(io, example.patch, x, y + 20)
        println(io, "<text x=\"$x\" y=\"$(y + 81)\" font-size=\"9\">image $(example.ref.image_id)</text>")
    end
    println(io, "</svg>")
    write(path, String(take!(io)))
    path
end

end
