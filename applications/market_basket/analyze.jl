using ItemsetMining
using TOML: TOML
const ROOT = dirname(dirname(@__DIR__))
include(joinpath(ROOT, "experiments", "Experiments.jl"))
include(joinpath(@__DIR__, "MarketBasket.jl"))
using .Experiments: load_manifest, prepare_dataset, code_revision
using .MarketBasket: association_rules, top_rules, top_rule_groups, group_ranks, group_key, rule_labels,
                     write_rules, write_tsv, format_measure, split_by_date, measure_rule, confidence, lift,
                     AssociationRule

const USAGE = """
Usage:
  julia --project=. applications/market_basket/analyze.jl [OUT_DIR]
  julia --project=. applications/market_basket/analyze.jl -h

Mine the cleaned Online Retail II baskets with Eclat, derive association rules,
and write the top-10 tables and robustness checks to OUT_DIR, by default
results/raw/market_basket/. Takes a few minutes, mostly mining.
"""

# Each reported pattern rests on at least 396 of 39,516 receipts.
const MINSUP = 0.01
# A rule must hold in more than half of the baskets that contain its antecedent.
const MINCONF = 0.5
const TOP = 10
const MINSUP_GRID = (0.0075, 0.01, 0.015)
const MINCONF_GRID = (0.4, 0.5, 0.6)
# A lower threshold admits rarer patterns, whose high lift rests on fewer receipts.
const RARE_MINSUP = 0.005
# The receipts span two years; the second starts on this date.
const YEAR_CUTOFF = "2010-12-01"
# Wholesale orders above the 99th percentile of basket width could create co-occurrence on their own.
const LARGE_BASKET_QUANTILE = 0.99

"""Mine `transactions` once per threshold, so several minconf values reuse one map."""
function mined(cache::Dict{Float64,SupportMap}, transactions, minsup::Float64)
    get!(cache, minsup) do
        seconds = @elapsed patterns = mine(transactions; minsup)
        println(stderr, "mined at minsup $minsup in $(round(seconds; digits=1)) s")
        patterns
    end
end

"""Support, confidence, and lift of `rule` recounted in `transactions`; blank where undefined."""
function recounted(rule::AssociationRule, transactions)
    r = measure_rule(rule, transactions)
    defined = r.antecedent_support > 0 && r.consequent_support > 0
    return (string(r.support), defined ? format_measure(confidence(r)) : "", defined ? format_measure(lift(r)) : "")
end

