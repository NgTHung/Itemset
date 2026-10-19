# Transaction and mining contract

The market basket and image-pattern applications, the benchmark runner, and the SPMF comparator all exchange data with `ItemsetMining`. This contract fixes what each of them may assume about transactions, support thresholds, and mined output. Every Eclat variant obeys it, so a caller can switch variants or compare outputs without code changes.

## Transactions

A database is a vector of transactions, and each transaction is a collection of integer item IDs. IDs are nonnegative `Int` values, and 0 is valid. `Bool` values are rejected, because Julia treats `true` as the integer 1 and a boolean column would silently become item 1.

`canonical_transaction` sorts and deduplicates one transaction. Support counts transactions, not item occurrences, so repeated items in one transaction collapse. Repeated transactions stay distinct records, because each is a separate receipt or image.

Applications keep their own reversible mapping between labels, such as product names or visual words, and IDs. The miner never sees labels.

## Read SPMF input

`read_transactions(path)` reads SPMF transaction text: one transaction per line, items separated by whitespace.

- Blank lines and lines that start with `#`, `%`, or `@` are skipped as comments and metadata.
- A malformed token or a negative ID throws `ArgumentError` with the line number. This rejects SPMF sequence files, whose `-1` and `-2` delimiters would otherwise be read as items.
- A blank line never encodes an empty transaction. To count empty transactions in N, build the database in memory, and record the removal or retention of empty transactions in the application's preprocessing notes.

## Support thresholds

`support_threshold(minsup, N)` converts `minsup` into the minimum transaction count.

- An integer `minsup` of at least 1 is an absolute count. `1` means one transaction.
- A floating-point `minsup` in (0, 1] is a fraction. The count is `ceil(minsup * N)` computed on the decimal value, and at least 1. `1.0` means all transactions, and `0.07` of 100 transactions means 7, not the 8 that `Float64` arithmetic would give.
- Any other value, including `Bool`, zero, `NaN`, and `Inf`, throws `ArgumentError`.

The CLI exposes the two forms as the mutually exclusive `--minsup FRACTION` and `--min-count COUNT`.

## Mine

`mine(transactions; minsup, variant=:baseline)` returns a `SupportMap`, a `Dict{Tuple{Vararg{Int}},Int}` that holds all frequent nonempty itemsets and their exact support counts.

- `mine` validates and canonicalizes every transaction before a variant runs, so both variants reject the same input. An invalid transaction throws `ArgumentError` naming its 1-based index.
- Keys are canonical: ascending, unique IDs.
- An empty database, or an absolute threshold above N, returns an empty map.
- The output has no length cap and never substitutes closed or maximal itemsets, because the SPMF comparison and both applications need the complete set.
- `variant` is `:baseline` or `:optimized`. Any other symbol throws `ArgumentError`. Both variants return equal maps for the same input, and a failing variant raises an error instead of falling back to the other.

Callers depend only on this function and its output, never on tidsets or other internal types, so the optimized variant can change its data structures freely.

## Write output

`write_itemsets(path, patterns)` writes one itemset per line in lexicographic key order, in SPMF format:

```text
1 2 #SUP: 3
```

The fixed order makes output files byte-comparable across variants and runs. It validates every key and support before writing any line, so an invalid map never produces partial output. An empty map writes an empty file.

## Association rules

The market basket application derives rules from the `SupportMap` with these definitions, where X and Y are nonempty disjoint itemsets and N is the transaction count:

- support(X ⇒ Y) = support(X ∪ Y)
- confidence(X ⇒ Y) = support(X ∪ Y) / support(X)
- lift(X ⇒ Y) = confidence(X ⇒ Y) / (support(Y) / N)

The hand-derived fixtures in [data/toy](../data/toy/README.md) let you test rule logic and result rendering against known maps.
