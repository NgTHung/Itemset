"""A measure as text with four decimals, the precision of every table and report figure."""
format_measure(x::Real) = @sprintf("%.4f", Float64(x))

"""
    check_tsv(header, rows)

Throw `ArgumentError` naming the row and column of the first field that holds a
tab, carriage return, or line break, or the first row whose field count differs
from the header. A tab would shift a column and a line break would split a row,
so a product name from the raw data can never corrupt a table.
"""
function check_tsv(header, rows)
    unsafe(field) = occursin(r"[\t\r\n]", string(field))
    for (column, name) in enumerate(header)
        unsafe(name) && throw(ArgumentError("header column $column contains a tab or line break"))
    end
    for (index, row) in enumerate(rows)
        length(row) == length(header) ||
            throw(ArgumentError("row $index has $(length(row)) fields, expected $(length(header))"))
        for (column, field) in enumerate(row)
            unsafe(field) &&
                throw(ArgumentError("row $index, column $(header[column]): $(repr(string(field))) contains a tab or line break"))
        end
    end
    return nothing
end

"""
    write_tsv(path, header, rows)

Write `header` and `rows` as tab-separated text, converting each field with
`string`. Runs `check_tsv` before opening `path`, so an invalid table never
truncates an existing file or leaves partial output.
"""
function write_tsv(path::AbstractString, header, rows)
    rows = collect(rows)
    check_tsv(header, rows)
    open(path, "w") do io
        println(io, join(header, '\t'))
        for row in rows
            println(io, join(row, '\t'))
        end
    end
    return nothing
end
