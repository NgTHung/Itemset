# Report figures

Each figure here is a copy of a plot in `results/figures/`, which Git ignores. This file names the raw run behind each one and the command that regenerates it.

| Figure | Raw run | Regenerate |
|---|---|---|
| `scalability.pdf` | `results/raw/bbq-scalability-cli-20261119T140526Z`, archive SHA-256 `55340c7242bce9df9bba262d6941fd66f94601cc8782838205b540b1babd0abe` | See [the scalability record](../../bbq-scalability-runtime-2026-11-19.md#reproduce) |
| `output-size.pdf` | `results/raw/bbq-all-variants-cli-5repeat-20261117T041922Z` | See [the output-size record](../../output-size-2026-11-19.md#reproduce) |
| `en/scalability.pdf` | Same run as `scalability.pdf` | The same commands with `--out $OUT` and no `--language vi`, which write `$OUT/scalability.pdf` |
| `en/output-size.pdf` | Same run as `output-size.pdf` | The same commands with `--out $OUT` and no `--language vi`, which write `$OUT/output-size.pdf` |
| `correctness-grid.pdf` | `results/raw/bbq-all-variants-cli-5repeat-20261117T041922Z` | See [the report README](../README.md#tạo-lại-biểu-đồ-độ-đúng-và-bảng-bộ-nhớ) |
| `en/correctness-grid.pdf` | Same run as `correctness-grid.pdf` | The same command without `--language vi` |
| `runtime-curves.png` | `results/raw/bbq-all-variants-cli-5repeat-20261117T041922Z` | See [the runtime record](../../runtime-curves-2026-11-17.md#reproduce) |
| `width-curves.png` | `results/raw/bbq-width-profile-20261127T044121Z` | See [the width and profile record](../../bbq-width-profile-2026-11-27.md#reproduce) |

The English report, `main-en.tex`, uses the `en/` copies.
