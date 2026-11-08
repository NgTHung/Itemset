"""Bitset tidsets of `items` over `database`, as root-class members in the given order."""
function bitset_members(database, items)
    words = ItemsetMining.bitset_tidsets(database, items)
    return [ItemsetMining.BitsetMember(item, sum(count_ones, w; init=0), w) for (item, w) in zip(items, words)]
end

@testset "Diffset operations" begin
    @testset "List differences are exact within the bound and -1 beyond it" begin
        difference_lists! = ItemsetMining.difference_lists!
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:500
            b = sort!(unique(rand(rng, 1:60, rand(rng, 0:30))))
            a = sort!(unique(rand(rng, 1:60, rand(rng, 0:30))))
            bound = rand(rng, 0:30)
            b_before, a_before = copy(b), copy(a)
            dest = rand(rng, 1:9, rand(rng, 0:3))
            expected = setdiff(b, a)
            count = difference_lists!(dest, b, a, bound)
            if length(expected) <= bound
                @test count == length(expected) && dest == expected
            else
                @test count == -1
            end
            @test b == b_before && a == a_before
        end
        @test @inferred(difference_lists!(Int[], [1, 2, 3], [2], 5)) == 2
        @test difference_lists!(Int[], Int[], [1, 2], 0) == 0
    end

    @testset "Bitset differences list a AND NOT b for N = $n" for n in (1, 63, 64, 65, 129)
        bitset_difference! = ItemsetMining.bitset_difference!
        rng = Xoshiro(DEFAULT_SEED + n)
        for _ in 1:20
            in_a, in_b = rand(rng, Bool, n), rand(rng, Bool, n)
            database = [[item for (item, member) in ((1, in_a[t]), (2, in_b[t])) if member] for t in 1:n]
            a, b = ItemsetMining.bitset_tidsets(database, [1, 2])
            expected = [t for t in 1:n if in_a[t] && !in_b[t]]
            bound = rand(rng, 0:n)
            dest = Int[]
            count = bitset_difference!(dest, a, b, bound)
            @test count == (length(expected) <= bound ? length(expected) : -1)
            count >= 0 && @test dest == expected
        end
        @test_throws DimensionMismatch bitset_difference!(Int[], zeros(UInt64, 1), zeros(UInt64, 2), 1)
    end

    @testset "A member switches when its diffsets are short against a bitset join" begin
        prefer_diffsets = ItemsetMining.prefer_diffsets
        state(rule=:cost) = ItemsetMining.SearchState(:cost, 8.0, rule, 1.0)
        member(support) = ItemsetMining.BitsetMember(1, support, zeros(UInt64, 100))
        # Bound 2 × (support - minsup) against 1.0 × 100 words.
        @test prefer_diffsets(member(140), 100, state())
        @test !prefer_diffsets(member(160), 100, state())
        @test prefer_diffsets(member(900), 100, state(:always))
        @test !prefer_diffsets(member(101), 100, state(:never))
        @test !prefer_diffsets(ItemsetMining.ListMember(1, 101, Int[]), 100, state(:always))
    end
end

@testset "Diffset classes" begin
    DiffMember = ItemsetMining.DiffMember
    join_members! = ItemsetMining.join_members!

    @testset "Supports stay exact across the switch, and children own their diffsets" begin
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:100
            database = ItemsetMining.canonical_database([rand(rng, 1:6, rand(rng, 0:6)) for _ in 1:rand(rng, 1:70)])
            class = bitset_members(database, collect(1:6))
            any(m -> m.support == 0, class) && continue
            before = [copy(m.tidset) for m in class]
            children, perfect = DiffMember[], Int[]
            join_members!(children, perfect, class, 1, 1, Vector{Int}[])
            a = class[1]
            t(x) = Set(findall(transaction -> x in transaction, database))
            for child in children
                @test child.support == length(t(a.item) ∩ t(child.item))
                @test child.tidset == sort!(collect(setdiff(t(a.item), t(child.item))))
                @test all(m -> m.tidset !== child.tidset, class)
            end
            for item in perfect
                @test t(a.item) ⊆ t(item)
            end
            @test [m.tidset for m in class] == before
        end
    end

    @testset "An empty diffset marks a perfect extension" begin
        # In class Q, d(Qb) = [2, 4] and d(Qc) = [4], so d(Qbc) = d(Qc) \ d(Qb) is empty.
        class = [DiffMember(7, 5, [2, 4]), DiffMember(8, 6, [4]), DiffMember(9, 6, [1])]
        children, perfect = DiffMember[], Int[]
        @test join_members!(children, perfect, class, 1, 2, Vector{Int}[]) == 1
        @test perfect == [8]
        # d(Qb9) = [1] \ [2, 4] = [1], so support(Qb9) = 5 - 1.
        @test [(c.item, c.support, c.tidset) for c in children] == [(9, 4, [1])]
    end

    @testset "A diffset search leaves its parents, prefix, and perfect stack unchanged" begin
        database = [[1, 2, 3, 4], [1, 2, 4], [2, 3, 4], [1, 3, 4], [1, 2, 3, 4], [2, 4], [1, 2, 4]]
        class = ItemsetMining.bitset_class(database, 2)
        before = [copy(m.tidset) for m in class]
        prefix, perfect = Int[], Int[]
        state = ItemsetMining.SearchState(:never, 8.0, :always, 1.0)
        result = @inferred ItemsetMining.eclat_search!(class, prefix, perfect, 2, FrequentItemsets(), state)
        @test [m.tidset for m in class] == before
        @test isempty(prefix) && isempty(perfect)
        @test support_map(result) == brute_force_supports(database, 2)
        @test length(result) == length(support_map(result))
    end

    @testset "Mining matches the oracle with diffsets $diff_rule and lists $list_rule" for diff_rule in
            (:never, :always, :cost), list_rule in (:never, :always)
        rng = Xoshiro(DEFAULT_SEED)
        for _ in 1:100
            transactions = [rand(rng, 0:11, rand(rng, 0:8)) for _ in 1:rand(rng, 0:40)]
            database = ItemsetMining.canonical_database(transactions)
            min_count = rand(rng, 1:4)
            expected = brute_force_supports(unique.(transactions), min_count)
            packed = ItemsetMining.mine_optimized(database, min_count; diff_rule, list_rule)
            @test support_map(packed) == expected
            @test length(packed) == length(expected)
        end
    end
end
