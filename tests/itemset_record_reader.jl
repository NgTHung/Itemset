# The regex line reader that the byte reader replaces, kept as the reference.
function line_record_reader(io::IO)
    records = ItemsetMining.ItemsetRecord[]
    for (line_number, line) in enumerate(eachline(io))
        value = strip(line)
        ItemsetMining.is_spmf_metadata(value) && !occursin("#SUP:", value) && continue
        parts = match(r"^(.*?)\s*#SUP:\s*(\S*)$", value)
        parts === nothing &&
            throw(ArgumentError("line $line_number: expected 'items #SUP: count', got $(repr(value))"))
        items = ItemsetMining.parse_item_ids(parts[1], line_number)
        isempty(items) && throw(ArgumentError("line $line_number: empty itemset"))
        allunique(items) || throw(ArgumentError("line $line_number: repeated item ID in $(repr(value))"))
        support = tryparse(Int, parts[2])
        (support === nothing || support < 1) &&
            throw(ArgumentError("line $line_number: invalid support $(repr(parts[2]))"))
        push!(records, (itemset=Tuple(sort!(items)), support=support, line=line_number))
    end
    return records
end

@testset "Byte itemset record reader" begin
    cases = ["", "\n", "1 #SUP: 2", "1 2 #SUP: 3\r\n2 #SUP: 1\r\n", "  3 1 #SUP:  4  \n", "1 2#SUP:3\n", "1\t#SUP:\t5\n",
             "% c\n@x\n# c\n\n1 #SUP: 1\n", "#SUP: 1\n", "  #SUP: 1\n", "1 #SUP:\n", "1 #SUP: 0\n", "1 #SUP: -1\n",
             "1 #SUP: +2\n", "1 #SUP: 2 3\n", "1 #SUP: 2 #SUP: 3\n", "1 #SUP: 2 #SUP:3\n", "1 #SUP: x\n", "x #SUP: 1\n",
             "1 1 #SUP: 2\n", "2 1 2 #SUP: 2\n", "#x 1 #SUP: 2\n", "1 2\n", "1 #SUP: 9223372036854775807\n",
             "1 #SUP: 9223372036854775808\n", "9223372036854775807 #SUP: 1\n", "007 #SUP: 007\n", "1 #SUP: 2\n",
             "１ #SUP: 1\n", "1 #SUP: \xff\n", "1 #sup: 2\n", "1 #SUP 2\n"]
    for text in cases
        @test outcome(read_itemset_records, text) == outcome(line_record_reader, text)
    end
    for path in filter(endswith(".expected.txt"), readdir(TOY_DIR; join=true))
        text = read(path, String)
        @test outcome(read_itemset_records, text) == outcome(line_record_reader, text)
    end
end
