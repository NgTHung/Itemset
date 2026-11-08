include(joinpath(@__DIR__, "encode_images.jl"))

"""
    mining_main(args; entry=semeion_entry(), fetch=Downloads.download, vocabulary_size=24)

Write complete baseline maps and traceable matching/nonmatching image evidence
for Semeion. `args` holds INPUT and a fresh OUTPUT_DIR, optionally followed by
`--vocabulary-size K` and `--minsup FRACTIONS` (comma separated).
"""
function mining_main(args; vocabulary_size::Int=VOCABULARY_SIZE, kwargs...)
    length(args) >= 2 && iseven(length(args)) ||
        throw(ArgumentError("expected INPUT OUTPUT_DIR [--vocabulary-size K] [--minsup FRACTIONS]"))
    levels = SemeionPilot.MINING_LEVELS
    seen = Set{String}()
    for i in 3:2:length(args)
        option, value = args[i], args[i + 1]
        option in seen && throw(ArgumentError("repeated option: $option"))
        push!(seen, option)
        if option == "--vocabulary-size"
            k = tryparse(Int, value)
            k !== nothing && k > 0 || throw(ArgumentError("invalid vocabulary size: $value"))
            vocabulary_size = k
        elseif option == "--minsup"
            levels = Tuple(parse.(Float64, split(value, ',')))
            allunique(levels) || throw(ArgumentError("duplicate support levels: $value"))
            foreach(level -> support_threshold(level, 1), levels)
        else
            throw(ArgumentError("unknown option: $option"))
        end
    end
    prepared = prepare_encoding_command(args[1:2]; vocabulary_size, kwargs...)
    metadata = command_provenance(args; script="scripts/mine_image_patterns.jl")
    root = dirname(@__DIR__)
    sources = Dict(replace(relpath(joinpath(dir, file), root), '\\' => '/') =>
                   Experiments.file_sha256(joinpath(dir, file))
                   for (dir, _, files) in walkdir(joinpath(root, "src")) for file in files if endswith(file, ".jl"))
    SemeionPilot.write_mining_run(prepared.output, prepared.encoding;
        source_sha=prepared.entry.sha256, source_url=first(prepared.entry.sources).url,
        source_hashes=sources, levels, metadata...)
    print(read(joinpath(prepared.output, "thresholds.tsv"), String))
    prepared.output
end

if abspath(PROGRAM_FILE) == @__FILE__
    mining_main(ARGS)
end
