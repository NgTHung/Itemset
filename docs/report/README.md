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

## Regenerate the figures

[figures/README.md](figures/README.md) names the raw run behind every figure and measured table, and the commands that redraw them.
