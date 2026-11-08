const RECEIPTS_PATH = joinpath(TOY_DIR, RECEIPT_CASE.file)
const RECEIPT_HEADER = "Invoice,StockCode,Description,Quantity,InvoiceDate,Price,Customer ID,Country"

@testset "Market basket data" begin
    @testset "Read receipts" begin
        lines = MarketBasket.read_receipts(RECEIPTS_PATH)
        @test length(lines) == 14
        @test lines[6].description == "ALARM CLOCK BAKELIKE PINK, LARGE"
        @test lines[14].description == "JUMBO BAG \"RED\" RETROSPOT"
        bad(text) = MarketBasket.read_receipts(IOBuffer(text))
        @test_throws "line 3" bad(RECEIPT_HEADER * "\n1001,85123A,X,6,2010-12-01 08:26:00,2.55,,UK\n1001,85123A,X,six,2010-12-01 08:26:00,2.55,,UK\n")
        @test_throws ArgumentError bad(RECEIPT_HEADER * "\n1001,85123A,X,6,2010-12-01 08:26:00,2.55,UK\n")
        # The year split compares dates as text, so any other layout would split wrongly.
        for date in ("12/1/2010 8:26", "2010-12-01", "2010-13-01 08:26:00")
            @test_throws "line 2" bad(RECEIPT_HEADER * "\n1001,85123A,X,6,$date,2.55,,UK\n")
        end
    end

    @testset "Clean receipts step by step" begin
        kept, steps = MarketBasket.clean_receipts(MarketBasket.read_receipts(RECEIPTS_PATH))
        @test [(s.name, s.removed, s.rows, s.invoices) for s in steps] ==
              [(s.name, s.removed, s.rows, s.invoices) for s in RECEIPT_CASE.steps]
        @test length(kept) == last(RECEIPT_CASE.steps).rows
    end

    @testset "Baskets and reversible mapping" begin
        basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(RECEIPTS_PATH))
        @test basket.invoices == RECEIPT_CASE.invoices
        @test basket.dates == RECEIPT_CASE.dates
        @test basket.codes == RECEIPT_CASE.codes
        # 22728 has two descriptions once each; the tie goes to the smaller string.
        @test basket.descriptions == RECEIPT_CASE.descriptions
        @test basket.transactions == RECEIPT_CASE.transactions
        # The cutoff belongs to the later part, so a whole day never splits.
        early, late = MarketBasket.split_by_date(basket, "2010-12-01 09:00:00")
        @test early == RECEIPT_CASE.transactions[1:1] && late == RECEIPT_CASE.transactions[2:3]
        @test_throws ArgumentError MarketBasket.split_by_date(basket, "12/2/2010")
    end

    @testset "Write baskets, items, and cleaning report" begin
        basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(RECEIPTS_PATH))
        mktempdir() do dir
            MarketBasket.write_market_basket(dir, basket)
            @test read_transactions(joinpath(dir, "baskets.txt")) == basket.transactions
            @test readlines(joinpath(dir, "items.tsv"))[2] == "1\t22728\tALARM CLOCK BAKELIKE PINK\t2"
            @test last(readlines(joinpath(dir, "cleaning.tsv"))) == "non-product codes\t2\t7\t3"
        end
        # A bad label writes nothing: the three files are checked before any is opened.
        mktempdir() do dir
            tabbed = merge(basket, (; descriptions=["ok", "bad\tname", "ok", "ok"]))
            @test_throws ArgumentError MarketBasket.write_market_basket(dir, tabbed)
            @test isempty(readdir(dir))
        end
    end
end
