include(joinpath(@__DIR__, "encode_images.jl"))

"""
    mining_main(args; entry=semeion_entry(), fetch=Downloads.download, vocabulary_size=24)

Write complete baseline maps and traceable matching/nonmatching image evidence
for the frozen Semeion encoding. `args` holds INPUT and a fresh OUTPUT_DIR.
"""
function mining_main(args; kwargs...)
    prepared = prepare_encoding_command(args; kwargs...)
    metadata = command_provenance(args; script="scripts/mine_image_patterns.jl")
    root = dirname(@__DIR__)
    sources = Dict(replace(relpath(joinpath(dir, file), root), '\\' => '/') =>
                   Experiments.file_sha256(joinpath(dir, file))
                   for (dir, _, files) in walkdir(joinpath(root, "src")) for file in files if endswith(file, ".jl"))
    SemeionPilot.write_mining_run(prepared.output, prepared.encoding;
        source_sha=prepared.entry.sha256, source_url=first(prepared.entry.sources).url,
        source_hashes=sources, metadata...)
    print(read(joinpath(prepared.output, "thresholds.tsv"), String))
    prepared.output
end

if abspath(PROGRAM_FILE) == @__FILE__
    mining_main(ARGS)
end
