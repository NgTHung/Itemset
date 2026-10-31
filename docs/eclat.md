# Eclat baseline

`mine(...; variant=:baseline)` finds every frequent itemset with Eclat from Zaki, "Scalable Algorithms for Association Mining" (IEEE TKDE 2000). It counts support by intersecting tid-lists instead of rescanning the database. This document states the invariants the code in `src/algorithm/eclat.jl` keeps, proves that they give each frequent itemset exactly once with its exact support, and gives the cost. The caller contract lives in [interface.md](interface.md).

## Terms

- A tid is the 1-based index of a transaction in the canonical database. Empty transactions get a tid and count in N, but they appear in no tid-list.
- The tid-list t(X) of an itemset X holds the tids of the transactions that contain X, so support(X) = |t(X)|.
- A prefix-based equivalence class with prefix P is a list of members (b, t(P ∪ {b})), where each b is an item greater than every item of P (Zaki, Sec. 3).

## Algorithm

1. `to_class` builds the vertical index: each item with its tid-list, sorted by item.
2. `mine` drops the items whose tid-list is shorter than the count threshold. The rest form the root class, whose prefix is empty.
3. `bottom_up!` follows the Bottom-Up procedure (Zaki, Sec. 4.2). For each member a of a class with prefix P, it records P ∪ {a}. It then intersects t(P ∪ {a}) with the tid-list of every later member b, keeps the frequent results as the class with prefix P ∪ {a}, and searches that class before it moves to the next a.

The paper counts the frequent 2-itemsets from the horizontal database with a triangular array before the first intersection. The baseline starts the intersections at the single items instead, so one routine handles every level.

## Invariants

Every class that `bottom_up!` receives satisfies these four properties.

1. Each tid-list is ascending with no repeats. `to_class` adds tids in database order, and `intersect_tidlists` merges two ascending lists into an ascending result.
2. Members are in ascending item order, and each item is greater than every item of the prefix.
3. Each member is frequent: its tid-list has at least `minsup` tids.
4. The tid-list of member b is exactly t(P ∪ {b}).

The root class meets all four by construction. A child class takes members b after a from a class that meets them, so properties 1 and 2 carry over. The size check before `push!` gives property 3. A transaction contains P ∪ {a, b} exactly when it contains both P ∪ {a} and P ∪ {b}, so t(P ∪ {a, b}) = t(P ∪ {a}) ∩ t(P ∪ {b}), which gives property 4.

## Correctness

Exact support. By property 4, the recorded value |t(P ∪ {a})| is the number of transactions that contain P ∪ {a}.

No duplicates. Properties 2 and 4 make every recorded key strictly ascending. A key (x1, ..., xk) is recorded only when the class with prefix (x1, ..., xk-1) reaches member xk. Each class is created once, by the search of its prefix, so each key is recorded once.

Complete output. Take a frequent itemset X = {x1 < ... < xk}. Every subset of X is frequent, because a transaction that contains X contains each subset, so the pruning in steps 2 and 3 never removes a subset of a frequent itemset. By induction on j, the class with prefix (x1, ..., xj-1) holds every item y > xj-1 for which (x1, ..., xj-1, y) is frequent. The root class holds every frequent item. For the step, if (x1, ..., xj, y) is frequent with y > xj, then (x1, ..., xj-1, y) is frequent and holds y after xj in the parent class, so the join keeps it. With j = k, the class of (x1, ..., xk-1) holds xk, and the search records X.

`tests/eclat.jl` checks these claims on every toy fixture and on 300 seeded random databases against a brute-force count of all subsets.

## Cost

Let N be the transaction count, L the total number of items over all transactions, m the number of distinct items, and C the number of joins.

- The vertical index takes O(L) expected time for the dictionary, O(m log m) for the sort, and O(L) memory.
- One join merges two tid-lists in O(|t(P ∪ {a})| + |t(P ∪ {b})|) time, which is at most O(N), and allocates only the resulting tid-list.
- A class with k members makes k(k - 1)/2 joins, so C is the sum of that count over all searched classes, and the total time is O(L + m log m + C N).
- The search is depth-first, so memory holds only the classes on the current path: at most one class per level, each with at most m members of up to N tids.

The output itself can grow exponentially with the longest frequent itemset, since a frequent k-itemset has 2^k - 1 frequent nonempty subsets.
