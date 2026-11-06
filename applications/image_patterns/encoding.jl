"""Frozen patch encoder settings; `seed` constructs a private Xoshiro RNG per fit."""
Base.@kwdef struct EncodingSettings
    vocabulary_size::Int = 24
    min_ink::Int = 2
    iterations::Int = 25
    max_distance2::Float64 = 1.0
    seed::Int = DEFAULT_SEED
end

"""Images, codebook, transactions, and source patches from one encoding fit."""
struct ImageEncoding
    settings::EncodingSettings
    images::Vector{DigitImage}
    patches::Vector{Patch}
    references::Vector{PatchRef}
    codebook::Matrix{Float64}
    transactions::Vector{Vector{Int}}
    examples::Vector{WordExample}
end

"""
    prepare_encoding(images; settings=EncodingSettings()) -> ImageEncoding

Fit and encode in source order with a private RNG initialized from `settings.seed`.
Empty transactions remain aligned with image IDs. Invalid settings or data throw
`ArgumentError`; word IDs are 1-based codebook columns.
"""
function prepare_encoding(images::AbstractVector{DigitImage}; settings=EncodingSettings())
    patches, references = extract_patches(images; min_ink=settings.min_ink)
    codebook = fit_codebook(patches, settings.vocabulary_size;
                            rng=Xoshiro(settings.seed), iterations=settings.iterations)
    transactions = encode_images(images, codebook; min_ink=settings.min_ink,
                                  max_distance2=settings.max_distance2)
    examples = representative_patches(patches, references, codebook;
                                       max_distance2=settings.max_distance2)
    ImageEncoding(settings, collect(images), patches, references, codebook, transactions, examples)
end

function validate_encoding(encoding::ImageEncoding)
    s = encoding.settings
    isempty(encoding.images) && throw(ArgumentError("encoding has no images"))
    size(encoding.codebook, 2) == s.vocabulary_size || throw(ArgumentError("codebook vocabulary size differs from settings"))
    transactions = encode_images(encoding.images, encoding.codebook;
                                  min_ink=s.min_ink, max_distance2=s.max_distance2)
    transactions == encoding.transactions || throw(ArgumentError("transactions differ from image/codebook assignments"))
    patches, references = extract_patches(encoding.images; min_ink=s.min_ink)
    patches == encoding.patches && references == encoding.references ||
        throw(ArgumentError("patches or source references differ from images"))
    representatives = representative_patches(patches, references, encoding.codebook; max_distance2=s.max_distance2)
    representatives == encoding.examples || throw(ArgumentError("representatives differ from accepted assignments"))
    nothing
end

function median_width(widths)
    isempty(widths) && throw(ArgumentError("cannot take median of empty widths"))
    ordered = sort(widths)
    n = length(ordered)
    isodd(n) ? Float64(ordered[cld(n, 2)]) : (ordered[n ÷ 2] + ordered[n ÷ 2 + 1]) / 2
end

"""Return width and image-frequency statistics, retaining empty images in the denominator."""
function encoding_statistics(encoding::ImageEncoding)
    widths = length.(encoding.transactions)
    n, k = length(widths), encoding.settings.vocabulary_size
    counts = item_frequencies(encoding.transactions)
    Dict("images" => n, "patches" => length(encoding.patches),
         "distinct_patches" => length(unique(encoding.patches)), "words_used" => length(counts),
         "total_word_presences" => sum(widths), "widths_min" => minimum(widths),
         "widths_median" => median_width(widths), "widths_mean" => sum(widths) / n,
         "widths_max" => maximum(widths), "empty_transactions" => count(isempty, encoding.transactions),
         "transaction_density" => sum(widths) / (n * k),
         "label_counts_0_to_9" => [count(image -> image.label == label, encoding.images) for label in 0:9])
end
