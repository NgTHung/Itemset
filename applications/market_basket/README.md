# Market basket analysis

A retailer wants to know which products customers buy together, so it can place, bundle, or promote them. This workstream turns real receipts into transactions, mines them with `ItemsetMining.mine`, and reports the association rules with the highest lift.

## Data

Use a public retail dataset with meaningful product labels and a known license, linked from Hugging Face or Kaggle. Keep the raw files in [data/raw](../../data/raw/README.md). Record:

- source and mirror URLs, license, and SHA-256,
- how rows group into receipts, deterministically,
- how returns, missing values, and duplicate rows are handled,
- the reversible mapping between product labels and integer IDs.

## Deliverables

- Top-10 rules by lift, with support and confidence, labelled with product names and a business interpretation. Rule measures follow [docs/interface.md](../../docs/interface.md#association-rules).
- Sensitivity of the rules to the support threshold.
- Limitations of the data and the method.
- A runnable notebook module and the Vietnamese report section.

Develop and test the rule code against `data/toy/baskets.expected.txt`. Final rules come only from the team's validated miner, never from fixtures.
