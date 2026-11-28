# IEEE report

The course brief asks for a 10 to 15 page IEEE conference paper, not counting references and appendices, exported as `docs/Report.pdf`. `main.tex` is that paper. It is written in English, uses the IEEEtran conference class, and compiles with XeLaTeX. `docs/assignment.md` holds the brief's other rules: three chapters, captioned and referenced figures and tables, every formula variable explained, and the original paper plus at least three other references.

The LaTeX environment is separate from the Julia environment. It needs IEEEtran and fontspec.

## Build

Tectonic runs XeTeX, BibTeX, and every rerun in one command from this directory:

```sh
tectonic -X compile main.tex
```

With TeX Live or MiKTeX:

```sh
xelatex main.tex
bibtex main
xelatex main.tex
xelatex main.tex
```

## Ownership

Hung writes implementation, scalability, and output size. Thien writes market basket, runtime, width, and future work. Phat writes image patterns, correctness, and memory. Thien assembles sections that have evidence behind them and does not write for the whole team. Phat assembles the notebooks, and Hung checks the final repository.

## Regenerate the correctness grid and memory table

The correctness grid and the peak RSS table come from the timing run on the grading machine, `bbq-all-variants-cli-5repeat-20261117T041922Z`. The [run record](../runtime-curves-2026-11-17.md#reproduce) has the hash of the results folder and the commands that rerun it. Every run in it was checked in full against SPMF, and the plotting script refuses to draw a run that does not match. The peak RSS table is the median of the `peak_rss_bytes` column of `runs.csv` at the lowest minsup of each database.

```sh
RUN=results/raw/bbq-all-variants-cli-5repeat-20261117T041922Z
uv run --no-project --python 3.12 --with matplotlib==3.10.7 python scripts/plot_report_validation.py $RUN --out docs/report/figures
```

## Regenerate the runtime and width figures

The [runtime record](../runtime-curves-2026-11-17.md#reproduce) writes `results/figures/runtime/curves.csv`. From that file:

```sh
uv run --no-project --python 3.12 --with matplotlib==3.11.2 python scripts/plot_runtime_curves.py results/figures/runtime/curves.csv --out docs/report/figures
```

The [width record](../bbq-width-cli-2026-11-28.md#reproduce) has the command that draws `width-curves.png`, and the [image-pattern guide](../../applications/image_patterns/README.md#reproduce-the-sensitivity-study) has the commands for the sensitivity table and the Semeion contrast figure. [figures/README.md](figures/README.md) lists the raw run behind every figure.
