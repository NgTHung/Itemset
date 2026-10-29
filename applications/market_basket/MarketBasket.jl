"""
Turn Online Retail II receipt lines into integer-ID baskets for `mine`. One
transaction is one invoice and one item is one product stock code. Every
cleaning step is counted, so the report can explain how each filter changes the
transaction and item counts. `rules.jl` derives association rules from the
mined baskets.
"""
module MarketBasket

using ItemsetMining
using Printf: @sprintf

const HEADER = "Invoice,StockCode,Description,Quantity,InvoiceDate,Price,Customer ID,Country"

"""
Stock codes that record a service or bookkeeping entry instead of merchandise.
They would pair with almost every basket, such as postage, and say nothing
about which products sell together.
"""
const NON_PRODUCT_CODES = Set([
    "POST", "DOT", "C2", "C3",       # postage and carriage
    "M", "D", "S", "B",              # manual entry, discount, samples, bad debt
    "BANK CHARGES", "AMAZONFEE", "CRUK",
    "ADJUST", "ADJUST2", "TEST001", "TEST002", "GIFT",
])

"""True for a normalized stock code that is not merchandise, including every gift voucher."""
is_non_product(code::AbstractString) = code in NON_PRODUCT_CODES || startswith(code, "GIFT_")

"""Upper case merges codes such as `85123a` and `85123A`, which name the same product."""
normalize_code(code::AbstractString) = uppercase(strip(code))

struct ReceiptLine
    invoice::String
    stock_code::String
    description::String
    quantity::Int
    invoice_date::String
    price::Float64
    customer::String
    country::String
end

fields(line::ReceiptLine) = ntuple(i -> getfield(line, i), fieldcount(ReceiptLine))

"""Split one CSV record. Quoted fields may hold commas and doubled quotes."""
function split_csv_line(line::AbstractString, line_number::Int)
    values = String[]
    value = IOBuffer()
    quoted = false
    i = firstindex(line)
    while i <= lastindex(line)
        c = line[i]
        if quoted && c == '"'
            next = nextind(line, i)
            if next <= lastindex(line) && line[next] == '"'
                print(value, '"')
                i = next
            else
                quoted = false
            end
        elseif quoted
            print(value, c)
        elseif c == '"'
            quoted = true
        elseif c == ','
            push!(values, String(take!(value)))
        else
            print(value, c)
        end
        i = nextind(line, i)
    end
    quoted && throw(ArgumentError("line $line_number: unterminated quoted field"))
    push!(values, String(take!(value)))
    return values
end

"""
    read_receipts(io_or_path) -> Vector{ReceiptLine}

Read the Online Retail II CSV. Throws `ArgumentError` for a different header,
and for a record with the wrong field count, an unterminated quote, or a
quantity or price that does not parse, naming the line number.
"""
function read_receipts(io::IO)
    header = readline(io)
    rstrip(header, '\r') == HEADER ||
        throw(ArgumentError("expected the Online Retail II header $(repr(HEADER)), got $(repr(header))"))
    lines = ReceiptLine[]
    for (offset, raw) in enumerate(eachline(io))
        line_number = offset + 1
        text = rstrip(raw, '\r')
        isempty(text) && continue
        v = split_csv_line(text, line_number)
        length(v) == 8 ||
            throw(ArgumentError("line $line_number: expected 8 fields, got $(length(v))"))
        quantity = tryparse(Int, v[4])
        quantity === nothing && throw(ArgumentError("line $line_number: quantity $(repr(v[4])) is not an integer"))
        price = tryparse(Float64, v[6])
        price === nothing && throw(ArgumentError("line $line_number: price $(repr(v[6])) is not a number"))
        push!(lines, ReceiptLine(v[1], v[2], v[3], quantity, v[5], price, v[7], v[8]))
    end
    return lines
end

read_receipts(path::AbstractString) = open(read_receipts, path)

"""One cleaning step: rows it removed, and the rows and invoices left after it."""
struct CleaningStep
    name::String
    removed::Int
    rows::Int
    invoices::Int
end

