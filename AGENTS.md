# Itemset

Itemset is a Julia package, `ItemsetMining`, that mines frequent itemsets with Eclat (Zaki, IEEE TKDE 2000) for the HCMUS Data Mining course project. Two applications consume it: market basket analysis and image-pattern mining. The original brief, in Vietnamese, is `docs/assignment.md`; read it before you change scope, deliverables, or report content.

The package is a WIP. Proposed sweeping changes that improve long-term maintainability are encouraged. Read `README.md` for the layout and `docs/interface.md` for the shared transaction and mining contract before you assume an API.

## Core Priority

1. Correctness. Every variant must return the exact same `SupportMap` as an independent SPMF run. A fast miner with one wrong support is worthless for grading and for both applications.
2. Performance. The brief grades Julia performance anti-patterns, and the benchmarks (Chess, Mushroom, Retail, T10I4D100K) reach low minsup values.
3. Reproducibility. Every result must regenerate from the repository, its pinned environment, and `DEFAULT_SEED` (42).

If a tradeoff must be made, choose correctness and robustness over short-term convenience.

## Academic integrity

- Implement Eclat from the paper. Never import a frequent-itemset-mining library and never copy SPMF or other repository source.
- Each author must be able to explain every submitted line at the oral defense. Prefer readable code over clever code, and keep the paper's terminology (tidset, equivalence class, prefix) in names.
- Keep authorship history attributable: small commits, one concern each.
- Code review between team members is a human task. Do not mark a review as done for a person.

## Commands

Run from the repository root. Julia 1.13.2 is pinned by `.julia-version`; CI also covers 1.12.6 on Ubuntu and Windows.

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
julia --startup-file=no --project=. scripts/check_setup.jl
julia --startup-file=no --project=. test/runtests.jl
julia --startup-file=no --project=. demo.jl --check-input data/toy/baskets.txt
```

## Maintainability

Long-term maintainability is a core priority. Before you add functionality, check whether shared logic belongs in `structures.jl`, `utils.jl`, or a new module. Duplicated logic across files is a code smell. Don't be afraid to change existing code, and don't solve a problem with local logic that another caller will need.

Applications and experiments use only the public `mine`, `read_transactions`, `write_itemsets`, and `support_threshold` API. Never expose tidsets or other algorithm internals to them. If an application needs more, extend the contract in `docs/interface.md` first.

Avoid large files:

- Prefer adding a new file over growing an existing one.
- Target Julia files under 700 lines.
- If a file exceeds roughly 1000 lines, add new functionality in a new file unless there is a strong documented reason not to.

## Development

This is a TDD project. Write the test first, watch it fail, then implement. Read and copy the style of neighboring tests when you add cases. All changes must be tested.

- Put tests under `tests/`, never inline in `src/`. Group them with nested `@testset` blocks as `tests/runtests.jl` does.
- Add a new toy database only with its hand-derived `*.expected.txt` file and an entry in `tests/fixtures.jl`.
- Hand-derived fixtures are development aids, not proof of correctness. Miner correctness needs complete-map comparison across all toy databases and against SPMF output (see `tools/spmf/README.md`).
- Both variants, `:baseline` and `:optimized`, must return equal maps before you compare their performance.

### Change size

Unless the change is mechanical, keep the total diff under 1000 changed lines, and under 700 for complex logic. If a change is larger, split it into reviewable stages and land the smallest coherent stage first. Base the split on the actual diff, dependencies, and call sites.

### Julia rules

- Keep hot code type-stable. Check new mining code with `@code_warntype` or `Test.@inferred`.
- Never use untyped non-`const` globals. Use `const` or pass values as arguments.
- Use concrete element types in containers and struct fields on hot paths, such as `Vector{Int}`, not `Vector{Any}` or `Vector{Integer}`.
- Use `@inbounds` and `@simd` only where a test or an explicit bounds check proves the indices valid. A comment states that reason.
- Prefer non-allocating loops and in-place `!` functions in the mining inner loop. Measure allocations before and after an optimization and record the numbers.
- Throw `ArgumentError` for invalid input and include the offending value or line number. Never return `nothing` or an empty map to hide a failure, and never silently fall back to another variant.
- Validate all output before writing any bytes, as `write_itemsets` does.
- Pass a seeded RNG (`DEFAULT_SEED`) to every stochastic step. Never use the global RNG.
- Only Julia standard libraries are approved. A new dependency needs team approval first; commit `Project.toml` and the regenerated `Manifest.toml` together.
- Do not use comments to divide sections of code.

### Documentation rules

Core principle: explain why, not what. Keep comments as short as possible. One sentence of rationale beats a paragraph that restates code.

Docstrings (`"""`):

- Document every exported function and type with a docstring placed directly above it.
- Start with the signature for functions with keywords or a return type, as `mine` does.
- State the contract the caller relies on: units, edge cases, and what throws.
- Docstrings render as Markdown, so code spans, fenced examples, and lists are fine where they aid the rendered output. Keep it minimal.

Inline comments (`#`):

- Delete comments that restate obvious code.
- Explain why for decisions, such as the `BigFloat` parse in `support_threshold`.
- Use one sentence when possible. Only expand for truly non-obvious consequences.
- Cite the paper section or equation when code follows a specific step of Zaki's algorithm.

Error handling comments explain the strategy and recovery, not just "throw and stop".

Never use:

- Placeholder comments ("for now", "TODO: extract this later").
- Markdown formatting such as `**bold**` in plain `#` comments.
- ASCII diagrams. Put those in `docs/` if needed.
- Section divider comments (`# ========== Section ==========`).
- Comments explaining removed code during refactors.
- Task IDs in code or docstrings. Link work in commits instead.

## Writing Style

Read `docs/WRITING_GUIDE.md` before you write or edit any Markdown document. It owns the full rules and the review checklist. The rules agents break most often:

- Open with the problem the thing solves, not with project status or task IDs.
- Describe the system as it is, in the present tense. Keep "now", "still", "no longer", "until", and task IDs out of reference docs.
- Put status in Linear, history in commits and dated records. Link to them instead of restating them.
- Give each fact one home and link to it.
- Explain why before what, and back performance claims with numbers.
- Use short, active sentences. No em dashes, no filler adjectives, no bold in prose.

The report under `docs/report/` follows the brief's rules instead: Vietnamese prose, English technical terms kept on first use with a gloss, captioned and referenced figures and tables, and every formula variable explained.

## Task Tracking

Work is tracked in Linear project as `DAT-*` issues. Use the Linear MCP tools to read an issue before you work on it and to update its status or comment on it afterwards. `docs/project-plan.md` records the dated plan and ownership as of project setup; Linear is the current source of truth.

Use a task branch named after the issue, such as `dat-8-eclat-baseline`. Commit each step of a plan with a Conventional Commit message (`feat:`, `fix:`, `test:`, `docs:`, `chore:`) and reference the issue in the body.

Keep large data, credentials, SPMF JARs, Julia runtimes, LaTeX build output, and generated runs out of Git. `.gitignore` already covers `data/benchmark/`, `data/raw/`, `results/raw/`, `results/figures/`, and `tools/spmf/*.jar`.
