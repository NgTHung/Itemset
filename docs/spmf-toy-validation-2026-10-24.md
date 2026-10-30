# SPMF toy validation, 24 October 2026

A complete itemset map comparison checks supports that itemset counts cannot
detect. Five toy databases and two boundary thresholds were mined independently
with the SPMF Eclat executable, then compared with the Julia baseline and the
hand-derived fixtures. The raw outputs, logs, diffs, and exact rerun commands
are in `results/raw/spmf-toy-2026-10-24/` on the run host. The `commands.ps1`
script completed with exit code 0 when rerun after the outputs were checked.

## Environment and inputs

- Windows x86-64; Julia 1.13.2; Temurin Java 25.0.4.1+1.
- Git revision `50116e1dfb63ca3d5f88798af718b816d9a4f602` for the run.
  The DAT-9 commit `89a0431` has the identical source tree
  (`5af956324307d1db9886a6050de05c8957984389`).
- SPMF JAR downloaded from the official release page on 24 October 2026.
  The page listed release 2.67; the JAR manifest does not state a version, and
  Eclat printed `ECLAT v2.65`. JAR SHA-256:
  `4AA468384693B2016B457EA310A08CC24AA83ABD42D3169AD65B9027778DFE6A`.
- The run used absolute count thresholds in Julia and the equivalent percentages
  in SPMF. Every threshold is a ceiling over the transaction count `N`.

| Database | Input SHA-256 | N | Count | SPMF percent | Itemsets | Baseline match | Fixture match |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baskets | `BF15A3EB98335BCF82B0020856F38CBB23E1B89520BBDCC5D74517C5AAE664BB` | 4 | 2 | 50% | 6 | 100% | 100% |
| dense | `8C50AAFC7943180E0AEE25174FE05B60D5584F927593060974A7D2C151A02EF6` | 2 | 2 | 100% | 7 | 100% | 100% |
| groceries, numeric copy | `CC19FEE0CC7447BFCBCE0B6D370A343DD5A27C591EE1F8F63DC2F34D04F48928` | 5 | 2 | 40% | 5 | 100% | 100% |
| boundary | `18503A79C0D8C6203266DD46AF34735B42499E5DB64231BC0D6EE49368A47951` | 4 | 2 | 50% | 2 | 100% | 100% |
| boundary | same input | 4 | 1 | 25% | 4 | 100% | 100% |
| nested | `2C8AE27F22BAA3EB7E90AEBEC6613EFA04BACBA82DA7B2E06F5255F0C6C8974B` | 4 | 2 | 50% | 3 | 100% | 100% |

The source `groceries.txt` has SHA-256
`3FA8F2C833DFB0FAE642B4C72E010D649A1ECD1B3FC9895C592589BD849B350F`.
Its `@ITEM` metadata makes SPMF write labels instead of integer IDs. The run
used `read_transactions` and `write_transactions` to save the same five
transactions without labels before mining them in both programs.

## Checks

`test/runtests.jl` passed 565 of 565 tests on Julia 1.13.2. Every raw comparator
diff reported no missing, extra, duplicate, or support-mismatched itemsets.
The comparator command exited 1 for a deliberately wrong support and 2 for a
malformed support token; the saved diffs identify the affected itemset or line.
The [SPMF procedure](../tools/spmf/README.md) defines the match rate and how
to regenerate each output. These results cover the baseline variant on small
databases; they do not establish benchmark or optimized-variant correctness.
