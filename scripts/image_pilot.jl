include(joinpath(@__DIR__, "encode_images.jl"))
const SUPPORT_LEVELS = (0.2, 0.1, 0.05)

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

function main(args; entry=semeion_entry(), fetch=Experiments.Downloads.download,
              vocabulary_size::Int=VOCABULARY_SIZE)
    prepared = prepare_encoding_command(args; entry, fetch, vocabulary_size)
    images, transactions = prepared.encoding.images, prepared.encoding.transactions
    output_dir = prepared.output
    runs = mining_runs(transactions)
    threshold_results = threshold_results_tsv(runs)
    supporting_results = supporting_results_tsv(runs, images, transactions)
    write_command_encoding(prepared, args; script="scripts/image_pilot.jl")
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
    output_dir
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
