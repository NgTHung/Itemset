# Market basket analysis

A retailer wants to know which products customers buy together, so it can place, bundle, or promote them. This workstream turns real receipts into transactions, mines them with `ItemsetMining.mine`, and reports the association rules with the highest lift. Owner: Thien. Reviewer: Hung. Linear: DAT-10 (data), DAT-14 (rules), DAT-37 (notebook).

## Prepare the data

```sh
julia --startup-file=no --project=. applications/market_basket/prepare.jl
```

The script downloads [Online Retail II](https://doi.org/10.24432/C5CG6D) (UCI, CC BY 4.0) from a pinned Hugging Face mirror and checks its SHA-256 against [data/raw/manifest.toml](../../data/raw/manifest.toml). It then writes three files to `data/raw/market_basket/`:

- `baskets.txt`: one SPMF transaction per invoice, with `@ITEM=id=stock code` lines.
- `items.tsv`: ID, stock code, description, and the number of baskets that hold the item.
- `cleaning.tsv`: rows removed and rows and invoices left after each step.

The data holds every line of a UK online gift retailer's invoices from 2009-12-01 to 2011-12-09. One transaction is one invoice, ordered by invoice number. One item is one stock code in upper case, because `85123a` and `85123A` name the same product. Its label is the code, so a typo in a description never splits a product. Its display name is the code's most frequent description, with ties going to the smaller string.

## Cleaning

| Step | Rows removed | Rows left | Invoices left |
|---|---|---|---|
| Raw CSV | | 1,067,371 | 53,628 |
| Exact duplicate rows | 34,335 | 1,033,036 | 53,628 |
| Cancellation invoices (`C`, returns) | 19,104 | 1,013,932 | 45,336 |
| Bad-debt adjustments (`A`) | 6 | 1,013,926 | 45,330 |
| Quantity of zero or less | 3,393 | 1,010,533 | 41,937 |
| Price of zero or less | 2,621 | 1,007,912 | 40,076 |
| Non-product codes | 4,555 | 1,003,357 | 39,516 |

UCI's two yearly sheets both hold 1 to 9 December 2010, which accounts for 22,844 of the duplicates. Duplicates never change a basket, because repeated items collapse. A cancellation is a separate `C` invoice that reverses an earlier sale, so dropping it leaves the original basket as the customer bought it.

Rows with quantity or price of zero or less are stock notes such as "check" or "damaged", not sales. They remove 5,254 invoices made only of such notes, and 380 codes that never sold. The non-product list in `MarketBasket.jl` drops postage, carriage, manual entries, discounts, samples, fees, adjustments, test items, and gift vouchers. Postage and carriage appear on 8.8% of the invoices left before that step, so they would form rules with any popular product. The step removes 560 invoices that held only such codes.

Rows without a customer ID stay, because a receipt is a basket whoever paid; 2,922 kept invoices have none.

The result is 39,516 baskets over 4,725 products. Widths have a median of 15, a 90th percentile of 51, and a maximum of 1,106 for wholesale orders, with a mean of 25.1. 92% of baskets come from the United Kingdom.

## Derive and check rules

```sh
julia --startup-file=no --project=. applications/market_basket/analyze.jl
```

The script mines the baskets with `mine` at minsup 0.01, so every pattern rests on at least 396 receipts, and keeps rules with confidence of at least 0.5. `rules.jl` enumerates every split of each frequent itemset into a nonempty antecedent X and consequent Y. The miner already applied minsup to X ∪ Y. Measures follow [docs/interface.md](../../docs/interface.md#association-rules) and are exact fractions. The minconf test uses the identity confidence ≥ minconf exactly when support(X ∪ Y) ≥ ⌈minconf · support(X)⌉, computed by `support_threshold`. Comparing with the `Float64` value 0.1 would drop a rule whose confidence is exactly one tenth.

Rules rank by lift, then confidence, then support, then item IDs. Mirrored rules X ⇒ Y and Y ⇒ X always share a lift, so the higher-confidence direction ranks first. `top_rules` reports how many rules outside the top 10 tie with the tenth. A single frequent itemset with m items yields up to 2^m − 2 rules, so `top_rule_groups` also lists the best rule of each of the first ten distinct product groups.

The script writes to `results/raw/market_basket/`, which Git ignores, in about two and a half minutes:

- `rules.tsv`, `top_rules.tsv`, `top_groups.tsv`: ranked rules with labels, IDs, support count, relative support, confidence, and lift.
- `sensitivity.tsv`: for minsup 0.0075, 0.01, and 0.015 and minconf 0.4, 0.5, and 0.6, the rule count, and the rank of each top group's rule.
- `stability.tsv`: each top group recounted in each year (split at 2010-12-01) and without baskets above the 99th percentile of width. `measure_rule` recounts the supports directly; mining a subset again at the same relative minsup would drop patterns just under the smaller threshold.
- `rare_groups.tsv`: the top groups at minsup 0.005, recounted per year, for comparing rare high-lift patterns with the base ones.
- `summary.toml`: input SHA-256, code revision, thresholds, and counts.

[docs/market-basket-rules-2026-10-29.md](../../docs/market-basket-rules-2026-10-29.md) records the results and their checks against SPMF.

Rule tests use `GROCERY_RULES` in `tests/fixtures.jl` and compare every rule on 60 seeded random databases with a direct count. `RECEIPT_CASE` and [data/toy/receipts.csv](../../data/toy/receipts.csv) check the cleaning. Final rules come only from the team's validated miner, never from fixtures.
