# Manual coding — instructions (100-paper validation sample)

Open `validation_coding_sheet.csv` (Excel/Numbers/LibreOffice). For each row, read
the `normality_sentences` and put ONE label in the `CODE` column. Do not look at
the classifier's output — code only from the sentence(s) shown.

The question for each paper: **what was the normality test applied to?**

## Codes

- **CORRECT** — applied to the model **residuals**
  (e.g. "residuals were checked for normality", "normality of the residuals").

- **ACCEPTABLE** — applied **separately within each group**
  (e.g. "tested separately for each group", "normality was verified in each
  group", "for men and women separately"). For a balanced two-group design this
  is equivalent to testing residuals.

- **INCORRECT** — applied to the **raw data / outcome / variables / distribution**,
  with no residual or per-group qualifier. This is the default when a paper just
  says it tested normality of "the data", "the variables", "the scores", "the
  outcome", or simply "the data were normally distributed". An unqualified
  "data were tested for normality using Shapiro–Wilk" is **INCORRECT**.

- **MIXED** — both a **residual (correct)** statement **and** an unqualified
  pooled statement occur in the same paper. (A per-group statement together with
  a pooled statement is **ACCEPTABLE**, not mixed — per-group dominates.)

- **UNCLEAR** — no determinable normality-test target. Use this when a normality
  test is mentioned but its target cannot be determined, **or** when the matched
  "normal"/"distribution" wording is not actually a model-assumption check
  (e.g. a Gaussian filter, "normal range", "within normal limits",
  "abnormality"). The classifier has no separate "not relevant" level, so to keep
  the levels identical we fold such cases into UNCLEAR (note the reason in the
  comment column if you like).

## Decision rules for borderline cases

- "data were Shapiro–Wilk tested and found normally distributed" → **INCORRECT**.
- "each group was assessed for normality" → **ACCEPTABLE**.
- Group words that refer to the *comparison test* ("differences between groups
  were compared…") are **not** per-group normality testing → still **INCORRECT**.
- If only the abstract-level wording is shown and it is ambiguous → **UNCLEAR**.

## When done

Save the file (keep the CSV format) and send it back. I will compute the
agreement and Cohen's κ between your coding and the rule-based classifier, and
update the manuscript with the real human-validation figures.
