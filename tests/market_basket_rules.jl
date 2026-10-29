using Random: Xoshiro

rule_pairs(rules) = [(r.antecedent, r.consequent) for r in rules]

"""Every rule with confidence at least `minconf`, counted directly from the transactions."""
function brute_force_rules(transactions, min_count, minconf::Rational)
    items = sort!(unique(Int[i for t in transactions for i in t]))
    count_of(set) = count(t -> all(in(t), set), transactions)
    rules = Set{Tuple}()
    for xmask in 1:(2^length(items) - 1), ymask in 1:(2^length(items) - 1)
        xmask & ymask == 0 || continue
        x = Tuple(items[b] for b in eachindex(items) if isodd(xmask >> (b - 1)))
        y = Tuple(items[b] for b in eachindex(items) if isodd(ymask >> (b - 1)))
        union = count_of((x..., y...))
        union >= min_count && union // count_of(x) >= minconf || continue
        push!(rules, (x, y, union, union // count_of(x),
                      union * length(transactions) // (count_of(x) * count_of(y))))
    end
    return rules
end

@testset "Market basket rules" begin
    grocery = only(c for c in MINING_CASES if c.name == "groceries").expected

    @testset "Grocery rules match the hand-derived measures" begin
        rules = MarketBasket.association_rules(grocery, 5; minconf=0.5)
        # Lift ties between mirrored rules break on confidence.
        @test rule_pairs(rules) == [((3,), (2,)), ((2,), (3,)), ((4,), (2,)), ((2,), (4,))]
        for r in rules
            expected = only(g for g in GROCERY_RULES if (g.antecedent, g.consequent) == (r.antecedent, r.consequent))
            @test r.support == expected.support
            @test MarketBasket.confidence(r) == expected.confidence
            @test MarketBasket.lift(r) == expected.lift
            @test MarketBasket.relative_support(r) == expected.support // 5
        end
    end

    @testset "minconf applies exactly to the rule" begin
        @test length(MarketBasket.association_rules(grocery, 5; minconf=0.6)) == 3
        @test length(MarketBasket.association_rules(grocery, 5; minconf=0.75)) == 2
        @test rule_pairs(MarketBasket.association_rules(grocery, 5; minconf=0.76)) == [((3,), (2,))]
        # Float64 0.1 is slightly above 1/10, so a naive comparison would drop
        # a rule whose confidence is exactly one tenth.
        @test !(1 // 10 >= 0.1)
        tenth = SupportMap((1,)=>10, (2,)=>1, (1, 2)=>1)
        @test rule_pairs(MarketBasket.association_rules(tenth, 10; minconf=0.1)) ==
              [((2,), (1,)), ((1,), (2,))]
    end

    @testset "Ties order by antecedent, then consequent" begin
        dense = only(c for c in MINING_CASES if c.name == "dense").expected
        rules = MarketBasket.association_rules(dense, 2; minconf=1.0)
        @test rule_pairs(rules) == [
            ((1,), (2,)), ((1,), (2, 3)), ((1,), (3,)), ((1, 2), (3,)), ((1, 3), (2,)),
            ((2,), (1,)), ((2,), (1, 3)), ((2,), (3,)), ((2, 3), (1,)),
            ((3,), (1,)), ((3,), (1, 2)), ((3,), (2,))]
        @test all(r -> MarketBasket.lift(r) == 1 && MarketBasket.confidence(r) == 1, rules)
        cut = MarketBasket.top_rules(rules, 10)
        @test cut.rules == rules[1:10] && cut.ties_beyond == 2
        mirrored = MarketBasket.top_rules(MarketBasket.association_rules(grocery, 5; minconf=0.5), 1)
        @test mirrored.ties_beyond == 1
        @test MarketBasket.top_rules(rules, 20).rules == rules
        @test MarketBasket.top_rules(rules, 20).ties_beyond == 0
    end

    @testset "One rule per product group" begin
        rules = MarketBasket.association_rules(grocery, 5; minconf=0.5)
        groups = MarketBasket.top_rule_groups(rules, 10)
        @test rule_pairs(groups) == [((3,), (2,)), ((4,), (2,))]
        @test rule_pairs(MarketBasket.top_rule_groups(rules, 1)) == [((3,), (2,))]
    end

    @testset "Rules agree with direct counting on random databases" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:60
            transactions = [sort!(unique(rand(rng, 1:6, rand(rng, 1:4)))) for _ in 1:rand(rng, 4:10)]
            n = length(transactions)
            patterns = mine(transactions; minsup=2)
            rules = MarketBasket.association_rules(patterns, n; minconf=0.3)
            measured = Set((r.antecedent, r.consequent, r.support, MarketBasket.confidence(r),
                            MarketBasket.lift(r)) for r in rules)
            @test measured == brute_force_rules(transactions, 2, 3 // 10)
            @test length(rules) == length(measured)
            @test all(r -> isdisjoint(r.antecedent, r.consequent), rules)
        end
    end

    @testset "Invalid input" begin
        for bad in (0.0, 1.5, NaN, -0.2)
            @test_throws ArgumentError MarketBasket.association_rules(grocery, 5; minconf=bad)
        end
        @test_throws ArgumentError MarketBasket.association_rules(grocery, 5; minconf=1)
        err = try
            MarketBasket.association_rules(SupportMap((1, 2)=>2, (1,)=>2), 3; minconf=0.5)
        catch e
            e
        end
        @test err isa ArgumentError && occursin("(2,)", err.msg)
        @test_throws ArgumentError MarketBasket.association_rules(grocery, 3; minconf=0.5)
        @test_throws ArgumentError MarketBasket.top_rules(MarketBasket.AssociationRule[], 0)
        @test isempty(MarketBasket.association_rules(SupportMap(), 0; minconf=0.5))
    end

    @testset "Recount a rule in another basket set" begin
        rule = only(r for r in MarketBasket.association_rules(grocery, 5; minconf=0.5)
                    if (r.antecedent, r.consequent) == ((2,), (3,)))
        first_three = [[2, 4], [2, 3], [2, 3, 4]]
        recounted = MarketBasket.measure_rule(rule, first_three)
        @test (recounted.support, recounted.antecedent_support, recounted.consequent_support,
               recounted.transactions) == (2, 3, 2, 3)
        @test MarketBasket.confidence(recounted) == 2 // 3 && MarketBasket.lift(recounted) == 1
        none = MarketBasket.measure_rule(rule, [[1], [4]])
        @test (none.support, none.antecedent_support, none.consequent_support, none.transactions) == (0, 0, 0, 2)
        @test MarketBasket.measure_rule(rule, Vector{Int}[]).transactions == 0
    end

    @testset "Analysis helpers" begin
        rules = MarketBasket.association_rules(grocery, 5; minconf=0.5)
        ranks = MarketBasket.rule_ranks(rules)
        @test ranks[((2,), (3,))] == 2 && ranks[((2,), (4,))] == 4
        @test !haskey(ranks, ((3,), (4,)))
        basket = MarketBasket.prepare_baskets(MarketBasket.read_receipts(joinpath(TOY_DIR, RECEIPT_CASE.file)))
        early, late = MarketBasket.split_by_date(basket, "2010-12-02")
        @test early == RECEIPT_CASE.transactions[1:2] && late == RECEIPT_CASE.transactions[3:3]
        # The cutoff belongs to the later part, so a whole day never splits.
        early, late = MarketBasket.split_by_date(basket, "2010-12-01 09:00:00")
        @test length(early) == 1 && length(late) == 2
    end

    @testset "Write rules with product labels" begin
        rules = MarketBasket.association_rules(grocery, 5; minconf=0.5)
        labels = ["beer", "bread", "butter", "milk"]
        mktempdir() do dir
            path = joinpath(dir, "rules.tsv")
            MarketBasket.write_rules(path, rules, labels)
            @test readlines(path) == [
                "rank\tantecedent\tconsequent\tantecedent_ids\tconsequent_ids\tsupport\trelative_support\tconfidence\tlift",
                "1\tbutter\tbread\t3\t2\t3\t0.6000\t1.0000\t1.2500",
                "2\tbread\tbutter\t2\t3\t3\t0.6000\t0.7500\t1.2500",
                "3\tmilk\tbread\t4\t2\t2\t0.4000\t0.6667\t0.8333",
                "4\tbread\tmilk\t2\t4\t2\t0.4000\t0.5000\t0.8333"]
            write(path, "keep\n")
            @test_throws ArgumentError MarketBasket.write_rules(path, rules, ["beer", "bre\tad", "butter", "milk"])
            @test_throws ArgumentError MarketBasket.write_rules(path, rules, labels[1:3])
            @test read(path, String) == "keep\n"
        end
        triple = MarketBasket.association_rules(
            only(c for c in MINING_CASES if c.name == "dense").expected, 2; minconf=1.0)
        @test MarketBasket.rule_labels(triple[2], ["a", "b", "c"]) == ("a", "b + c")
    end
end
