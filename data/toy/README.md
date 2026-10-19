# Toy fixtures

Each database here is small enough to mine by hand, so its expected output is known before any miner runs. Tests and application code use them to check I/O, rule logic, and rendering against exact maps. The expected files are hand-derived, not SPMF output, so they never stand in for application results or reference comparisons.

| File | N | Count threshold | Expected result |
|---|---|---|---|
| `baskets.txt` | 4 | 2 (minsup 0.5) | Each singleton has support 3, each pair 2. The triple occurs once and is not frequent. |
| `duplicates.txt` | 3 | 2 | `{1,2}` has support 2 and `{2}` support 3. Repeated items collapse; repeated baskets count separately. |
| `disjoint.txt` | 3 | 2 | No frequent itemsets. Item 0 is intentional. |
| `dense.txt` | 2 | 2 | All seven nonempty subsets of `{1,2,3}` have support 2. |
| `empty.txt` | 0 | 1 | No frequent itemsets. |

Expected outputs are in the matching `*.expected.txt` files, and `tests/fixtures.jl` holds the same five maps for the test suite. Databases with no frequent itemsets have no expected file, because the expected output is empty.
