# Writing Guide

This guide covers Itemset documentation, docstrings, and code comments. It does not cover the Vietnamese report in `docs/report/`, which follows the course brief in `docs/assignment.md`. Each document answers one reader question. You decide which question before you write, and the answer decides what belongs on the page and what goes somewhere else.

## Start with the problem

Open with the problem the thing solves, then describe how it solves it. Do not open with project status, task IDs, or what changed recently.

The opening paragraph is two to four sentences. It says what the thing is, who uses it, and which problem it removes for them.

Weak opening:

> This is the project setup, not a completed miner. `mine` deliberately fails until DAT-8 is implemented.

Strong opening:

> `ItemsetMining` finds every frequent itemset in a transaction database with Eclat. The market basket and image-pattern applications call one function, `mine`, so both mine with the same validated code and compare results on equal terms.

## Pick the document type

Each type has one job. Status, history, and plans belong in the types built for them.

| Type | Answers | Contains | Never contains |
|---|---|---|---|
| Root README | What is Itemset and how do I run it? | Purpose, team, layout, install and run commands, Colab and data links, latest dated test output | Task IDs, open-work lists, change history |
| Contract (`docs/interface.md`) | What must every caller and variant rely on? | Present-tense rules for input, thresholds, and output, with the reason for each rule | Review status, task progress, "will" statements |
| Protocol (`experiments/README.md`, `tools/spmf/README.md`) | How is evidence produced so others can repeat it? | Steps, recorded fields, timing boundaries, tools and versions | Results, owner progress |
| Owner brief (`applications/*/README.md`) | What must this workstream deliver? | Scope, inputs, deliverables, owner, reviewer, linked Linear issues | Results, contract rules copied from `interface.md` |
| Dated record (`docs/setup-validation.md`, `docs/project-plan.md`) | What did we find or intend on a given date? | Date, environment, commands, measurements, task IDs | Edits that track later state |
| Docstring | How do I call this and what does it guarantee? | Signature, contract, edge cases, what throws | Task IDs, implementation history |
| Linear issue | What work remains and when is it done? | Scope, criteria, status | Nothing restricted |

Status lives in Linear. Other documents link there instead of restating it. When a dated record goes stale, write a new dated section or file instead of editing the old one.

## Describe what is, not what changed

Contracts, protocols, READMEs, and docstrings describe the current system in the present tense. Ask of each sentence: will this still be true, and still worth reading, after the next merge? If not, it belongs in a commit message, a Linear issue, or a dated record.

Drop these words from those documents: now, still, currently, yet, until, no longer, at this stage, has been, was removed, former, legacy, new.

| Instead of | Write |
|---|---|
| Today both variants raise an explicit unimplemented error. | Both variants return the same `SupportMap` for the same input. |
| The notebook now targets Colab's native Julia kernel. | The notebook runs on Colab's native Julia kernel. |

If a feature is missing, the reference doc omits it and the Linear issue tracks it. Do not describe planned behavior as if it exists.

## Explain why before what

Readers can read the code for what it does. Give them the reason the code cannot give: the constraint, the cost, or the failure it prevents.

Weak: `support_threshold` parses `minsup` as a `BigFloat`.
Strong: `support_threshold` parses the decimal text of `minsup`, because `0.07 * 100` is `7.000000000000001` in `Float64` and would raise the threshold from 7 to 8 transactions.

Put numbers behind performance and reliability claims. "Mines Chess at minsup 0.6 in N s with M MB peak RSS", with the measured values filled in, is useful. "Fast and memory efficient" is not. Every number names its dataset, threshold, variant, machine, and Julia version, or links to the raw run in `results/raw/`.

## Keep one home per fact

Each fact has one owning document. Other documents link to it.

- The course requirements live in `docs/assignment.md`.
- The transaction, threshold, and output contract lives in `docs/interface.md` and the `mine` docstring.
- The benchmark measurement protocol lives in `experiments/README.md`, and the CSV fields in `experiments/result-fields.txt`.
- The SPMF reference procedure lives in `tools/spmf/README.md`.
- The fixed seed lives in `DEFAULT_SEED` in `src/structures.jl`.
- Install and run commands live in the root README.
- Task status and ownership live in Linear.

Before you add a paragraph, search for the fact. If it exists, link to it or move it.

## Structure

Use headings that match the reader's task, such as "Install and verify" or "Compare with SPMF". Keep titles short.

Use prose for reasoning and cause and effect. Use lists for parallel, discrete items such as options, commands, or recorded fields. A list item that needs a "because" clause belongs in prose.

Use a table when the reader compares items across the same attributes, such as datasets or variants.

Use a code example when it replaces a paragraph of explanation. Examples in Markdown show the smallest call that works, and every command runs from the repository root.

Do not use ASCII or Mermaid diagrams. Do not use bold or italic in running prose.

## Length

A root README fits on about two screens, around 120 lines, because the brief requires it to carry setup, usage, test output, and submission links. Other READMEs stay under 60 lines. If a section explains a subsystem in more than five paragraphs, it deserves its own document under `docs/`.

## Sentences

Write short sentences in active voice. Address the reader as "you". State facts plainly and let data carry the weight.

Avoid these constructions:

- Em dashes. Use commas or periods.
- "Not only X, but also Y".
- Metaphors and clichés.
- Generalizations without an example or a number.
- Setup phrases such as "in conclusion" or "it is worth noting".
- Adjectives and adverbs that add no fact, such as fast, simple, clean, robust, powerful, or seamless, unless you measure them.
- Emojis and hashtags.

Avoid these words and their relatives: comprehensive, delve, utilize, harness, realm, tapestry, unlock, revolutionary, groundbreaking, remarkable, pivotal.

## Code comments

Docstrings and comments follow the documentation rules in `AGENTS.md`. They explain why, stay short, and never narrate refactor history or cite task IDs.

## Review checklist

Before you commit a document, check that:

1. The first paragraph states the problem and fits in four sentences.
2. The document matches one type in the table and contains nothing from its "Never contains" column.
3. No sentence depends on "now", "until", or a task ID to make sense, unless the document is a dated record or an owner brief.
4. Every performance or reliability claim has a number or a link to a raw run.
5. Every fact that exists elsewhere is a link, not a copy.
