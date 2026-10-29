# Market basket rules, 2026-10-29

The market basket application needs association rules that come from the team's own Eclat, rank by lift with exact measures, and hold up when the thresholds or the data change. This record gives the run, its checks, and the tables the report cites.

## Run

Windows 11, AMD Ryzen 7 H 260, Julia 1.13.2, main at `9b8e563` with the uncommitted rule code. Input SHA-256 `32569a66…` (Online Retail II, 39,516 cleaned baskets, 4,725 products).

```sh
julia --startup-file=no --project=. applications/market_basket/prepare.jl
julia --startup-file=no --project=. applications/market_basket/analyze.jl
```

At minsup 0.01 (396 baskets) Eclat finds 1,355 frequent itemsets, and minconf 0.5 keeps 455 of the 1,804 rules they yield. Every rule has lift above 1.4.

## Checks

- SPMF v2.66 Eclat on the same baskets, written without labels, gives the same 1,355 itemsets: `tools/spmf/compare.jl` reports a 100% exact-map match.
- A separate script derived the rules from SPMF's map with its own enumeration and found the same 455 rules. No confidence lies within 0.0001 of 0.5, so the threshold decides no rule by rounding.
- The support, relative support, confidence, and lift of each top-10 rule match a direct count over the baskets.

## Top 10 rules

| Rank | Rule | Support | Rel. support | Confidence | Lift |
|---|---|---|---|---|---|
| 1 | Bedroom + Kitchen ⇒ Livingroom | 409 | 0.0104 | 0.7343 | 51.45 |
| 2 | Livingroom ⇒ Bedroom + Kitchen | 409 | 0.0104 | 0.7252 | 51.45 |
| 3 | Livingroom + Kitchen ⇒ Bedroom | 409 | 0.0104 | 0.8629 | 48.50 |
| 4 | Bedroom ⇒ Livingroom + Kitchen | 409 | 0.0104 | 0.5818 | 48.50 |
| 5 | Bedroom + Livingroom ⇒ Kitchen | 409 | 0.0104 | 0.8872 | 47.25 |
| 6 | Kitchen ⇒ Bedroom + Livingroom | 409 | 0.0104 | 0.5512 | 47.25 |
| 7 | Livingroom ⇒ Bedroom | 461 | 0.0117 | 0.8174 | 45.95 |
| 8 | Bedroom ⇒ Livingroom | 461 | 0.0117 | 0.6558 | 45.95 |
| 9 | Livingroom ⇒ Kitchen | 474 | 0.0120 | 0.8404 | 44.76 |
| 10 | Kitchen ⇒ Livingroom | 474 | 0.0120 | 0.6388 | 44.76 |

Every item is a POPPY'S PLAYHOUSE room set. The ten rules are six splits of one three-item set and two mirrored pairs. No rule outside the top 10 ties with rank 10.

## Top 10 product groups

| Group | Best rule | Support | Confidence | Lift | Lift year 1 | Lift year 2 | Lift without large |
|---|---|---|---|---|---|---|---|
| 1 | Poppy's Playhouse Bedroom + Kitchen ⇒ Livingroom | 409 | 0.734 | 51.4 | 63.4 | 43.1 | 57.4 |
| 2 | Poppy's Playhouse Livingroom ⇒ Bedroom | 461 | 0.817 | 45.9 | 60.1 | 37.1 | 52.3 |
| 3 | Poppy's Playhouse Livingroom ⇒ Kitchen | 474 | 0.840 | 44.8 | 58.0 | 36.2 | 50.3 |
| 4 | Poppy's Playhouse Bedroom ⇒ Kitchen | 557 | 0.792 | 42.2 | 56.2 | 33.6 | 48.4 |
| 5 | Wooden Tree ⇒ Wooden Star Christmas Scandinavian | 437 | 0.790 | 40.7 | 56.0 | 32.1 | 46.6 |
| 6 | Small Marshmallows Pink Bowl ⇒ Small Dolly Mix Orange Bowl | 457 | 0.744 | 40.1 | 62.0 | 29.3 | 48.4 |
| 7 | Set/10 Blue Spotty ⇒ Pink Polkadot Party Candles | 488 | 0.776 | 38.0 | 33.2 | 44.3 | 40.3 |
| 8 | Key Fob Garage Design ⇒ Key Fob Back Door | 402 | 0.646 | 37.1 | 33.8 | 41.1 | 42.4 |
| 9 | Feltcraft Princess Lola ⇒ Princess Charlotte Doll | 401 | 0.620 | 35.8 | 52.2 | 27.2 | 39.1 |
| 10 | Pink Polkadot Cup ⇒ Blue Polkadot Cup | 521 | 0.694 | 35.6 | 31.3 | 41.2 | 39.3 |

Year 1 runs from 2009-12-01 to 2010-11-30 (19,743 baskets), year 2 from 2010-12-01 (19,773 baskets). "Without large" drops the 393 baskets with more than 197 items, the 99th percentile. Each group's rule keeps a lift above 27 and a confidence between 0.62 and 0.90 in every subset, and each year holds at least 108 of its baskets.

## Thresholds

Lift and confidence are properties of the data, so thresholds only decide which rules pass and what they rank against.

| minsup (count) | minconf 0.4 | minconf 0.5 | minconf 0.6 | Top groups present | Ranks of the ten group rules at minconf 0.5 |
|---|---|---|---|---|---|
| 0.0075 (297) | 1,799 rules | 1,181 | 698 | 10 of 10 | 32 to 108 |
| 0.01 (396) | 710 | 455 | 221 | 10 of 10 | 1 to 23 |
| 0.015 (593) | 186 | 112 | 44 | 0 of 10 | |

Raising minconf to 0.6 removes the two top-10 rules with confidence 0.58 and 0.55 and keeps every group. Lowering minsup keeps every rule but admits rarer rules with higher lift, which push the ten groups down to ranks 32 to 108. Raising minsup to 0.015 removes all ten groups, because their supports of 401 to 557 baskets fall below 593.

## Rare high-lift patterns

At minsup 0.005 (198 baskets) the top groups change completely. Nine of the ten are sets of HERB MARKER garden labels with lift near 150. Year 1 holds only 7 to 11 baskets of each, which makes its lift of 1,480 to 1,795 meaningless, and year 2 holds 193 to 221. The other is a children's garden trowel and fork, with 156 baskets in year 1 and 57 in year 2. These rules rest on half the receipts of the base groups and mostly on one season, so the report treats them as leads, not findings.
