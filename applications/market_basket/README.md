# Market Basket Analysis — Thien

Start with DAT-10; final pipeline and rules are DAT-14. Use real data with meaningful
product labels and public provenance/license, deterministic receipt grouping,
documented returns/missing-value/duplicate handling, and reversible integer IDs.
Keep raw inputs in `data/raw/`, not Git; record checksums and Hugging Face/Kaggle links.

Develop rule formulas against `data/toy/baskets.expected.txt` now; final itemsets
must come from own validated `ItemsetMining.mine`. Supply top-10 lift rules with
support/confidence and business interpretation, threshold sensitivity, and limits.
Supply the runnable notebook module and report text; Hung reviews this work.
