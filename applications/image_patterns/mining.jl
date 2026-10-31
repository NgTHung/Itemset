const MINING_LEVELS = (0.2, 0.1, 0.05)

"""Mine complete baseline maps after one untimed warm-up; measure only `mine` calls."""
function mine_visual_patterns(transactions; levels=MINING_LEVELS)
    isempty(levels) && throw(ArgumentError("support levels must be nonempty: $levels"))
    allunique(string.(levels)) || throw(ArgumentError("duplicate support levels: $levels"))
    counts = [support_threshold(level, length(transactions)) for level in levels]
    mine(transactions; minsup=first(levels), variant=:baseline)
    [begin
        elapsed = @elapsed patterns = mine(transactions; minsup=level, variant=:baseline)
        (; minsup=level, min_count=count, patterns, elapsed)
    end for (level, count) in zip(levels, counts)]
end

"""Choose the most supported singleton, combination, and longest pattern; resolve ties by IDs."""
function select_patterns(patterns)
    ordered = sort!(collect(keys(patterns)); by=key -> (-patterns[key], key))
    choices = eltype(ordered)[]
    for candidates in (filter(key -> length(key) == 1, ordered),
                       filter(key -> length(key) > 1, ordered),
                       sort(ordered; by=key -> (-length(key), -patterns[key], key)))
        isempty(candidates) || push!(choices, first(candidates))
    end
    unique(choices)
end

"""Find all supports and select source-ID-ordered matches plus near misses, preferring the same digit label."""
function pattern_evidence(encoding::ImageEncoding, itemset; limit::Int=3)
    limit >= 1 || throw(ArgumentError("example limit must be positive: $limit"))
    items = collect(itemset)
    !isempty(items) && issorted(items) && allunique(items) &&
        all(word -> word isa Int && 1 <= word <= encoding.settings.vocabulary_size, items) ||
        throw(ArgumentError("invalid visual-word itemset: $itemset"))
    supporting = supporting_images(encoding.transactions, itemset)
    matching = sort(supporting; by=p -> encoding.images[p].id)
    resize!(matching, min(limit, length(matching)))
    anchor = isempty(matching) ? -1 : encoding.images[first(matching)].label
    nonmatching = [p for p in eachindex(encoding.images) if !all(word -> word in encoding.transactions[p], itemset)]
    sort!(nonmatching; by=p -> (encoding.images[p].label != anchor,
          -count(word -> word in encoding.transactions[p], itemset), encoding.images[p].id))
    resize!(nonmatching, min(limit, length(nonmatching)))
    label_counts = [count(p -> encoding.images[p].label == label, supporting) for label in 0:9]
    (; itemset, supporting, matching, nonmatching, label_counts)
end

function accepted_example(encoding, position, word)
    best = nothing
    distance = Inf
    for (patch, ref) in zip(encoding.patches, encoding.references)
        ref.image_id == encoding.images[position].id || continue
        assigned, candidate = nearest_word(patch, encoding.codebook)
        if assigned == word && candidate <= encoding.settings.max_distance2 && candidate < distance
            best = WordExample(word, patch, ref, candidate)
            distance = candidate
        end
    end
    best === nothing && throw(ArgumentError("word $word has no accepted patch in image $(encoding.images[position].id)"))
    best
end

function example_rows(encoding, evidence)
    [begin
        present = [word for word in evidence.itemset if word in encoding.transactions[position]]
        missing = setdiff(collect(evidence.itemset), present)
        patches = [accepted_example(encoding, position, word) for word in present]
        (; kind, position, present, missing, patches)
    end for (kind, positions) in (("support", evidence.matching), ("nonmatch", evidence.nonmatching))
        for position in positions]
end

