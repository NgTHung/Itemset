using ItemsetMining

# The command line lives in the package, so a cold run uses its precompiled code.
if abspath(PROGRAM_FILE) == @__FILE__
    exit(ItemsetMining.cli_exit_code(ARGS))
end
