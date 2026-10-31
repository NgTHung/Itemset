# Transaction and mining contract

The market basket and image-pattern applications, the benchmark runner, and the SPMF comparator all exchange data with `ItemsetMining`. This contract fixes what each of them may assume about transactions, support thresholds, and mined output. Every Eclat variant obeys it, so a caller can switch variants or compare outputs without code changes.

## Transactions

A database is a vector of transactions, and each transaction is a collection of integer item IDs. IDs are nonnegative `Int` values, and 0 is valid. `Bool` values are rejected, because Julia treats `true` as the integer 1 and a boolean column would silently become item 1.

`canonical_transaction` sorts and deduplicates one transaction. Support counts transactions, not item occurrences, so repeated items in one transaction collapse. Repeated transactions stay distinct records, because each is a separate receipt or image.

An empty transaction, such as an image with no visual words, is a valid record and counts in N. Dropping it raises every relative support, so an application keeps empty transactions unless its preprocessing notes justify the removal.

## Item labels

Applications start from labels, such as product names or visual words, and the miner sees only IDs. Both applications use the same encoding, so a mapping recorded by one is read the same way by the other.

- `encode_transactions(rows)` returns `(transactions, labels)`. IDs start at 1 and follow sorted label order, so the mapping depends only on the set of labels, never on row order, and `labels[id]` is the label of `id`.
- `decode_itemset(labels, itemset)` returns the labels of an itemset. An ID without a label throws `ArgumentError`, because it means the itemset and labels come from different encodings.
- A `missing`, `nothing`, or blank label throws `ArgumentError` naming its row. Preprocessing removes such values or replaces them with an explicit label, so a gap in the raw data never becomes a product.
- Each row must be a collection of labels. A bare string row throws `ArgumentError`, because Julia would otherwise split it into characters.

## Read SPMF input

`read_transactions(path)` reads SPMF transaction text: one transaction per line, items separated by whitespace.

- Blank lines and lines that start with `#`, `%`, or `@` are skipped as comments and metadata.
- A malformed token or a negative ID throws `ArgumentError` with the line number. This rejects SPMF sequence files, whose `-1` and `-2` delimiters would otherwise be read as items.
- A blank line never encodes an empty transaction. To count empty transactions in N, build the database in memory, and record the removal or retention of empty transactions in the application's preprocessing notes.

## Write SPMF input

`write_transactions(path, transactions; labels)` writes a database as SPMF transaction text, so applications and benchmark subsets can feed the CLI, Colab, and SPMF reference runs. With `labels`, the file starts with SPMF's own metadata lines, which `read_transactions` skips:

```text
@CONVERTED_FROM_TEXT
@ITEM=1=beer
@ITEM=2=bread
1 2
```

An empty transaction throws `ArgumentError`, because its blank line would read back as no transaction and change N. To compare a database that keeps empty transactions with SPMF, run both with the same absolute count (`--min-count`) instead of a fraction. The writer validates every transaction and label before it opens the output, so invalid input never truncates an existing file.

## Support thresholds

`support_threshold(minsup, N)` converts `minsup` into the minimum transaction count.

- An integer `minsup` of at least 1 is an absolute count. `1` means one transaction.
- A floating-point `minsup` in (0, 1] is a fraction. The count is `ceil(minsup * N)` computed on the decimal value, and at least 1. `1.0` means all transactions, and `0.07` of 100 transactions means 7, not the 8 that `Float64` arithmetic would give.
- Any other value, including `Bool`, zero, `NaN`, and `Inf`, throws `ArgumentError`.

The CLI exposes the two forms as the mutually exclusive `--minsup FRACTION` and `--min-count COUNT`.

## Randomness

Every stochastic step, such as fitting a k-means codebook or sampling a benchmark subset, takes an explicit `rng::AbstractRNG` argument and never touches the global RNG, so its output depends only on its arguments. Scripts build the generator as `Random.Xoshiro(DEFAULT_SEED)`, with the seed defined once in `src/structures.jl`. Julia does not promise the same random stream across minor versions, so seeded results reproduce on the version pinned in `.julia-version`.

## Mine

`mine(transactions; minsup, variant=:baseline)` returns a `SupportMap`, a `Dict{Tuple{Vararg{Int}},Int}` that holds all frequent nonempty itemsets and their exact support counts.

