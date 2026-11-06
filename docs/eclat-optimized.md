# Eclat optimized variant

The baseline joins sorted tid-lists in item order, and on dense data most of its time goes to merging long lists and allocating the results. `mine(...; variant=:optimized)` runs the same Bottom-Up search with three changes that keep its output identical: bitset tidsets, increasing-support item order, and perfect-extension pruning. This document states what changes in the [baseline's invariants and proof](eclat.md) and what each join costs. The code is in `src/algorithm/tidsets.jl` and `src/algorithm/eclat_optimized.jl`.

## Bitset tidsets

A bitset tidset holds W = ⌈N/64⌉ words of 64 bits, where N is the transaction count. Bit t − 1 is set exactly when tid t is in the set, so a set's support is the number of set bits. `bitset_tidsets` sets only bits 1 to N, and a join only ANDs words, so the unused high bits of the last word stay zero and never count as a transaction.

`intersect_bitsets!` writes a AND b into a spare set and counts its bits in the same pass. A frequent result becomes a child's tidset. An infrequent result goes back to a pool of spare sets, so a failed join allocates nothing. A child class returns its sets to the pool once its own search ends, because no class still on the search path refers to them.

## Item order

`frequent_items_by_support` orders the frequent items by increasing support, breaking ties by item ID. A class holds only the members after a, so with rare items first, the classes near the root hold the frequent items, whose joins are most likely to succeed. The search emits itemsets in this order, but `prefix` keeps its items sorted by ID, so every emitted itemset is ascending without a sort.

## Invariants and correctness

The baseline's proof uses only one property of the item order: it is a strict total order, and each class takes the members that follow a in it. Increasing support with ID tie-breaks is such an order, so the four invariants of [eclat.md](eclat.md#invariants) hold with "ascending item order" read as this order and "tid-list" read as bitset. The proofs of exact support, no duplicates, and completeness then carry over unchanged. Property 4 holds because the bits of a AND b are set exactly at the tids in both sets.

`tests/tidsets.jl` checks the boundary cases of N = 0, 1, 63, 64, 65, 127, 128, and 129. It also checks the unused high bits, that parent sets and the prefix are unchanged after a search, and the item order. The variant also runs every fixture, SPMF, seeded oracle, CLI, and package-image test that the baseline runs.

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

`tests/perfect_extensions.jl` checks universal items, groups of items with equal tidsets, siblings with equal support but different tidsets, perfect extensions found at two depths of one path, and itemsets whose support equals minsup. Each check compares the number of emitted itemsets with the size of the map, so a duplicate cannot hide behind a dictionary overwrite.

## Cost

A join reads 3W words, whatever the supports of its inputs. On Chess, W is 50, and on Accidents it is 5,316. A sorted-list join instead costs the lengths of both lists. Bitsets therefore win when the frequent items cover a large part of N and lose on sparse data such as Retail, where a frequent item covers a small part of N. Building the root sets takes one pass over the database with a hash lookup per item occurrence, plus m sets of W words, where m is the number of frequent items. The search keeps at most one class per level of the current path, plus the pooled spare sets.
