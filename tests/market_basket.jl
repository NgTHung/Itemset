using Random: Xoshiro, shuffle

const RECEIPTS_PATH = joinpath(TOY_DIR, RECEIPT_CASE.file)
const RECEIPT_HEADER = "Invoice,StockCode,Description,Quantity,InvoiceDate,Price,Customer ID,Country"

@testset "Market basket data" begin
    @testset "Read receipts" begin
        lines = MarketBasket.read_receipts(RECEIPTS_PATH)
        @test length(lines) == 14
        @test lines[6].description == "ALARM CLOCK BAKELIKE PINK, LARGE"
        @test lines[14].description == "JUMBO BAG \"RED\" RETROSPOT"
        @test lines[5].customer == "" && lines[5].stock_code == "85123a"
        @test lines[11].price == -1000.0 && lines[7].quantity == -3
        bad(text) = MarketBasket.read_receipts(IOBuffer(text))
        @test_throws ArgumentError bad("Invoice,StockCode\n")
        err = try
            bad(RECEIPT_HEADER * "\n1001,85123A,X,6,2010-12-01 08:26:00,2.55,,UK\n1001,85123A,X,six,2010-12-01 08:26:00,2.55,,UK\n")
        catch e
            e
        end
        @test err isa ArgumentError && occursin("line 3", err.msg)
        @test_throws ArgumentError bad(RECEIPT_HEADER * "\n1001,85123A,X,6,2010-12-01 08:26:00,2.55,UK\n")
        @test_throws ArgumentError bad(RECEIPT_HEADER * "\n1001,85123A,\"X,6,2010-12-01 08:26:00,2.55,,UK\n")
    end

    @testset "Invoice dates keep the sortable layout" begin
        row(date) = RECEIPT_HEADER * "\n1001,85123A,X,6,$date,2.55,,UK\n"
        ok = MarketBasket.read_receipts(IOBuffer(row("2010-12-01 08:26:00")))
        @test only(ok).invoice_date == "2010-12-01 08:26:00"
        # Other layouts would still read, but the year split compares dates as text.
        for date in ("12/1/2010 8:26", "2010-12-01", "2010-12-01T08:26:00", "2010-13-01 08:26:00",
                     "2010-12-32 08:26:00", "2010-12-01 24:00:00", "2010-12-01 08:60:00", "")
            err = try
                MarketBasket.read_receipts(IOBuffer(row(date)))
            catch e
                e
            end
            @test err isa ArgumentError && occursin("line 2", err.msg) && occursin(repr(date), err.msg)
        end
        basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(RECEIPTS_PATH))
        for cutoff in ("12/2/2010", "2010-12", "2010-12-02 8:00", "yesterday")
            @test_throws ArgumentError MarketBasket.split_by_date(basket, cutoff)
        end
    end

    @testset "TSV writer validates before opening the file" begin
        mktempdir() do dir
            path = joinpath(dir, "out.tsv")
            MarketBasket.write_tsv(path, ("id", "name"), [(1, "tea"), (2, "milk")])
            @test read(path, String) == "id\tname\n1\ttea\n2\tmilk\n"
            @test MarketBasket.write_tsv(path, ("id",), Tuple{Int}[]) === nothing
            @test read(path, String) == "id\n"
            write(path, "keep\n")
            for (header, rows, where_) in (
                    (("id", "name"), [(1, "tea"), (2, "mi\tlk")], "row 2, column name"),
                    (("id", "name"), [(1, "te\na")], "row 1, column name"),
                    (("id", "name"), [(1, "te\ra")], "row 1, column name"),
                    (("id", "na\tme"), [(1, "tea")], "header"),
                    (("id", "name"), [(1, "tea"), (2,)], "row 2"))
                err = try
                    MarketBasket.write_tsv(path, header, rows)
                catch e
                    e
                end
                @test err isa ArgumentError && occursin(where_, err.msg)
                @test read(path, String) == "keep\n"
            end
        end
    end

    @testset "Clean receipts step by step" begin
        kept, steps = MarketBasket.clean_receipts(MarketBasket.read_receipts(RECEIPTS_PATH))
        @test [(s.name, s.removed, s.rows, s.invoices) for s in steps] ==
              [(s.name, s.removed, s.rows, s.invoices) for s in RECEIPT_CASE.steps]
        @test length(kept) == last(RECEIPT_CASE.steps).rows
        @test MarketBasket.is_non_product("POST") && MarketBasket.is_non_product("GIFT_0001_20")
        @test !MarketBasket.is_non_product("DCGS0058") && !MarketBasket.is_non_product("85123A")
    end

    @testset "Baskets and reversible mapping" begin
        basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(RECEIPTS_PATH))
        @test basket.invoices == RECEIPT_CASE.invoices
        @test basket.dates == RECEIPT_CASE.dates
        @test basket.codes == RECEIPT_CASE.codes
        # 22728 has two descriptions once each; the tie goes to the smaller string.
        @test basket.descriptions == RECEIPT_CASE.descriptions
        @test basket.transactions == RECEIPT_CASE.transactions
        @test decode_itemset(basket.codes, (2, 4)) == ["71053", "85123A"]
        @test Experiments.dataset_stats(basket.transactions).total_items == 7
    end

    @testset "Row order does not change the encoding" begin
        lines = MarketBasket.read_receipts(RECEIPTS_PATH)
        shuffled = shuffle(Xoshiro(DEFAULT_SEED), lines)
        @test shuffled != lines
        a = MarketBasket.prepare_baskets(lines)
        b = MarketBasket.prepare_baskets(shuffled)
        @test (a.invoices, a.dates, a.codes, a.descriptions, a.transactions) ==
              (b.invoices, b.dates, b.codes, b.descriptions, b.transactions)
    end

    @testset "Write baskets, items, and cleaning report" begin
        basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(RECEIPTS_PATH))
        mktempdir() do dir
            MarketBasket.write_market_basket(dir, basket)
            @test read_transactions(joinpath(dir, "baskets.txt")) == basket.transactions
            @test startswith(read(joinpath(dir, "baskets.txt"), String), "@CONVERTED_FROM_TEXT\n@ITEM=1=22728\n")
            @test readlines(joinpath(dir, "items.tsv")) == [
                "id\tstock_code\tdescription\tbaskets",
                "1\t22728\tALARM CLOCK BAKELIKE PINK\t2",
                "2\t71053\tWHITE METAL LANTERN\t2",
                "3\t85099B\tJUMBO BAG \"RED\" RETROSPOT\t1",
                "4\t85123A\tWHITE HANGING HEART T-LIGHT HOLDER\t2"]
            cleaning = readlines(joinpath(dir, "cleaning.tsv"))
            @test first(cleaning) == "step\trows_removed\trows\tinvoices"
            @test last(cleaning) == "non-product codes\t2\t7\t3"
        end
        # A bad label writes nothing: the three files are checked before any is opened.
        mktempdir() do dir
            tabbed = merge(basket, (; descriptions=["ok", "bad\tname", "ok", "ok"]))
            @test_throws ArgumentError MarketBasket.write_market_basket(dir, tabbed)
            @test isempty(readdir(dir))
            coded = merge(basket, (; codes=["22728", "7105\n3", "85099B", "85123A"]))
            @test_throws ArgumentError MarketBasket.write_market_basket(dir, coded)
            @test isempty(readdir(dir))
        end
    end
end
