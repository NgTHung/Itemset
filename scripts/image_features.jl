include(joinpath(@__DIR__, "mine_image_patterns.jl"))

"""
    features_main(args; kwargs...) -> String

Mine Semeion as `mine_image_patterns.jl` does, then write `image_features.tsv` to the output folder: one
row per image (source ID, digit label) and one column per frequent pattern of the lowest threshold, named by
its visual-word IDs. A cell is 1 exactly when the whole pattern occurs in that image, so each column sums to
the support of its pattern. `args` and `kwargs` are those of `mining_main`.
"""
function features_main(args; kwargs...)
    run = run_mining_command(args; kwargs...)
    lowest = argmin(r -> r.minsup, run.runs)
    columns = sort!(collect(keys(lowest.patterns)))
    features = SemeionPilot.itemset_features(run.encoding.transactions, columns)
    # A mismatch would mean the feature rule and the miner disagree on what contains a pattern.
    vec(sum(features; dims=1)) == [lowest.patterns[pattern] for pattern in columns] ||
        error("feature column sums differ from the supports of their patterns")
    open(joinpath(run.output, "image_features.tsv"), "w") do io
        println(io, join(vcat("image_id", "label", [join(pattern, ' ') for pattern in columns]), '\t'))
        for (i, image) in enumerate(run.encoding.images)
            println(io, join(vcat(image.id, image.label, Int.(features[i, :])), '\t'))
        end
    end
    return run.output
end

main(args; kwargs...) = features_main(args; kwargs...)

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
