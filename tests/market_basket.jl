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
            bad(RECEIPT_HEADER * "\n1001,85123A,X,6,2010-12-01,2.55,,UK\n1001,85123A,X,six,2010-12-01,2.55,,UK\n")
        catch e
            e
        end
        @test err isa ArgumentError && occursin("line 3", err.msg)
        @test_throws ArgumentError bad(RECEIPT_HEADER * "\n1001,85123A,X,6,2010-12-01,2.55,UK\n")
        @test_throws ArgumentError bad(RECEIPT_HEADER * "\n1001,85123A,\"X,6,2010-12-01,2.55,,UK\n")
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
        @test (a.invoices, a.codes, a.descriptions, a.transactions) ==
              (b.invoices, b.codes, b.descriptions, b.transactions)
    end

    @testset "Write baskets, items, and cleaning report" begin
        mktempdir() do dir
            basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(RECEIPTS_PATH))
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
    end
end
