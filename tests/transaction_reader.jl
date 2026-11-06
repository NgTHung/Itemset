# The line-and-token reader that the byte reader replaces, kept as the reference.
function line_reader(io::IO)
    transactions = Vector{Vector{Int}}()
    for (line_number, line) in enumerate(eachline(io))
        value = strip(line)
        ItemsetMining.is_spmf_metadata(value) && continue
        push!(transactions, canonical_transaction(ItemsetMining.parse_item_ids(value, line_number)))
    end
    return transactions
end

# Either the same database or the same error message, so errors keep their line numbers.
outcome(reader, text) = try
    reader(IOBuffer(text))
catch error
    error isa ArgumentError || rethrow()
    sprint(showerror, error)
end

@testset "Byte transaction reader" begin
    cases = ["", "\n", "\n\n1\n", "1 2", "1 2\r\n3\r\n", "1\r2\n", "  # c\n1", "%x\n@y\n#z\n2 1 2\n",
             "1\t2  3\n", "1\v2\f3\n", "+5 007\n", "-0 1\n", "0x10\n", "1_000\n", "9223372036854775807\n",
             "9223372036854775808\n", "99999999999999999999\n", "123456789012345678 1\n", "1 -1\n", "1 x\n",
             "1\n2 -\n", "1 +\n", "1 2\n", " # c\n", "１\n", "1 2\n", "\xff\n"]
    for text in cases
        @test outcome(read_transactions, text) == outcome(line_reader, text)
    end
    rng = Xoshiro(DEFAULT_SEED)
    alphabet = collect("0129 \t\n\r-+#x")
    for _ in 1:2_000
        text = String(rand(rng, alphabet, rand(rng, 0:40)))
        @test outcome(read_transactions, text) == outcome(line_reader, text)
    end
    for path in filter(endswith(".txt"), readdir(TOY_DIR; join=true))
        text = read(path, String)
        @test outcome(read_transactions, text) == outcome(line_reader, text)
    end
    @test_throws "line 3" read_transactions(IOBuffer("1\n\n2 x\n"))
end

@testset "Canonical transactions are not copied" begin
    database = [[1, 2], Int[], [0, 5]]
    canonical = ItemsetMining.canonical_database(database)
    @test canonical == database
    @test all(canonical[i] === database[i] for i in eachindex(database))
    unsorted = [[2, 1], [3, 3]]
    @test ItemsetMining.canonical_database(unsorted) == [[1, 2], [3]]
    @test unsorted == [[2, 1], [3, 3]]
    @test_throws "transaction 1" ItemsetMining.canonical_database([[-1, 2]])
end
