using ItemsetMining
const ROOT = dirname(dirname(@__DIR__))
include(joinpath(ROOT, "experiments", "Experiments.jl"))
include(joinpath(@__DIR__, "MarketBasket.jl"))
using .Experiments: load_manifest, prepare_dataset, dataset_stats, mean_width

const USAGE = """
Usage:
  julia --project=. applications/market_basket/prepare.jl [OUT_DIR]
  julia --project=. applications/market_basket/prepare.jl -h

Download and verify Online Retail II into data/raw/, clean it into one basket
per invoice, and write baskets.txt, items.tsv, and cleaning.tsv to OUT_DIR,
by default data/raw/market_basket/.
"""

function main(args)
    if MarketBasket.is_help(args)
        println(USAGE)
        return 0
    end
    raw_dir = joinpath(ROOT, "data", "raw")
    out = MarketBasket.output_folder(args, joinpath(raw_dir, "market_basket"), USAGE)
    entry = load_manifest(joinpath(raw_dir, "manifest.toml"))["online_retail_ii"]
    csv = prepare_dataset(entry, raw_dir)
    basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(csv))
    MarketBasket.write_market_basket(out, basket)

    println("step\trows_removed\trows\tinvoices")
    for s in basket.steps
        println(s.name, '\t', s.removed, '\t', s.rows, '\t', s.invoices)
    end
    stats = dataset_stats(basket.transactions)
    println("\ntransactions=", stats.transactions, " items=", stats.items,
            " mean_width=", round(mean_width(stats); digits=2), " max_width=", stats.max_width,
            " input_sha256=", entry.sha256)
    println("wrote ", out)
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
