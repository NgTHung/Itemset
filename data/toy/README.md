# Hand-verified development fixtures

These are original tiny fixtures, not SPMF reference runs. Expected files allow
application work before Eclat is ready; do not use them as final application results.

- `baskets.txt`: N=4, minsup=0.5 (count 2). Each singleton occurs 3 times;
  each pair 2 times; the triple only once. Expected output in `baskets.expected.txt`.
- `duplicates.txt`: N=3, count 2. `{1,2}` occurs twice and `{2}` three times.
  Duplicate items collapse; duplicate baskets count independently.
- `disjoint.txt`: N=3, count 2. No frequent itemsets. Item 0 is intentional.
- `dense.txt`: N=2, count 2. All seven nonempty subsets of `{1,2,3}` have support 2.
- `empty.txt`: N=0, count 1. No frequent itemsets.

`tests/fixtures.jl` holds the same five expected maps for future miner tests.
The setup suite verifies fixture integrity and I/O; it cannot validate an unwritten miner.
