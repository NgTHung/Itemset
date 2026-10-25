# SPMF toy validation, 25 October 2026

The [24 October record](spmf-toy-validation-2026-10-24.md) kept its raw SPMF outputs on the run host, so nobody else could check them. This run regenerated the outputs and committed them to [data/toy/spmf](../data/toy/README.md#spmf-reference-outputs), where the test suite compares every Eclat variant with them. It also adds the `duplicates` and `disjoint` databases, so seven databases and eight thresholds are covered.

## Environment

- Windows 11 x86-64; Julia 1.13.2; Temurin Java 25.0.4.1+1.
- SPMF JAR SHA-256 `4aa468384693b2016b457ea310a08cc24aa83abd42d3169ad65b9027778dfe6a`, the v2.66 checksum in [tools/spmf](../tools/spmf/README.md). Eclat prints `ECLAT v2.65` in its statistics.
- Outputs committed in `6740e6a` on the DAT-9 branch, generated with `julia --startup-file=no --project=. tools/spmf/toy_reference.jl .tools/jdk-25.0.4.1+1-jre/bin/java`.

## Results

Each fraction gives the same count in SPMF's `Float64` arithmetic and in `support_threshold`. "Baseline" compares SPMF with `mine(...; variant=:baseline)`, and "Fixture" compares SPMF with the hand-derived `*.expected.txt` file.

| Database | Input SHA-256 | N | minsup | Count | Itemsets | Baseline | Fixture |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baskets | `bf15a3eb98335bcf82b0020856f38cbb23e1b89520bbdcc5d74517c5aae664bb` | 4 | 0.5 | 2 | 6 | 100% | 100% |
| duplicates | `0b2496cdf476514181429c05015b39208fcc0f2d427f200cb80c0acc00492ce9` | 3 | 0.6 | 2 | 3 | 100% | 100% |
| disjoint | `b78a1987bcbdc0903ba6ba29ee3e1f4e7cc1ca868a60889beb141e26e06cb005` | 3 | 0.6 | 2 | 0 | 100% | 100% |
| dense | `8c50aafc7943180e0aee25174fe05b60d5584f927593060974a7d2c151a02ef6` | 2 | 1.0 | 2 | 7 | 100% | 100% |
| boundary | `18503a79c0d8c6203266dd46af34735b42499e5db64231bc0d6ee49368a47951` | 4 | 0.5 | 2 | 2 | 100% | 100% |
| boundary | same input | 4 | 0.25 | 1 | 4 | 100% | 100% |
| nested | `2c8ae27f22baa3eb7e90aebec6613efa04bacba82da7b2e06f5255f0c6c8974b` | 4 | 0.5 | 2 | 3 | 100% | 100% |
| groceries | `3fa8f2c833dfb0fae642b4c72e010d649a1ecd1b3fc9895c592589bd849b350f` | 5 | 0.4 | 2 | 5 | 100% | 100% |

`disjoint` has no frequent itemsets and no fixture file, so both comparisons are between empty maps. `empty.txt` is not covered, because SPMF rejects an empty input file. These results cover the baseline variant on small databases; they do not establish benchmark or optimized-variant correctness.
