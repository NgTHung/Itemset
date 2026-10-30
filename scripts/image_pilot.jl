using ItemsetMining
using Random
using SHA

include(joinpath(dirname(@__DIR__), "applications", "image_patterns", "SemeionPilot.jl"))
include(joinpath(dirname(@__DIR__), "experiments", "Experiments.jl"))
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

function median_width(widths)
    isempty(widths) && throw(ArgumentError("cannot take median of empty widths"))
    ordered = sort(widths)
    n = length(ordered)
    isodd(n) ? Float64(ordered[cld(n, 2)]) : (ordered[n ÷ 2] + ordered[n ÷ 2 + 1]) / 2
end

function mining_runs(transactions)
    mine(transactions; minsup=first(SUPPORT_LEVELS), variant=:baseline)
    map(SUPPORT_LEVELS) do minsup
        elapsed = @elapsed patterns = mine(transactions; minsup, variant=:baseline)
        (; minsup, min_count=support_threshold(minsup, length(transactions)), patterns, elapsed)
    end
end

function threshold_results_tsv(runs)
    io = IOBuffer()
    println(io, "minsup\tmin_count\titemsets\telapsed_seconds")
    for result in runs
        println(io, result.minsup, '\t', result.min_count,
                '\t', length(result.patterns), '\t', result.elapsed)
    end
    String(take!(io))
end

function supporting_results_tsv(runs, images, transactions)
    io = IOBuffer()
    println(io, "minsup\titems\tsupport\timage_ids\tlabels")
    for result in runs, itemset in sort!(collect(keys(result.patterns)))
        positions = SemeionPilot.supporting_images(transactions, itemset)
        length(positions) == result.patterns[itemset] || error("support scan differs for $itemset")
        println(io, result.minsup, '\t', join(itemset, ','), '\t', length(positions), '\t',
                join([images[p].id for p in positions], ','), '\t',
                join([images[p].label for p in positions], ','))
    end
    String(take!(io))
end

semeion_entry() = Experiments.load_manifest(joinpath(dirname(@__DIR__), "data", "raw", "manifest.toml"))["semeion"]

function main(args; entry=semeion_entry(), fetch=Experiments.Downloads.download,
              vocabulary_size::Int=VOCABULARY_SIZE)
    length(args) == 2 ||
        throw(ArgumentError("usage: julia --project=. scripts/image_pilot.jl INPUT OUTPUT_DIR; got $(length(args)) arguments"))
    input, output_dir = args
    ispath(output_dir) && throw(ArgumentError("output path already exists: $output_dir"))
    basename(input) == entry.file || throw(ArgumentError("input must be named $(entry.file): $input"))
    mkpath(dirname(abspath(input)))
    input = Experiments.prepare_dataset(entry, dirname(abspath(input)); fetch)
    images = SemeionPilot.read_semeion(input)
    patches, references = SemeionPilot.extract_patches(images; min_ink=MIN_INK)
    codebook = SemeionPilot.fit_codebook(patches, vocabulary_size;
                                         rng=Xoshiro(DEFAULT_SEED), iterations=ITERATIONS)
    transactions = SemeionPilot.encode_images(images, codebook;
                                               min_ink=MIN_INK, max_distance2=MAX_DISTANCE2)
    examples = SemeionPilot.representative_patches(patches, references, codebook; max_distance2=MAX_DISTANCE2)
    counts = item_frequencies(transactions)
    frequencies = [get(counts, word, 0) for word in 1:vocabulary_size]
    widths = sort!(length.(transactions))
    label_counts = [count(image -> image.label == label, images) for label in 0:9]
    input_sha = bytes2hex(sha256(read(input)))
    runs = mining_runs(transactions)
    threshold_results = threshold_results_tsv(runs)
    supporting_results = supporting_results_tsv(runs, images, transactions)
    summary = """
    dataset=UCI Semeion Handwritten Digit
    source=https://archive.ics.uci.edu/dataset/178/semeion+handwritten+digit
    license=CC BY 4.0
    input_sha256=$input_sha
    julia_version=$(VERSION)
    seed=$(DEFAULT_SEED)
    vocabulary_size=$vocabulary_size
    min_ink=$MIN_INK
    max_distance2=$MAX_DISTANCE2
    iterations=$ITERATIONS
    images=$(length(images))
    patches=$(length(patches))
    distinct_patches=$(length(unique(patches)))
    widths_min=$(first(widths))
    widths_median=$(median_width(widths))
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
    write(joinpath(output_dir, "supporting_images.tsv"), supporting_results)
    for result in runs
        write_itemsets(joinpath(output_dir, "patterns-$(result.minsup).txt"), result.patterns)
        isempty(result.patterns) && continue
        selected = first(sort!(collect(keys(result.patterns));
                               by=key -> (-length(key), -result.patterns[key], key)))
        SemeionPilot.write_supporting_images_svg(joinpath(output_dir, "supporting-$(result.minsup).svg"),
                                                 images, transactions, selected)
    end
    print(summary)
    output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
