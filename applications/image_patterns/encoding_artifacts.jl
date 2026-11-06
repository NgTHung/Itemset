function write_transactions_tsv(path, images, transactions)
    io = IOBuffer()
    println(io, "image_id\tlabel\twords")
    for (image, transaction) in zip(images, transactions)
        println(io, image.id, '\t', image.label, '\t', join(transaction, ','))
    end
    write(path, String(take!(io)))
end

function write_word_frequencies_tsv(path, frequencies)
    io = IOBuffer()
    println(io, "word\timage_count")
    for (word, frequency) in enumerate(frequencies)
        println(io, word, '\t', frequency)
    end
    write(path, String(take!(io)))
end

function write_representatives_tsv(path, examples)
    io = IOBuffer()
    println(io, "word\timage_id\trow\tcol\tdistance2\tpatch_row_major")
    for example in examples
        println(io, example.word, '\t', example.ref.image_id, '\t', example.ref.row, '\t',
                example.ref.col, '\t', example.distance2, '\t', join(example.patch))
    end
    write(path, String(take!(io)))
end

function write_codebook_tsv(path, codebook)
    io = IOBuffer()
    println(io, "word\t", join(["pixel_$index" for index in 1:16], '\t'))
    for word in axes(codebook, 2)
        println(io, word, '\t', join(codebook[:, word], '\t'))
    end
    write(path, String(take!(io)))
end

"""
    write_encoding(dir, encoding; source_sha, revision, command, source_url="", dirty=false)

Validate all image/word mappings before writing into a staged directory, then
publish it at a fresh `dir`. The TOML manifest records provenance, settings,
statistics and artifact hashes. Invalid data or an existing path throws
`ArgumentError`. No item position or multiplicity is retained in transactions.
"""
function write_encoding(dir, encoding::ImageEncoding; source_sha, revision, command, source_url="", dirty=false)
    ispath(dir) && throw(ArgumentError("output path already exists: $dir"))
    occursin(r"^[0-9a-f]{64}$", source_sha) || throw(ArgumentError("invalid source SHA-256: $source_sha"))
    validate_encoding(encoding)
    stats = encoding_statistics(encoding)
    s = encoding.settings
    settings = Dict("vocabulary_size" => s.vocabulary_size, "min_ink" => s.min_ink,
                    "iterations" => s.iterations, "max_distance2" => s.max_distance2,
                    "seed" => s.seed, "patch_size" => [4, 4], "patch_stride" => 4)
    counts = item_frequencies(encoding.transactions)
    output = abspath(dir)
    mkpath(dirname(output))
    mktempdir(dirname(output)) do staged
        write_transactions_tsv(joinpath(staged, "transactions.tsv"), encoding.images, encoding.transactions)
        write_word_frequencies_tsv(joinpath(staged, "word_frequencies.tsv"), [get(counts, word, 0) for word in 1:s.vocabulary_size])
        write_representatives_tsv(joinpath(staged, "representatives.tsv"), encoding.examples)
        write_codebook_tsv(joinpath(staged, "codebook.tsv"), encoding.codebook)
        write_digit_montage_svg(joinpath(staged, "digits.svg"), encoding.images)
        if isempty(encoding.examples)
            write(joinpath(staged, "visual_words.svg"), "<svg xmlns=\"http://www.w3.org/2000/svg\"><text x=\"8\" y=\"20\">No accepted words</text></svg>\n")
        else
            write_word_montage_svg(joinpath(staged, "visual_words.svg"), encoding.examples)
        end
        open(joinpath(staged, "widths.tsv"), "w") do io
            println(io, "width\timages")
            for width in 0:stats["widths_max"]
                println(io, width, '\t', count(t -> length(t) == width, encoding.transactions))
            end
        end
        open(joinpath(staged, "summary.txt"), "w") do io
            println(io, "input_sha256=", source_sha, "\njulia_version=", VERSION)
            for (key, value) in sort!(collect(merge(settings, stats)); by=first)
                println(io, key, '=', value isa Vector ? join(value, ',') : value)
            end
        end
        hashes = Dict(file => open(io -> bytes2hex(sha256(io)), joinpath(staged, file)) for file in readdir(staged))
        manifest = Dict("source_sha256" => source_sha, "source_url" => source_url,
            "git_revision" => revision, "git_dirty" => dirty, "command" => command,
            "julia_version" => string(VERSION), "settings" => settings, "statistics" => stats,
            "spatial_information_retained" => false, "multiplicity_retained" => false,
            "evaluation_scope" => "descriptive_all_images", "artifact_sha256" => hashes)
        open(io -> TOML.print(io, manifest; sorted=true), joinpath(staged, "manifest.toml"), "w")
        mv(staged, output)
    end
    dir
end