function mining_artifacts(encoding, runs)
    outputs = Dict{String,String}()
    thresholds, supports, examples, patches, selected = (IOBuffer() for _ in 1:5)
    println(thresholds, "minsup\tmin_count\titemsets\telapsed_seconds")
    println(supports, "minsup\titems\tsupport\timage_ids\tlabels")
    println(examples, "minsup\titems\tkind\timage_id\tlabel\tpresent_words\tmissing_words")
    println(patches, "minsup\titems\tkind\timage_id\tword\trow\tcol\tdistance2\tpatch_row_major")
    println(selected, "minsup\titems\tsupport\tlabel_counts_0_to_9")
    for run in runs
        println(thresholds, run.minsup, '\t', run.min_count, '\t', length(run.patterns), '\t', run.elapsed)
        outputs["patterns-$(run.minsup).txt"] = sprint(write_itemsets, run.patterns)
        for itemset in sort!(collect(keys(run.patterns)))
            positions = supporting_images(encoding.transactions, itemset)
            length(positions) == run.patterns[itemset] || throw(ArgumentError("support scan differs for $itemset"))
            println(supports, run.minsup, '\t', join(itemset, ','), '\t', length(positions), '\t',
                    join([encoding.images[p].id for p in positions], ','), '\t',
                    join([encoding.images[p].label for p in positions], ','))
        end
        choices = select_patterns(run.patterns)
        for (index, itemset) in enumerate(choices)
            evidence = pattern_evidence(encoding, itemset)
            rows = example_rows(encoding, evidence)
            println(selected, run.minsup, '\t', join(itemset, ','), '\t', length(evidence.supporting), '\t', join(evidence.label_counts, ','))
            for row in rows
                image = encoding.images[row.position]
                println(examples, run.minsup, '\t', join(itemset, ','), '\t', row.kind, '\t', image.id, '\t',
                        image.label, '\t', join(row.present, ','), '\t', join(row.missing, ','))
                for patch in row.patches
                    println(patches, run.minsup, '\t', join(itemset, ','), '\t', row.kind, '\t', image.id, '\t',
                            patch.word, '\t', patch.ref.row, '\t', patch.ref.col, '\t', patch.distance2, '\t', join(patch.patch))
                end
            end
            svg = pattern_evidence_svg(encoding, evidence, rows)
            outputs["examples-$(run.minsup)-$index.svg"] = svg
            index == length(choices) && (outputs["supporting-$(run.minsup).svg"] = svg)
        end
    end
    for (name, io) in zip(("thresholds.tsv", "supporting_images.tsv", "examples.tsv", "example_patches.tsv", "selected_patterns.tsv"),
                          (thresholds, supports, examples, patches, selected))
        outputs[name] = String(take!(io))
    end
    outputs
end

"""
    write_mining_run(dir, encoding; levels=MINING_LEVELS, source_sha, revision, command, ...)

Write complete baseline maps, exact support IDs, contrasting source images/patches,
and a timing/provenance manifest into a fresh directory. Validate supports before
publishing. No pattern-length or output cap is imposed; failures propagate.
"""
function write_mining_run(dir, encoding::ImageEncoding; levels=MINING_LEVELS,
                          source_sha, revision, command, source_url="", dirty=false, source_hashes=Dict{String,String}())
    ispath(dir) && throw(ArgumentError("output path already exists: $dir"))
    validate_encoding(encoding)
    runs = mine_visual_patterns(encoding.transactions; levels)
    outputs = mining_artifacts(encoding, runs)
    output = abspath(dir)
    mkpath(dirname(output))
    mktempdir(dirname(output)) do staged
        bundle = joinpath(staged, "bundle")
        write_encoding(bundle, encoding; source_sha, revision, command, source_url, dirty)
        for (file, content) in outputs
            write(joinpath(bundle, file), content)
        end
        results = [Dict("minsup" => run.minsup, "min_count" => run.min_count,
            "itemsets" => length(run.patterns), "elapsed_seconds" => run.elapsed, "status" => "ok",
            "pattern_bytes" => filesize(joinpath(bundle, "patterns-$(run.minsup).txt"))) for run in runs]
        hashes = Dict(file => open(io -> bytes2hex(sha256(io)), joinpath(bundle, file)) for file in readdir(bundle))
        manifest = Dict("variant" => "baseline", "git_revision" => revision, "git_dirty" => dirty,
            "command" => command, "source_sha256" => source_sha, "julia_version" => string(VERSION),
            "cpu_model" => first(Sys.cpu_info()).model, "threads" => Threads.nthreads(),
            "timing_boundary" => "mine call only, after one untimed warm-up at first threshold",
            "resource_limits" => "no explicit process limit or pattern cap", "source_hashes" => source_hashes,
            "runs" => results, "artifact_sha256" => hashes)
        open(io -> TOML.print(io, manifest; sorted=true), joinpath(bundle, "mining_manifest.toml"), "w")
        mv(bundle, output)
    end
    dir
end
