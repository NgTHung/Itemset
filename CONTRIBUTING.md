# Working together

Use task branches such as `dat-8-eclat-baseline`, make small attributable commits,
and reference the relevant DAT issue in the change description. Do not copy mining
implementations from SPMF or other repositories. Explain how your code follows the
original paper and retain hand traces, raw evidence, and limitations.

Before handing off code, run the README setup/test commands and add focused tests
for changed behavior. A passing setup suite does not prove Eclat correctness.
Commit Project/Manifest updates together for approved dependency additions. Keep
large data, private credentials, JARs, runtimes, and generated runs out of Git.

Use `mine` through its shared contract; do not expose algorithm internals to
applications. Both variants must produce exact equal maps before comparisons.
Supply your own runnable notebook module and Vietnamese report section. Review
rotation: Hung -> Thien -> Phat -> Hung. Review remains a human team task.
