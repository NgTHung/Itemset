# Eclat optimized variant

The baseline joins sorted tid-lists in item order, and on dense data most of its time goes to merging long lists and allocating the results. `mine(...; variant=:optimized)` runs the same Bottom-Up search with five changes that keep its output identical: bitset tidsets, increasing-support item order, perfect-extension pruning, root pair counts on sparse data, and tid lists for classes with short tidsets. This document states what changes in the [baseline's invariants and proof](eclat.md) and what each join costs. The code is in `src/algorithm/tidsets.jl`, `src/algorithm/pair_counts.jl`, and `src/algorithm/eclat_optimized.jl`.

## Bitset tidsets

A bitset tidset holds W = ⌈N/64⌉ words of 64 bits, where N is the transaction count. Bit t − 1 is set exactly when tid t is in the set, so a set's support is the number of set bits. `bitset_tidsets` sets only bits 1 to N, and a join only ANDs words, so the unused high bits of the last word stay zero and never count as a transaction.

`intersect_bitsets!` writes a AND b into a spare set and counts its bits in the same pass. A frequent result becomes a child's tidset. An infrequent result goes back to a pool of spare sets, so a failed join allocates nothing. A child class returns its sets to the pool once its own search ends, because no class still on the search path refers to them.

## Item order

`frequent_items_by_support` orders the frequent items by increasing support, breaking ties by item ID. A class holds only the members after a, so with rare items first, the classes near the root hold the frequent items, whose joins are most likely to succeed. The search emits itemsets in this order, but `prefix` keeps its items sorted by ID, so every emitted itemset is ascending without a sort.

## Invariants and correctness

The baseline's proof uses only one property of the item order: it is a strict total order, and each class takes the members that follow a in it. Increasing support with ID tie-breaks is such an order, so the four invariants of [eclat.md](eclat.md#invariants) hold with "ascending item order" read as this order and "tid-list" read as bitset. The proofs of exact support, no duplicates, and completeness then carry over unchanged. Property 4 holds because the bits of a AND b are set exactly at the tids in both sets.

`tests/eclat_optimized.jl` mines 200 seeded databases against the brute-force oracle. Their sizes include N = 63, 64, 65, 127, 128, and 129, so bitsets cross word boundaries. Each check compares the number of emitted itemsets with the size of the map, so a duplicate cannot hide behind a dictionary overwrite. The file also checks that a search leaves parent sets and the prefix unchanged. The variant also runs every fixture, SPMF, seeded oracle, CLI, and package-image test that the baseline runs.

## Perfect extensions

On dense data many joins return their left input unchanged. On Mushroom at minsup 0.05, the pruned search below reaches 33,819 nodes for 3,755,511 frequent itemsets ([plan](eclat-optimization-plan-2026-10-30.md#future-directions-for-the-report)), so most itemsets need no intersection of their own. Perfect-extension pruning stops joining an item once it adds nothing to a tidset, and emits the itemsets it would have produced directly.

### Definition

An item b is a perfect extension of an itemset X when t(X ∪ {b}) = t(X). Because t(X ∪ {b}) ⊆ t(X) always holds, this is true exactly when both sets have the same support, so `bitset_search!` tests it by comparing one count.

A search node holds three disjoint sets: the core C, the items joined so far; the perfect set E, the perfect extensions found on the path to the node; and the class M, the members still to join. The root has C = E = ∅ and M = every frequent item. For a member a of M, the child node has:

- C' = C ∪ {a};
- E' = E ∪ {b ∈ M : b after a, |t(C ∪ {a, b})| = |t(C ∪ {a})|};
- M' = {b ∈ M : b after a, minsup ≤ |t(C ∪ {a, b})| < |t(C ∪ {a})|}.

The child emits C' ∪ S with support |t(C')| for every S ⊆ E', and then searches M'. Items of E' leave the class, so they are never intersected again below the child.

### Exact support

Claim: t(C ∪ S) = t(C) for every node and every S ⊆ E. At the root E is empty. Assume the claim for a node and take its child. Split S ⊆ E' into S₀ ⊆ E and S₁ of new perfect items. Then t(C' ∪ S₀) = t(C ∪ S₀) ∩ t({a}) = t(C) ∩ t({a}) = t(C'). Each b in S₁ has t(C') ⊆ t({b}), so intersecting with t({b}) changes nothing, and t(C' ∪ S) = t(C'). Every emitted support is therefore exact, and it is at least minsup because a was a member of M.

### Coverage

Members of a node's class are exactly the items b after the last core item, outside E, with C ∪ {b} frequent. This holds at the root. For a child, an item b after a, outside E', with C' ∪ {b} frequent, makes C ∪ {b} frequent, so b is in M, and b is not perfect for C', so it is in M'.

Take a nonempty frequent itemset Z and walk from the root. At a node with C ⊆ Z, let R = Z \ (C ∪ E). If R is empty, the node emits Z as C ∪ (Z ∩ E). Otherwise every item of R comes after the last core item, because the walk always picks the earliest item of R. Let a be the earliest item of R in the item order. C ∪ {a} ⊆ Z is frequent and a is outside E, so a is in M, and the walk moves to the child of a, where C' ⊆ Z still holds. R loses at least a at each step, so the walk ends at a node that emits Z. It leaves the root first, because the root has C ∪ E = ∅.

### Uniqueness

Suppose a node N on the path a₁, a₂, ..., aₖ emits Z. At the node N_j reached after a₁, ..., a_j, a_{j+1} lies in R_j, since it is in Z, outside C_j, and in M_j, which is disjoint from E_j. Take any r in R_j. If r were before a_{j+1}, it could not be a later core item, because core items grow in the item order, so r would be in E. It is not in E_j, so it entered E at a later node N_i with i > j, which only adds items after a_i, and a_i comes no earlier than a_{j+1}. That contradicts r before a_{j+1}. So a_{j+1} is the earliest item of R_j, the coverage walk from Z takes exactly this path, and R is empty at N. Each node is reached by one path, and distinct subsets S of E give distinct itemsets because E is disjoint from C. Each frequent itemset is therefore emitted exactly once.

### Emission order

`push_subsets!` emits the 2^|E| itemsets of a node in binary reflected Gray-code order. Step i toggles the perfect item at position trailing_zeros(i) + 1, so each itemset differs from the one before by one item, which `insert!` or `deleteat!` puts in place in the ascending prefix. A node's emissions therefore cost O(2^|E| k) for itemsets of length at most k, the same as copying them into the packed result. The prefix ends with the last perfect item and drops it, so the caller gets its prefix back unchanged. A perfect set of more than 62 items would need more than 2^62 itemsets, which no result vector can hold, so the search throws `OverflowError` instead of looping.

Half of the seeded databases in `tests/eclat_optimized.jl` draw whole groups of items that always occur together, so perfect extensions appear at every depth. The file also checks that a perfect set too large for a result throws before any emission.

## Root pair counts

On sparse data almost every root join fails: on Retail at minsup 0.001, 99.9% of 2,239,786 root joins fall below the threshold, and each reads 1,378 words. Zaki (2000, Sec. 4.2) counts the 2-itemsets from the horizontal database instead. `count_pairs` does this in one pass: for each transaction it ranks the frequent items it holds and adds one to the slot of every pair in a triangular table of m(m − 1)/2 counts. The root search then joins members i and j only when their pair count reaches minsup.

The skip is exact. At the root the prefix is empty, so the join of members i and j has tidset t({a_i, a_j}), whose size is the pair count. A pair below minsup would fail its join anyway, and every pair at or above it is joined as before, so the classes, and the proofs above, are unchanged. Classes below the root join without counts.

`pair_filter` counts pairs only when that is cheaper than the root joins. Counting touches at most the sum of |t|(|t| − 1)/2 slots, and the root joins read m(m − 1)/2 bitsets of ⌈N/64⌉ words. A slot update can miss the cache while a join reads words in order, so counting must be ten times cheaper by this measure. Retail and T10I4D100K pass by two orders of magnitude, and Chess, Mushroom, and Accidents fail, because their transactions are long and their frequent items few. The table is sized with an overflow check and capped at 2^28 slots before it is allocated; above the cap the search joins every root pair.

`tests/eclat_optimized.jl` mines every seeded database both with and without pair counts.

## Tid lists below the root

A bitset join reads ⌈N/64⌉ words whatever the supports, so it wastes most of its reads when tidsets are short. On T10I4D100K at minsup 0.00025, the search runs 2,256,822 joins at depth 2, 99.1% of them fail, and the children that survive hold about 100 tids against 1,563 words. `search_children!` therefore moves a class of bitset children to ascending tid lists when `prefer_lists` finds lists cheaper. Lists never move back to bitsets, because tidsets only shrink with depth.

`intersect_lists!` merges two ascending lists. Each step writes a[i] into the destination and keeps it only on a match, then advances each cursor by a comparison result, so the loop has no branch that depends on the data. It stops once the tids found plus the shorter remainder cannot reach minsup and returns -1, and it never stops on reaching minsup, because a frequent child needs its whole tidset.

The switch keeps every invariant. `bitset_tids!` lists exactly the set bits, so each member keeps the same tidset in a new form. A join that returns -1 had support below minsup, which the bitset search would also have rejected, and a join that reaches minsup returns its exact support, so frequent children and perfect extensions are the same as with bitsets. The proofs above therefore hold for list classes unchanged.

`prefer_lists` compares the cost of a class's own joins both ways, with W = ⌈N/64⌉. As bitsets, its k members make k(k − 1)/2 joins of W words. As lists, each member first costs one W-word scan to convert, and the joins merge (k − 1) times the sum of the supports, at `LIST_STEP_COST` words per merge step. A rule on mean support alone slowed Retail 0.00025 by 12%, because its switched classes made 2.4 joins per child against 50 on T10I4D100K 0.00025, so the conversions cost about what the joins saved. Counting the conversions keeps classes with few members as bitsets.

A warm sweep on BBQ of `LIST_STEP_COST` from 2 to 16 set it to 8. At 8, T10I4D100K 0.00025 mining drops from 1.20 s to 0.90 s, and Retail 0.00025, Retail 0.001, and T10I4D100K 0.001 stay within 1% of bitsets only. Smaller costs switch too many classes and slow T10I4D100K 0.0005 by up to 46%.

`tests/eclat_optimized.jl` mines every seeded database with lists never, always, or by the cost rule, so the conversion and the merge run across word boundaries. It also checks that a list search leaves its parents, prefix, and perfect stack unchanged.

## Cost

A join reads 3W words, whatever the supports of its inputs. On Chess, W is 50, and on Accidents it is 5,316. A sorted-list join instead costs the lengths of both lists. Bitsets therefore win when the frequent items cover a large part of N and lose on sparse data such as Retail, where a frequent item covers a small part of N. Building the root sets takes one pass over the database with a hash lookup per item occurrence, plus m sets of W words, where m is the number of frequent items. The search keeps at most one class per level of the current path, plus the pooled spare sets.
