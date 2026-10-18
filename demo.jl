using ItemsetMining

const USAGE = """
Usage:
  julia --project=. demo.jl --check-input PATH
  julia --project=. demo.jl --minsup FRACTION --output PATH [--variant baseline|optimized] INPUT
  julia --project=. demo.jl --min-count COUNT --output PATH [--variant baseline|optimized] INPUT

Setup supports --help and --check-input now. Mining becomes available with DAT-8.
--minsup uses a fraction in (0,1]; --min-count uses an integer >= 1.
"""

function main(args)
    if isempty(args) || args == ["--help"]
        println(USAGE)
        return 0
    end
    if first(args) == "--check-input"
        length(args) == 2 || throw(ArgumentError("--check-input needs exactly one path"))
        transactions = read_transactions(args[2])
        items = Set{Int}()
        foreach(t -> union!(items, t), transactions)
        println("transactions=$(length(transactions)) items=$(length(items))")
        return 0
    end
    threshold = nothing
    variant = :baseline
    output = nothing
    input = nothing
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg in ("--minsup", "--min-count", "--variant", "--output")
            index < length(args) || throw(ArgumentError("$arg needs a value"))
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
    patterns = mine(read_transactions(input); minsup=threshold, variant=variant)
    write_itemsets(output, patterns)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    code = try
        main(ARGS)
    catch exception
        println(stderr, "ERROR: ", sprint(showerror, exception))
        1
    end
    exit(code)
end
