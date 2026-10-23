using ItemsetMining
using Random
using SHA

include(joinpath(dirname(@__DIR__), "applications", "image_patterns", "SemeionPilot.jl"))
using .SemeionPilot

const VOCABULARY_SIZE = 24
const MIN_INK = 2
const MAX_DISTANCE2 = 1.0
const ITERATIONS = 25
const SUPPORT_LEVELS = (0.2, 0.1, 0.05)

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
        println(io, example.word, '\t', example.ref.image_id, '\t',
                example.ref.row, '\t', example.ref.col, '\t',
                example.distance2, '\t', join(example.patch))
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

function threshold_results_tsv(transactions)
    io = IOBuffer()
    println(io, "minsup\tmin_count\titemsets\telapsed_seconds")
    mine(transactions; minsup=first(SUPPORT_LEVELS), variant=:baseline)
    for minsup in SUPPORT_LEVELS
        elapsed = @elapsed patterns = mine(transactions; minsup, variant=:baseline)
        println(io, minsup, '\t', support_threshold(minsup, length(transactions)),
                '\t', length(patterns), '\t', elapsed)
    end
    String(take!(io))
end

function main(args)
    length(args) == 2 ||
        throw(ArgumentError("usage: julia --project=. scripts/image_pilot.jl INPUT OUTPUT_DIR; got $(length(args)) arguments"))
    input, output_dir = args
    isfile(input) || throw(ArgumentError("input file does not exist: $input"))
    ispath(output_dir) && throw(ArgumentError("output path already exists: $output_dir"))
    images = SemeionPilot.read_semeion(input)
    patches, references = SemeionPilot.extract_patches(images; min_ink=MIN_INK)
    codebook = SemeionPilot.fit_codebook(patches, VOCABULARY_SIZE;
                                         rng=Xoshiro(DEFAULT_SEED), iterations=ITERATIONS)
    transactions = SemeionPilot.encode_images(images, codebook;
                                               min_ink=MIN_INK, max_distance2=MAX_DISTANCE2)
    examples = SemeionPilot.representative_patches(patches, references, codebook)
    frequencies = [count(transaction -> word in transaction, transactions)
                   for word in 1:VOCABULARY_SIZE]
    widths = sort!(length.(transactions))
    label_counts = [count(image -> image.label == label, images) for label in 0:9]
    input_sha = bytes2hex(sha256(read(input)))
    threshold_results = threshold_results_tsv(transactions)
    summary = """
    dataset=UCI Semeion Handwritten Digit
    source=https://archive.ics.uci.edu/dataset/178/semeion+handwritten+digit
    license=CC BY 4.0
    input_sha256=$input_sha
    julia_version=$(VERSION)
    seed=$(DEFAULT_SEED)
    vocabulary_size=$VOCABULARY_SIZE
    min_ink=$MIN_INK
    max_distance2=$MAX_DISTANCE2
    iterations=$ITERATIONS
    images=$(length(images))
    patches=$(length(patches))
    distinct_patches=$(length(unique(patches)))
    widths_min=$(first(widths))
    widths_median=$(widths[cld(length(widths), 2)])
    widths_max=$(last(widths))
    empty_transactions=$(count(isempty, transactions))
    words_used=$(count(>(0), frequencies))
    label_counts_0_to_9=$(join(label_counts, ','))
    """
    mkpath(output_dir)
    write(joinpath(output_dir, "summary.txt"), summary)
    write_transactions_tsv(joinpath(output_dir, "transactions.tsv"), images, transactions)
    write_word_frequencies_tsv(joinpath(output_dir, "word_frequencies.tsv"), frequencies)
    write_representatives_tsv(joinpath(output_dir, "representatives.tsv"), examples)
    write_codebook_tsv(joinpath(output_dir, "codebook.tsv"), codebook)
    SemeionPilot.write_digit_montage_svg(joinpath(output_dir, "digits.svg"), images)
    SemeionPilot.write_word_montage_svg(joinpath(output_dir, "visual_words.svg"), examples)
    write(joinpath(output_dir, "thresholds.tsv"), threshold_results)
    print(summary)
    output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
