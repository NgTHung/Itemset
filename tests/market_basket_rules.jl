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
    @testset "Rules agree with direct counting on random databases" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:60
            transactions = [sort!(unique(rand(rng, 1:6, rand(rng, 1:4)))) for _ in 1:rand(rng, 4:10)]
            n = length(transactions)
            rules = MarketBasket.association_rules(mine(transactions; minsup=2), n; minconf=0.3)
            measured = Set((r.antecedent, r.consequent, r.support, MarketBasket.confidence(r),
                            MarketBasket.lift(r)) for r in rules)
            @test measured == brute_force_rules(transactions, 2, 3 // 10)
            @test length(rules) == length(measured)
        end
    end

    @testset "Ties order by antecedent, then consequent" begin
        dense = only(c for c in MINING_CASES if c.name == "dense").expected
        rules = MarketBasket.association_rules(dense, 2; minconf=1.0)
        @test rule_pairs(rules) == [
            ((1,), (2,)), ((1,), (2, 3)), ((1,), (3,)), ((1, 2), (3,)), ((1, 3), (2,)),
            ((2,), (1,)), ((2,), (1, 3)), ((2,), (3,)), ((2, 3), (1,)),
            ((3,), (1,)), ((3,), (1, 2)), ((3,), (2,))]
        cut = MarketBasket.top_rules(rules, 10)
        @test cut.rules == rules[1:10] && cut.ties_beyond == 2
    end

    @testset "A group stays present while any of its rules passes" begin
        # The best rule of group {1,2,3} is 1 => 2 + 3 (confidence 3/4, lift 21/16).
        # At minconf 0.76 it fails, yet 1 + 3 => 2 (confidence 1) still passes.
        transactions = [[2], [2], [1, 2], [1, 2, 3], [1, 2, 3], [2, 3], [1, 2, 3]]
        rules = MarketBasket.association_rules(mine(transactions; minsup=1), 7; minconf=0.76)
        @test MarketBasket.group_ranks(rules) == Dict((1, 2) => 1, (2, 3) => 2, (1, 2, 3) => 3)
        @test rule_pairs(MarketBasket.top_rule_groups(rules, 1)) == [rule_pairs(rules)[1]]
    end

    @testset "minconf is the exact decimal fraction" begin
        @test MarketBasket.decimal_fraction(0.1 + 0.2) == 30000000000000004 // 100000000000000000
        @test_throws ArgumentError MarketBasket.decimal_fraction(NaN)
        # The real baskets hold a rule with confidence 231/770 = 3/10. Rounding
        # ceil(0.3 * 770) up to 232 would drop it at minconf 0.3.
        real_case = SupportMap((1,)=>770, (2,)=>300, (1, 2)=>231)
        @test ((1,), (2,)) in rule_pairs(MarketBasket.association_rules(real_case, 1000; minconf=0.3))
        @test ((1,), (2,)) ∉ rule_pairs(MarketBasket.association_rules(real_case, 1000; minconf=0.31))
    end

    @testset "Invalid input" begin
        grocery = only(c for c in MINING_CASES if c.name == "groceries").expected
        for bad in (0.0, 1.5, NaN, 1)
            @test_throws ArgumentError MarketBasket.association_rules(grocery, 5; minconf=bad)
        end
        @test_throws "(2,)" MarketBasket.association_rules(SupportMap((1, 2)=>2, (1,)=>2), 3; minconf=0.5)
        @test_throws ArgumentError MarketBasket.top_rules(reverse(MarketBasket.association_rules(grocery, 5; minconf=0.5)), 2)
    end

    @testset "Recount a rule in another basket set" begin
        rule = MarketBasket.AssociationRule((2,), (3,), 3, 4, 3, 5)
        recounted = MarketBasket.measure_rule(rule, [[2, 4], [2, 3], [2, 3, 4]])
        @test (recounted.support, recounted.antecedent_support, recounted.consequent_support,
               recounted.transactions) == (2, 3, 2, 3)
        @test MarketBasket.measure_rule(rule, Vector{Int}[]).transactions == 0
    end

    @testset "Write rules with product labels" begin
        grocery = only(c for c in MINING_CASES if c.name == "groceries").expected
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
            @test read(path, String) == "keep\n"
        end
    end
end
