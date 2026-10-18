# Shared transaction/mining contract — DAT-6 draft

This initial contract is ready for Thien and Phat to review; it is not an assertion
that their review or the baseline release (DAT-13) has happened.

## Transactions

An in-memory database is a vector of integer-ID collections. IDs are nonnegative
`Int`s (including 0; never Bool). Sort and deduplicate each transaction. Preserve
repeated transactions as distinct records. Keep deterministic reversible mappings
between retail product/image visual-word labels and IDs outside the miner.

`read_transactions(path)` reads whitespace-delimited SPMF transaction text.
Whole-line `#`, `%`, `@` metadata/comments and blanks are skipped. Malformed tokens
and negative IDs fail with a line number. SPMF sequence delimiters are unsupported.
An in-memory empty transaction counts in N; a blank text line does not encode one.
Application preprocessing must record any removal of empty transactions.

## Thresholds and output

`mine(transactions; minsup, variant=:baseline)` returns `SupportMap`, a
`Dict{Tuple{Vararg{Int}},Int}` of **all** frequent nonempty itemsets. Canonical keys
are ascending unique IDs. Supports count transactions, not token multiplicity.
An empty database or an absolute threshold above N returns an empty map once the
miner is implemented. No output-length cap or silent closed/maximal substitution.

- Integer minsup >=1: absolute count (`1` means one transaction).
- Floating minsup in (0,1]: relative; count = ceil(decimal minsup * N), at least 1.
  `1.0` means all transactions. Decimal-boundary example: 0.07 of 100 means 7.
- CLI `--minsup FRACTION` and `--min-count COUNT` are mutually exclusive.
- Variants `:baseline` and `:optimized` must eventually obey the same contract.
  Today both raise an explicit unimplemented error. Never silently fall back.

`write_itemsets` writes lexicographically ordered lines `1 2 #SUP: 3`.
An empty map writes an empty file. Invalid keys/supports are rejected.

## Work before baseline validation

Use `data/toy/*.expected.txt` and `tests/fixtures.jl` for association-rule logic,
image result rendering, comparator tests, and API integration. These hand-derived
fixtures are not reference-executable output and must be labelled as fixtures.
The final miner tests must compare complete maps across all five databases and
against independent SPMF runs; setup tests cannot stand in for that evidence.

Top-lift rule support uses the union X∪Y; confidence=support(X∪Y)/support(X),
lift=confidence/(support(Y)/N), for nonempty disjoint X,Y. Neither application
should depend on internal tidset types. Use seed 20261018 wherever random choices
are made, and retain mapping/codebook parameters for reproducibility.