function main(args)
    if MarketBasket.is_help(args)
        println(USAGE)
        return 0
    end
    out = MarketBasket.output_folder(args, joinpath(ROOT, "results", "raw", "market_basket"), USAGE)
    raw_dir = joinpath(ROOT, "data", "raw")
    entry = load_manifest(joinpath(raw_dir, "manifest.toml"))["online_retail_ii"]
    basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(prepare_dataset(entry, raw_dir)))
    transactions = basket.transactions
    n = length(transactions)
    labels = basket.descriptions
    # Every table prints these labels, so one check before the first write keeps a bad
    # label from leaving a half-written results folder.
    MarketBasket.check_tsv(("description",), [(label,) for label in labels])
    mkpath(out)
    cache = Dict{Float64,SupportMap}()

    patterns = mined(cache, transactions, MINSUP)
    rules = association_rules(patterns, n; minconf=MINCONF)
    top = top_rules(rules, TOP)
    groups = top_rule_groups(rules, TOP)
    write_rules(joinpath(out, "rules.tsv"), rules, labels)
    write_rules(joinpath(out, "top_rules.tsv"), top.rules, labels)
    write_rules(joinpath(out, "top_groups.tsv"), groups, labels)

    # Thresholds never change a rule's measures; they decide whether it passes and
    # which rules it is ranked against. A group is present while any of its splits
    # passes, and its rank is that of its best passing split, not of the base rule.
    sensitivity = map(Iterators.product(MINSUP_GRID, MINCONF_GRID)) do (minsup, minconf)
        cell_patterns = mined(cache, transactions, minsup)
        cell = association_rules(cell_patterns, n; minconf)
        by_group = group_ranks(cell)
        top_keys = Set((r.antecedent, r.consequent) for r in top_rules(cell, TOP).rules)
        ranks = [get(by_group, group_key(g), "-") for g in groups]
        (minsup, support_threshold(minsup, n), minconf, length(cell_patterns), length(cell),
         count(r -> (r.antecedent, r.consequent) in top_keys, top.rules),
         count(!=("-"), ranks), join(ranks, ' '))
    end
    write_tsv(joinpath(out, "sensitivity.tsv"),
        ("minsup", "minsup_count", "minconf", "itemsets", "rules", "top_rules_in_top10",
         "top_groups_present", "group_ranks"), vec(sensitivity))

    year1, year2 = split_by_date(basket, YEAR_CUTOFF)
    cap = sort(length.(transactions))[ceil(Int, LARGE_BASKET_QUANTILE * n)]
    small = filter(t -> length(t) <= cap, transactions)
    write_tsv(joinpath(out, "stability.tsv"),
        ("group_rank", "antecedent", "consequent", "support", "confidence", "lift",
         "support_year1", "confidence_year1", "lift_year1", "support_year2", "confidence_year2", "lift_year2",
         "support_small", "confidence_small", "lift_small"),
        [(i, rule_labels(g, labels)..., g.support, format_measure(confidence(g)), format_measure(lift(g)),
          recounted(g, year1)..., recounted(g, year2)..., recounted(g, small)...)
         for (i, g) in enumerate(groups)])

    base_groups = Set(group_key.(groups))
    rare = top_rule_groups(association_rules(mined(cache, transactions, RARE_MINSUP), n; minconf=MINCONF), TOP)
    write_tsv(joinpath(out, "rare_groups.tsv"),
        ("group_rank", "antecedent", "consequent", "support", "confidence", "lift", "in_base_groups",
         "support_year1", "confidence_year1", "lift_year1", "support_year2", "confidence_year2", "lift_year2"),
        [(i, rule_labels(g, labels)..., g.support, format_measure(confidence(g)), format_measure(lift(g)), group_key(g) in base_groups,
          recounted(g, year1)..., recounted(g, year2)...)
         for (i, g) in enumerate(rare)])

    summary = Dict{String,Any}(
        "input_sha256" => entry.sha256, "code_revision" => code_revision(ROOT),
        "julia_version" => string(VERSION), "transactions" => n, "items" => length(basket.codes),
        "minsup" => MINSUP, "minsup_count" => support_threshold(MINSUP, n), "minconf" => MINCONF,
        "itemsets" => length(patterns), "rules" => length(rules), "top" => TOP,
        "ties_beyond_top" => top.ties_beyond, "year_cutoff" => YEAR_CUTOFF,
        "transactions_year1" => length(year1), "transactions_year2" => length(year2),
        "large_basket_cap" => cap, "transactions_small" => length(small),
        "rare_minsup" => RARE_MINSUP, "rare_minsup_count" => support_threshold(RARE_MINSUP, n))
    open(io -> TOML.print(io, summary), joinpath(out, "summary.toml"), "w")

    println("Top $TOP rules by lift (minsup $MINSUP = $(support_threshold(MINSUP, n)) baskets, ",
            "minconf $MINCONF, $(length(rules)) rules):")
    for (rank, r) in enumerate(top.rules)
        left, right = rule_labels(r, labels)
        println(rank, ". ", left, " => ", right, "  support=", r.support,
                " confidence=", format_measure(confidence(r)), " lift=", format_measure(lift(r)))
    end
    top.ties_beyond > 0 && println("$(top.ties_beyond) more rules share the lift of rule $TOP.")
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
