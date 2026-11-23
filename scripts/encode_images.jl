using ItemsetMining
using SHA

include(joinpath(dirname(@__DIR__), "applications", "image_patterns", "SemeionPilot.jl"))
include(joinpath(dirname(@__DIR__), "experiments", "Experiments.jl"))
using .SemeionPilot: median_width

const VOCABULARY_SIZE = SemeionPilot.EncodingSettings().vocabulary_size

semeion_entry() = Experiments.load_manifest(joinpath(dirname(@__DIR__), "data", "raw", "manifest.toml"))["semeion"]

function prepare_encoding_command(args; entry=semeion_entry(), fetch=Experiments.Downloads.download,
                                  vocabulary_size::Int=VOCABULARY_SIZE, allow_minsup=false)
    usage = "INPUT OUTPUT_DIR [--vocabulary-size K]"
    allow_minsup && (usage *= " [--minsup FRACTIONS]")
    length(args) >= 2 && iseven(length(args)) || throw(ArgumentError("expected $usage, got $args"))
    input, output = args[1:2]
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
        elseif allow_minsup && option == "--minsup"
            levels = Tuple(parse.(Float64, split(value, ',')))
            allunique(levels) || throw(ArgumentError("duplicate support levels: $value"))
            foreach(level -> support_threshold(level, 1), levels)
        else
            throw(ArgumentError("unknown option: $option"))
        end
    end
    ispath(output) && throw(ArgumentError("output path already exists: $output"))
    basename(input) == entry.file || throw(ArgumentError("input must be named $(entry.file): $input"))
    mkpath(dirname(abspath(input)))
    input = Experiments.prepare_dataset(entry, dirname(abspath(input)); fetch)
    settings = SemeionPilot.EncodingSettings(; vocabulary_size)
    encoding = SemeionPilot.prepare_encoding(SemeionPilot.read_semeion(input); settings)
    (; input, output, encoding, entry, levels)
end

function command_provenance(args; script="scripts/encode_images.jl")
    root = dirname(@__DIR__)
    revision = ispath(joinpath(root, ".git")) ? readchomp(`git -C $root rev-parse HEAD`) : "unavailable"
    dirty = revision == "unavailable" || !isempty(readchomp(`git -C $root status --porcelain --untracked-files=no`))
    command = ["julia", "--startup-file=no", "--project=.", script, args...]
    (; revision, dirty, command)
end

function write_command_encoding(prepared, args; script="scripts/encode_images.jl")
    metadata = command_provenance(args; script)
    SemeionPilot.write_encoding(prepared.output, prepared.encoding;
        source_sha=prepared.entry.sha256, source_url=first(prepared.entry.sources).url,
        metadata...)
    print(read(joinpath(prepared.output, "summary.txt"), String))
    prepared.output
end

"""
    encoding_main(args; entry=semeion_entry(), fetch=Downloads.download, vocabulary_size=24)

Prepare the verified Semeion input and write encoding artifacts into a fresh output
directory. Arguments are INPUT OUTPUT_DIR with an optional --vocabulary-size K.
"""
function encoding_main(args; kwargs...)
    prepared = prepare_encoding_command(args; kwargs...)
    write_command_encoding(prepared, args)
end

if abspath(PROGRAM_FILE) == @__FILE__
    encoding_main(ARGS)
end
