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

## Deliverables

- Top-10 rules by lift, with support and confidence, labelled with product names and a business interpretation. Rule measures follow [docs/interface.md](../../docs/interface.md#association-rules).
- Sensitivity of the rules to the support threshold.
- Limitations of the data and the method.
- A runnable notebook module and the Vietnamese report section.

Develop and test the rule code against `GROCERY_RULES` in `tests/fixtures.jl`, built from [data/toy/groceries.txt](../../data/toy/README.md). `RECEIPT_CASE` and [data/toy/receipts.csv](../../data/toy/receipts.csv) check the cleaning. Final rules come only from the team's validated miner, never from fixtures.
