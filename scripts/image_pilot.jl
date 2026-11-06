include(joinpath(@__DIR__, "mine_image_patterns.jl"))
const SUPPORT_LEVELS = SemeionPilot.MINING_LEVELS

main(args; kwargs...) = mining_main(args; kwargs...)

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
