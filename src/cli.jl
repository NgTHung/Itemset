const CLI_USAGE = """
Usage:
  julia --project=. demo.jl --check-input PATH
  julia --project=. demo.jl --minsup FRACTION --output PATH [--variant baseline|optimized] INPUT
  julia --project=. demo.jl --min-count COUNT --output PATH [--variant baseline|optimized] INPUT

--check-input prints transaction and distinct-item counts.
--minsup uses a fraction in (0,1]; --min-count uses an integer >= 1.
"""

"""
    cli_main(args::Vector{String}, out::IO=stdout) -> Int

Run the `demo.jl` command line and return 0. The code lives in the package, not
in the script, so the package image holds its native code and a cold run
compiles nothing. Throws `ArgumentError` for invalid arguments or input, and
leaves an existing output file untouched when it throws.
"""
function cli_main(args::Vector{String}, out::IO=stdout)
    if isempty(args) || args == ["--help"]
        println(out, CLI_USAGE)
        return 0
    end
    if first(args) == "--check-input"
        length(args) == 2 || throw(ArgumentError("--check-input needs exactly one path"))
        transactions = read_transactions(args[2])
        items = Set{Int}()
        foreach(t -> union!(items, t), transactions)
        println(out, "transactions=", length(transactions), " items=", length(items))
        return 0
    end
    threshold::Union{Nothing,Float64,Int} = nothing
    variant = :baseline
    output::Union{Nothing,String} = nothing
    input::Union{Nothing,String} = nothing
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg in ("--minsup", "--min-count", "--variant", "--output")
            # A missing value would otherwise shift every later argument, so `--output --variant`
            # would make "--variant" the output path instead of failing here.
            index < length(args) && !startswith(args[index + 1], "--") ||
                throw(ArgumentError("$arg needs a value"))
            value = args[index + 1]
            if arg in ("--minsup", "--min-count")
                threshold === nothing || throw(ArgumentError("choose exactly one support threshold"))
                threshold = arg == "--minsup" ? parse(Float64, value) : parse(Int, value)
            elseif arg == "--variant"
                variant = Symbol(value)
            else
                output = value
            end
            index += 2
        elseif startswith(arg, "--")
            throw(ArgumentError("unknown option $arg"))
        else
            input === nothing || throw(ArgumentError("only one input path is allowed"))
            input = arg
            index += 1
        end
    end
    input !== nothing && output !== nothing && threshold !== nothing ||
        throw(ArgumentError("input, --output, and a support threshold are required"))
    abspath(input) != abspath(output) || throw(ArgumentError("input and output must differ"))
    patterns = mine_packed(read_transactions(input); minsup=threshold, variant=variant)
    write_itemsets(output, patterns)
    return 0
end

"""
    cli_exit_code(args::Vector{String}) -> Int

Run `cli_main` and return the process exit code: 0 on success, or 1 after
printing `ERROR: ` and the message to stderr, so a script exits without a
stack trace.
"""
function cli_exit_code(args::Vector{String})
    try
        return cli_main(args)
    catch exception
        println(stderr, "ERROR: ", sprint(showerror, exception))
        return 1
    end
end
