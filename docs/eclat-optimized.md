# Eclat optimized variant

The baseline joins sorted tid-lists in item order, and on dense data most of its time goes to merging long lists and allocating the results. `mine(...; variant=:optimized)` runs the same Bottom-Up search with two changes that keep its output identical: bitset tidsets and increasing-support item order. This document states what changes in the [baseline's invariants and proof](eclat.md) and what each join costs. The code is in `src/algorithm/tidsets.jl` and `src/algorithm/eclat_optimized.jl`.

## Bitset tidsets

A bitset tidset holds W = ⌈N/64⌉ words of 64 bits, where N is the transaction count. Bit t − 1 is set exactly when tid t is in the set, so a set's support is the number of set bits. `bitset_tidsets` sets only bits 1 to N, and a join only ANDs words, so the unused high bits of the last word stay zero and never count as a transaction.

`intersect_bitsets!` writes a AND b into a spare set and counts its bits in the same pass. A frequent result becomes a child's tidset. An infrequent result goes back to a pool of spare sets, so a failed join allocates nothing. A child class returns its sets to the pool once its own search ends, because no class still on the search path refers to them.

## Item order

`frequent_items_by_support` orders the frequent items by increasing support, breaking ties by item ID. A class holds only the members after a, so with rare items first, the classes near the root hold the frequent items, whose joins are most likely to succeed. The search emits itemsets in this order, but `prefix` keeps its items sorted by ID, so every emitted itemset is ascending without a sort.

## Invariants and correctness

The baseline's proof uses only one property of the item order: it is a strict total order, and each class takes the members that follow a in it. Increasing support with ID tie-breaks is such an order, so the four invariants of [eclat.md](eclat.md#invariants) hold with "ascending item order" read as this order and "tid-list" read as bitset. The proofs of exact support, no duplicates, and completeness then carry over unchanged. Property 4 holds because the bits of a AND b are set exactly at the tids in both sets.

`tests/tidsets.jl` checks the boundary cases of N = 0, 1, 63, 64, 65, 127, 128, and 129. It also checks the unused high bits, that parent sets and the prefix are unchanged after a search, and the item order. The variant also runs every fixture, SPMF, seeded oracle, CLI, and package-image test that the baseline runs.

## Cost

A join reads 3W words, whatever the supports of its inputs. On Chess, W is 50, and on Accidents it is 5,316. A sorted-list join instead costs the lengths of both lists. Bitsets therefore win when the frequent items cover a large part of N and lose on sparse data such as Retail, where a frequent item covers a small part of N. Building the root sets takes one pass over the database with a hash lookup per item occurrence, plus m sets of W words, where m is the number of frequent items. The search keeps at most one class per level of the current path, plus the pooled spare sets.
