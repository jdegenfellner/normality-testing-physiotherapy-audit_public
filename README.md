# Normality Testing in Physiotherapy Research — a full-text meta-research audit

A full-text audit of how physiotherapy and rehabilitation papers apply normality
tests (Shapiro–Wilk, Kolmogorov–Smirnov, …): to the **residuals** of the model
(correct) or to the **raw data** (incorrect). It builds on the residuals-versus-
raw-data criterion of Midway & White (2025, *Royal Society Open Science*), who
reported the same error in 70% of ecology and 90% of biology papers.

**Main result.** The search returned 1,173 articles; after excluding 16
online-first records dated 2025, **1,157 articles** from **16 journals**
(2015–2024) remained, of which 1,155 could be definitively coded. The rule-based
classifier coded **96.8%** as applying the normality test to the raw data rather
than the residuals; correcting for the classifier's measured labelling error
against a hand-coded 100-paper validation sample gives a conservative prevalence
of **89.0% (95% CI 81.4–95.2%)** (90.4% among the papers whose target could be
determined). Only 1.0%
tested the residuals. A companion simulation (10,000 reps/cell) shows the power
cost of the error is small (about 2 percentage points, and ≤3 even under unequal
variances); the eventual choice of test matters far more.

This repository holds the data and code only. A link to the published article
will be added on publication.

## Pipeline

| Script | Purpose |
|---|---|
| `fetch_corpus.py` | Europe PMC full-text search across the 14 indexed journals |
| `fetch_fulltext.py` | PubMed Central full-text retrieval + passage extraction |
| `fetch_elsevier.py` | Elsevier full-text API (the two ScienceDirect journals) |
| `fetch_render_pdf.py` | rendered-PDF recovery for articles outside the PMC open-access subset |
| `classify.py` | deterministic, rule-based coding (residuals / per-group / raw / mixed / unclear) |
| `llm_classify.py` | independent LLM coding of the same passages (local Qwen2.5-32B-Instruct, MLX, greedy) — cross-check of the rule-based classifier |
| `llm_compare.py` | LLM vs rule-based (whole corpus) and LLM vs human (validation sample, as an independent second coder) |
| `validation_analyze.py` | classifier vs. human coding: agreement, Gwet's AC1, and the design-based misclassification-corrected prevalence |
| `run_simulation.R` | power simulation of four decision workflows (seed 2025), incl. a heteroscedastic (unequal-variance) scenario |
| `analysis.R` | figures and tables |

Self-contained sanity checks of the paper's statistical claims:
`equivalence_sanity_check.R` (t-test/ANOVA/paired-t are linear models),
`paired_normality_demo.R` (paired-t assumption is on the differences),
`normality_least_consequential_demo.R` (normality is the least consequential
linear-model assumption), `exact_normal_mean_demo.R` (the sample mean / mean
difference of normal data is exactly normal at any n),
`ttest_vs_mannwhitney_demo.R` (the t-test and Mann-Whitney test the same
hypothesis only under a location shift, and can point in opposite directions
when shapes differ), `residuals_pergroup_equivalence_demo.R` (per-group
normality testing equals testing the residuals for balanced designs, and both
are immune to the between-group mean shift that breaks pooled-raw testing).

The classifier was validated against the author's manual coding of a stratified
100-paper sample: corpus-weighted agreement **90.7%**, Gwet's AC1 = **0.89**
("almost perfect"; we report AC1 rather than Cohen's κ, which is deflated by the
extreme class imbalance). The prevalence above is corrected for the measured
classification error with a design-based estimator and a bootstrap confidence
interval.

As an independent cross-check, the whole corpus was re-coded by a local
open-weight LLM (Qwen2.5-32B-Instruct, MLX, greedy). It agreed with the
rule-based classifier on 92% of papers, independently reproduced the
near-universal error (92% of definitive papers), and — used as a second coder on
the validation sample — agreed with the human gold standard **better** than the
rule-based classifier did (corpus-weighted 96.0% / AC1 0.96 vs 90.7% / 0.89).

## Data availability & licensing

Open data are provided where licensing permits:

* `passages_public.json` — extracted normality passages, **open-access content
  only**; for non-open-licensed content the passage text is blanked (codes are
  still provided).
* `coded_auto.csv` — per-paper codes for all 1,157 articles (the normality
  sentence is blanked for non-open-licensed content).
* `validation_human_codes.csv` — the 100-paper human validation sample with the
  author's manual codes (identifiers + codes only, no sentence text).
* `corpus_raw.json`, `elsevier_corpus.json` — article metadata (DOIs, etc.).
* `simulation_results.csv`, `table*.csv`, figures.

**Not included** (excluded via `.gitignore`): the Elsevier API key; the full-text
passages for the two Elsevier journals and for articles recovered from
non–open-access sources. These are governed by the Elsevier API / text-and-data-
mining terms and are not redistributable. They can be regenerated by running the
scripts with your own Elsevier API key and institutional access.

## Reproduce

```bash
# 1. corpus + open-access full text
python3 fetch_corpus.py && python3 fetch_fulltext.py
# 2. the two ScienceDirect journals (needs an Elsevier API key + institutional access)
ELS_KEY=<your-key> python3 fetch_elsevier.py
# 3. recover articles outside the PMC open-access subset
python3 fetch_render_pdf.py
# 4. classify, validate, simulate, analyse
python3 classify.py && python3 validation_analyze.py
Rscript run_simulation.R && Rscript analysis.R
# 5. the estimand-explainer figure (reads estimand_figure_data.json from step 4)
Rscript estimand_fig.R
```

Requires Python 3 (standard library, plus `openpyxl` for the validation) with
`pdftotext` (poppler) on PATH, and R 4.6 with the tidyverse.