"""
    clean_receipts(lines) -> (kept, steps)

Remove, in order: exact duplicate rows, cancellation invoices (`C` prefix,
returns), bad-debt adjustment invoices (`A` prefix), rows with quantity or price
of zero or less, and non-product codes. Rows without a customer ID stay, because
a receipt is a basket whoever paid. `steps` starts with the raw counts.
"""
function clean_receipts(lines::AbstractVector{ReceiptLine})
    kept = collect(lines)
    steps = CleaningStep[]
    record!(name, removed) =
        push!(steps, CleaningStep(name, removed, length(kept), length(unique(l.invoice for l in kept))))
    record!("raw", 0)
    before = length(kept)
    # UCI publishes two yearly sheets that both hold 1-9 December 2010, so
    # those receipts appear twice unless exact copies are dropped.
    kept = unique(fields, kept)
    record!("duplicate rows", before - length(kept))
    for (name, keep) in (
            "cancelled invoices" => l -> !startswith(l.invoice, 'C'),
            "adjustment invoices" => l -> !startswith(l.invoice, 'A'),
            "nonpositive quantity" => l -> l.quantity > 0,
            "nonpositive price" => l -> l.price > 0,
            "non-product codes" => l -> !is_non_product(normalize_code(l.stock_code)))
        before = length(kept)
        filter!(keep, kept)
        record!(name, before - length(kept))
    end
    return kept, steps
end

"""
Most frequent nonblank description of each code, the smaller string on a tie,
so the label never depends on row order. A code without any description keeps
its code as the description.
"""
function item_descriptions(kept::AbstractVector{ReceiptLine}, codes::AbstractVector{String})
    counts = Dict{String,Dict{String,Int}}()
    for line in kept
        description = strip(line.description)
        isempty(description) && continue
        tally = get!(counts, normalize_code(line.stock_code), Dict{String,Int}())
        tally[description] = get(tally, description, 0) + 1
    end
    return map(codes) do code
        tally = get(counts, code, nothing)
        tally === nothing && return code
        best = maximum(n for n in values(tally))
        return minimum(d for (d, n) in tally if n == best)
    end
end

function invoice_number(invoice::AbstractString)
    number = tryparse(Int, invoice)
    number === nothing && throw(ArgumentError("invoice $(repr(invoice)) survived cleaning but is not a sale number"))
    return number
end

"""
    prepare_baskets(lines) -> NamedTuple

Clean `lines` and group them into one basket per invoice, ordered by invoice
number. IDs come from `encode_transactions` over stock codes, so `codes[id]`
and `descriptions[id]` reverse the mapping and row order never changes it.
`dates[i]` is the earliest `InvoiceDate` text of `invoices[i]`; the ISO layout
sorts as text, so the earliest is well defined.
"""
function prepare_baskets(lines::AbstractVector{ReceiptLine})
    kept, steps = clean_receipts(lines)
    by_invoice = Dict{String,Vector{String}}()
    first_date = Dict{String,String}()
    for line in kept
        push!(get!(by_invoice, line.invoice, String[]), normalize_code(line.stock_code))
        first_date[line.invoice] = min(get(first_date, line.invoice, line.invoice_date), line.invoice_date)
    end
    invoices = sort!(collect(keys(by_invoice)); by=invoice_number)
    transactions, codes = encode_transactions([by_invoice[i] for i in invoices])
    codes = Vector{String}(codes)
    dates = [first_date[i] for i in invoices]
    return (; invoices, dates, codes, descriptions=item_descriptions(kept, codes), transactions, steps)
end

"""
    split_by_date(basket, cutoff) -> (before, from)

Split the transactions of `prepare_baskets` output at the date text `cutoff`:
`before` holds baskets dated earlier, `from` the rest, each in invoice order.
Mining each part separately shows whether a pattern holds in both periods.
"""
function split_by_date(basket, cutoff::AbstractString)
    early = basket.dates .< cutoff
    return basket.transactions[early], basket.transactions[.!early]
end

"""
    write_market_basket(dir, basket)

Write `baskets.txt` (SPMF, with `@ITEM` stock-code labels), `items.tsv`, and
`cleaning.tsv` into `dir`. Validates every description before writing, so a tab
or line break never shifts a column, and throws `ArgumentError` naming the code.
"""
function write_market_basket(dir::AbstractString, basket)
    for (code, description) in zip(basket.codes, basket.descriptions)
        occursin(r"[\t\r\n]", description) &&
            throw(ArgumentError("description of $code contains a tab or line break"))
    end
    mkpath(dir)
    write_transactions(joinpath(dir, "baskets.txt"), basket.transactions; labels=basket.codes)
    baskets_per_item = zeros(Int, length(basket.codes))
    for transaction in basket.transactions, id in transaction
        baskets_per_item[id] += 1
    end
    open(joinpath(dir, "items.tsv"), "w") do io
        println(io, "id\tstock_code\tdescription\tbaskets")
        for (id, code) in enumerate(basket.codes)
            println(io, id, '\t', code, '\t', basket.descriptions[id], '\t', baskets_per_item[id])
        end
    end
    open(joinpath(dir, "cleaning.tsv"), "w") do io
        println(io, "step\trows_removed\trows\tinvoices")
        for s in basket.steps
            println(io, s.name, '\t', s.removed, '\t', s.rows, '\t', s.invoices)
        end
    end
    return nothing
end

include("rules.jl")

end