- `mine` validates and canonicalizes every transaction before a variant runs, so both variants reject the same input. An invalid transaction throws `ArgumentError` naming its 1-based index. A transaction must be a collection, so a flat vector such as `[1, 2, 3]` is rejected instead of read as three one-item transactions.
- Keys are canonical: ascending, unique IDs.
- Keys are tuples whatever a variant uses internally, so caller code such as `patterns[(2, 3)]` works with both variants.
- Every nonempty subset of a key is also a key, because a subset occurs in at least as many transactions. Rule code can look up any antecedent or consequent without a missing-key check.
- An empty database, or an absolute threshold above N, returns an empty map.
- The output has no length cap and never substitutes closed or maximal itemsets, because the SPMF comparison and both applications need the complete set.
- `variant` is `:baseline` or `:optimized`. Any other symbol throws `ArgumentError`. Both variants return equal maps for the same input, and a failing variant raises an error instead of falling back to the other.

Callers depend only on this function and its output, never on tidsets or other internal types, so the optimized variant can change its data structures freely.

## Mine packed

A tuple key per itemset costs more than mining on dense data, where millions of itemsets each share one support count. `mine_packed(transactions; minsup, variant=:baseline)` returns the same itemsets and supports as `mine` in a `FrequentItemsets` value, and throws for the same input. The CLI and the benchmark writer use it, and `mine` converts it once with `support_map`.

- `FrequentItemsets` stores every itemset back to back in one `items` vector. Itemset `k` is `items[offsets[k]:offsets[k+1]-1]` with support `supports[k]`.
- Iteration yields `itemset => support` pairs, where `itemset` is a view into `items`. Each itemset is ascending, and each appears once.
- The order of itemsets is unspecified, so a variant may emit them in its own search order. `write_itemsets` restores the fixed file order.
- `support_map(packed)` returns the `SupportMap` that `mine` returns.

## Write output

`write_itemsets(path, patterns)` writes one itemset per line in SPMF format. Lines are in numeric lexicographic key order: IDs compare as numbers, and a key precedes its extensions.

```text
1 #SUP: 2
1 2 #SUP: 1
1 10 #SUP: 1
2 #SUP: 1
10 #SUP: 1
```

The fixed order makes output files byte-comparable across variants and runs. SPMF writes its output in mining order, so a comparator parses both files into maps instead of comparing bytes. It validates every key and support before it opens the output, so an invalid map never produces partial output or truncates an existing file. An empty map writes an empty file.

## Read output

`read_itemset_records(path)` reads output from `write_itemsets` or SPMF as one `(itemset, support, line)` record per itemset line, in file order. Itemsets come back canonical, so SPMF's `2 1 #SUP: 3` reads as `(1, 2)`. A repeated itemset stays as a separate record instead of overwriting the first, because the SPMF comparator must report both supports.

- Metadata lines are skipped as in `read_transactions`. A line holding `#SUP:` is always an itemset, so `#SUP: 1` throws instead of passing as a comment.
- A line without `#SUP:`, an invalid or repeated item ID, an empty itemset, or a support below 1 throws `ArgumentError` with the line number.

## Association rules

The market basket application derives rules from the `SupportMap` with these definitions, where X and Y are nonempty disjoint itemsets and N is the transaction count:

- support(X ⇒ Y) = support(X ∪ Y)
- confidence(X ⇒ Y) = support(X ∪ Y) / support(X)
- lift(X ⇒ Y) = confidence(X ⇒ Y) / (support(Y) / N)

The hand-derived fixtures in [data/toy](../data/toy/README.md) let you test rule logic and result rendering against known maps.

## Example

The grocery fixture runs through the whole contract, so you can check each value by hand against [data/toy/groceries.expected.txt](../data/toy/groceries.expected.txt).

```julia
using ItemsetMining
rows = [["bread", "milk"], ["bread", "butter"], ["bread", "butter", "milk"],
        ["beer", "milk"], ["bread", "butter"]]
transactions, labels = encode_transactions(rows)  # labels == ["beer", "bread", "butter", "milk"]
write_transactions("results/groceries.txt", transactions; labels)
patterns = mine(transactions; minsup=0.4)         # 2 of 5 receipts
decode_itemset(labels, (2, 3))                    # ["bread", "butter"]
patterns[(2, 3)] / patterns[(2,)]                 # confidence(bread ⇒ butter) == 0.75
write_itemsets("results/groceries-patterns.txt", patterns)
```
