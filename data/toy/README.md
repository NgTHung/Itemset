# Toy fixtures

Each database here is small enough to mine by hand, so its expected output is known before any miner runs. Tests and application code use them to check I/O, rule logic, and rendering against exact maps. The expected files are hand-derived, not SPMF output, so they never stand in for application results or reference comparisons.

| File | N | Count threshold | Expected result |
|---|---|---|---|
| `baskets.txt` | 4 | 2 (minsup 0.5) | Each singleton has support 3, each pair 2. The triple occurs once and is not frequent. |
| `duplicates.txt` | 3 | 2 | `{1,2}` has support 2 and `{2}` support 3. Repeated items collapse; repeated baskets count separately. |
| `disjoint.txt` | 3 | 2 | No frequent itemsets. Item 0 is intentional. |
| `dense.txt` | 2 | 2 | All seven nonempty subsets of `{1,2,3}` have support 2. |
| `empty.txt` | 0 | 1 | No frequent itemsets. |
| `groceries.txt` | 5 | 2 (minsup 0.4) | Bread 4, butter 3, milk 3, bread and butter 3, bread and milk 2. Beer occurs once and is not frequent. |

Expected outputs are in the matching `*.expected.txt` files, and `tests/fixtures.jl` holds the same maps for the test suite. A test also checks every fixture map against a brute-force count of all itemsets, so a map that omits an itemset fails.

`groceries.txt` carries its labels in SPMF `@ITEM` lines, written by `write_transactions` from `GROCERY_ROWS`. `GROCERY_RULES` lists all four rules from its map with exact support, confidence, and lift. Confidences differ and lift falls on both sides of 1, so a swapped antecedent or a wrong denominator changes a value. Databases with no frequent itemsets have no expected file, because the expected output is empty.
