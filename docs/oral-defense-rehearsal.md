# Oral-defense rehearsal

At the oral defense each member explains any line and any result of the project, not only their own part. A rehearsal that lets each person present once leaves the other two parts unpracticed, so this protocol gives every member the same time on their own part, on another member's part, and on a small Eclat example, and records what each person could not explain.

## Format

Three blocks, each with the same time per member. Use a timer and stop a speaker at the limit.

1. Own part. Hung presents the Eclat implementation, the optimizations, and scalability. Thien presents the market baskets, the runtime and width experiments, and the future optimizations. Phat presents the image application, the correctness check against SPMF, and peak memory. Each speaker uses only the report, the notebook, and saved evidence.
2. Another member's part. Each member explains one application or experiment they did not write, chosen by a draw the day before in which nobody draws their own part. The author then asks two questions and notes every point where the explanation was wrong or went around a step.
3. A small example by hand. Each member traces Eclat on `data/toy/baskets.txt` (four baskets, `minsup` count 2) on paper, without the report open, and then checks the trace against the trace table of the implementation chapter. A member who cannot reproduce which itemset is pruned and why repeats the block.

Record each weak area as one comment on the Linear issue DAT-27 with the topic, the member, the action, and the owner of the action. Do not mark a rehearsal complete for a member who did not take part.

## Topics each member must be able to explain

For each topic, the place to find the evidence and a question that tests understanding rather than recall.

| Topic | Where the evidence is | A question to ask |
|---|---|---|
| Support, confidence, and lift | the market-basket section of the report, `applications/market_basket/rules.jl`, and the hand-checked example in `tests/market_basket_rules.jl` | Why can a rule with high lift rest on very few baskets, and why do mirrored rules share a lift but not a confidence? |
| Depth-first search and pruning | the correctness section of the implementation chapter and `docs/eclat.md` | Why is an itemset whose tidset is below `minsup` never extended, and why does that lose no frequent itemset? |
| Perfect extensions | `docs/eclat-optimized.md` | When does adding an item leave a tidset unchanged, and why do all the subsets of those items share one support? |
| Tidset representations | `docs/eclat-optimized.md` and the optimization chapter | What does one join cost as a bitset and as a sorted list, and which data favors which? |
| Output explosion | the minsup runtime section of the report | Why does the number of frequent itemsets grow far faster on a dense database than on a sparse one, and what part of the time does output take? |
| Image encoding and its losses | the image section of the report and `applications/image_patterns/README.md` | What does the encoding discard (position, repeats within an image, patches far from every codebook center), and what can a frequent itemset not say about the picture? |
| Timing and memory method | the shared protocol subsection of the report and `experiments/README.md` | Why is the `process` scope used, what does it include, and why does a ratio between two programs of one session need a different noise level than a comparison across sessions? |
| Limits | the limits paragraphs of each section | Which claim of your own part would you withdraw first if a grader reran it on another machine? |

## Demo and fallback

The live demo runs the notebook `notebooks/demo.ipynb` on a small input: the toy baskets, the width pilot, or one market-basket cell. Keep saved evidence ready and label it as saved when it replaces a live run: the report figures in `docs/report/figures/`, the tables of the market-basket results, and the run records in `docs/`. Every member can start the demo and say which cell produced which figure.
