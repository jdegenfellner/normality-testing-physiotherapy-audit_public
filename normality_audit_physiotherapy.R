# ============================================================
#  Normality Testing in Physiotherapy Research: A Meta-Research Audit
#
#  Replication and extension of:
#    Midway & White (2025). "Testing for normality in regression models:
#    mistakes abound (but may not matter)."
#    Royal Society Open Science, 12(4), 241904.
#    https://doi.org/10.1098/rsos.241904
#
#  Authors: [Your Name(s)]
#  Date:    [Date]
#  Target:  Teaching Statistics / Royal Society Open Science /
#           The American Statistician
# ============================================================
#
#  WORKFLOW OVERVIEW
#  -----------------
#  PART 1  — Package setup
#  PART 2  — PubMed search (rentrez)
#  PART 3  — Abstract text mining (flag candidate papers)
#  PART 4  — Export coding sheet (CSV for manual review in Excel/Sheets)
#  PART 5  — Import coded data & descriptive analysis
#  PART 6  — Visualisations (ggplot2)
#  PART 7  — Simulation study (replicating Midway & White)
#  PART 8  — Export results tables
#
#  NOTE: Run Parts 1–4 FIRST, code the CSV manually, then run Parts 5–8.
# ============================================================


# ── PART 1: PACKAGES ─────────────────────────────────────────────────────────

# Install missing packages automatically
required_packages <- c(
  "rentrez",      # PubMed API access
  "tidyverse",    # data wrangling & ggplot2
  "readxl",       # read Excel if needed
  "writexl",      # write Excel coding sheet
  "stringr",      # string manipulation
  "xml2",         # parse PubMed XML
  "purrr",        # functional helpers
  "scales",       # ggplot2 axis formatting
  "knitr",        # table output
  "kableExtra"    # table formatting
)

new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if (length(new_packages)) install.packages(new_packages, repos = "https://cloud.r-project.org")

library(rentrez)
library(tidyverse)
library(writexl)
library(stringr)
library(xml2)
library(purrr)
library(scales)


# ── PART 2: PUBMED SEARCH ────────────────────────────────────────────────────

# ---  2.1  Normality-test keywords  ----------------------------------------
# We search for any paper that MENTIONS a common normality test by name.
# This is an intentionally broad net — false positives are removed at coding.

normality_terms <- c(
  '"Shapiro-Wilk"',
  '"Shapiro Wilk"',
  '"Kolmogorov-Smirnov"',
  '"Kolmogorov Smirnov"',
  '"Lilliefors"',
  '"Anderson-Darling"',
  '"normality test"',
  '"test for normality"',
  '"tested for normality"',
  '"assess normality"',
  '"check normality"',
  '"D\'Agostino"'
)
normality_query <- paste(normality_terms, collapse = "[tiab] OR ")
normality_query <- paste0("(", normality_query, "[tiab])")

# ---  2.2  Physiotherapy / rehabilitation journal list  ----------------------
# Using NLM journal abbreviations as they appear in PubMed [ta] field.
# Expand or reduce this list as needed.

physio_journals <- c(
  '"J Physiother"',               # Journal of Physiotherapy
  '"Phys Ther"',                  # Physical Therapy (APTA)
  '"Physiother Theory Pract"',    # Physiotherapy Theory and Practice
  '"J Orthop Sports Phys Ther"',  # JOSPT
  '"Physiotherapy"',              # Physiotherapy (Elsevier)
  '"Arch Phys Med Rehabil"',      # Archives of Physical Medicine and Rehabilitation
  '"Clin Rehabil"',               # Clinical Rehabilitation
  '"Disabil Rehabil"',            # Disability and Rehabilitation
  '"Eur J Phys Rehabil Med"',     # European Journal of Physical and Rehabilitation Medicine
  '"J Phys Ther Sci"',            # Journal of Physical Therapy Science
  '"Musculoskelet Sci Pract"',    # Musculoskeletal Science and Practice (formerly Manual Therapy)
  '"J Hand Ther"',                # Journal of Hand Therapy
  '"Braz J Phys Ther"',           # Brazilian Journal of Physical Therapy
  '"Hong Kong Physiother J"',     # Hong Kong Physiotherapy Journal
  '"Phys Ther Sport"',            # Physical Therapy in Sport
  '"Physiother Can"'              # Physiotherapy Canada
)
journal_query <- paste(physio_journals, collapse = "[ta] OR ")
journal_query <- paste0("(", journal_query, "[ta])")

# ---  2.3  Date range  -------------------------------------------------------
# Mirror Midway & White's approach: last 10 years for manageable sample size.
# Adjust YEAR_FROM / YEAR_TO as needed.

YEAR_FROM <- 2015
YEAR_TO   <- 2024

date_query <- paste0(
  '("', YEAR_FROM, '/01/01"[dp] : "', YEAR_TO, '/12/31"[dp])'
)

# ---  2.4  Combined query  ---------------------------------------------------
full_query <- paste(normality_query, "AND", journal_query, "AND", date_query)
cat("PubMed query:\n", full_query, "\n\n")

# ---  2.5  Search PubMed  ---------------------------------------------------
cat("Searching PubMed...\n")

search_result <- entrez_search(
  db       = "pubmed",
  term     = full_query,
  retmax   = 0,  # first get count only
  use_history = TRUE
)
total_hits <- search_result$count
cat(sprintf("Total hits: %d\n\n", total_hits))

# Fetch ALL IDs (up to 9999; adjust if needed)
search_result_full <- entrez_search(
  db       = "pubmed",
  term     = full_query,
  retmax   = min(total_hits, 9999),
  use_history = TRUE
)
all_ids <- search_result_full$ids
cat(sprintf("Retrieved %d IDs.\n", length(all_ids)))


# ── PART 3: FETCH ABSTRACTS & METADATA ───────────────────────────────────────

# Helper: parse a single PubMed XML record into a flat list
parse_pubmed_record <- function(xml_record) {
  # Title
  title <- xml_text(xml_find_first(xml_record, ".//ArticleTitle"))

  # Abstract
  abstract_nodes <- xml_find_all(xml_record, ".//AbstractText")
  abstract <- paste(xml_text(abstract_nodes), collapse = " ")

  # Journal
  journal <- xml_text(xml_find_first(xml_record, ".//Journal/Title"))

  # Year
  year_node <- xml_find_first(xml_record, ".//PubDate/Year")
  year <- if (!is.na(year_node)) xml_text(year_node) else NA_character_

  # PMID
  pmid <- xml_text(xml_find_first(xml_record, ".//PMID"))

  # Authors (first author only for brevity)
  first_author_last <- xml_text(xml_find_first(xml_record, ".//Author/LastName"))

  list(
    pmid         = pmid,
    title        = title,
    journal      = journal,
    year         = year,
    first_author = first_author_last,
    abstract     = abstract
  )
}

# Fetch in batches of 100 to avoid API limits
batch_size <- 100
n_batches   <- ceiling(length(all_ids) / batch_size)

cat(sprintf("Fetching abstracts in %d batches...\n", n_batches))
all_records <- vector("list", length(all_ids))

for (i in seq_len(n_batches)) {
  idx_start <- (i - 1) * batch_size + 1
  idx_end   <- min(i * batch_size, length(all_ids))
  batch_ids <- all_ids[idx_start:idx_end]

  cat(sprintf("  Batch %d/%d (PMIDs %d–%d)\n", i, n_batches, idx_start, idx_end))

  # Polite API usage: wait 0.4s between requests
  if (i > 1) Sys.sleep(0.4)

  xml_raw <- entrez_fetch(
    db      = "pubmed",
    id      = batch_ids,
    rettype = "xml"
  )

  xml_parsed <- read_xml(xml_raw)
  records    <- xml_find_all(xml_parsed, "//PubmedArticle")

  for (j in seq_along(records)) {
    all_records[[idx_start + j - 1]] <- parse_pubmed_record(records[[j]])
  }
}

# Combine into a data frame
df_raw <- bind_rows(all_records)
cat(sprintf("\nData frame: %d rows × %d columns\n", nrow(df_raw), ncol(df_raw)))


# ── PART 3: TEXT MINING — flag likely candidates ──────────────────────────────
#
# We use keyword matching in the abstract to pre-classify papers.
# This is NOT the final coding — it just helps the human coder prioritise.
#
# Category heuristics (to be verified manually):
#   FLAG_RESIDUALS : mentions "residual" near normality test → likely CORRECT
#   FLAG_RAW_DATA  : mentions "data were" / "raw data" near normality test → likely INCORRECT
#   FLAG_GROUPS    : mentions "each group" / "per group" → ACCEPTABLE for t-test
#   FLAG_UNCLEAR   : no clear indication → needs manual reading

flag_pattern_residual  <- regex(
  "residual|model assumption|assumption.*model",
  ignore_case = TRUE
)
flag_pattern_raw       <- regex(
  "data were normally|raw data|outcome.*normal|variable.*normal|dependent.*normal",
  ignore_case = TRUE
)
flag_pattern_group     <- regex(
  "each group|per group|within.{0,20}group|group.{0,20}separately|both groups",
  ignore_case = TRUE
)

df_flagged <- df_raw %>%
  mutate(
    has_normality_keyword = str_detect(
      abstract,
      regex("Shapiro|Kolmogorov|Lilliefors|Anderson-Darling|normality test|test for normality",
            ignore_case = TRUE)
    ),
    flag_residuals = str_detect(abstract, flag_pattern_residual),
    flag_raw_data  = str_detect(abstract, flag_pattern_raw),
    flag_per_group = str_detect(abstract, flag_pattern_group),

    # Automated pre-classification (PROVISIONAL — must be confirmed manually)
    auto_class = case_when(
      flag_residuals ~ "LIKELY_CORRECT",
      flag_per_group ~ "ACCEPTABLE",
      flag_raw_data  ~ "LIKELY_INCORRECT",
      TRUE           ~ "UNCLEAR"
    )
  )

cat("\nAuto-classification summary:\n")
print(table(df_flagged$auto_class, useNA = "ifany"))


# ── PART 4: EXPORT CODING SHEET ──────────────────────────────────────────────
#
# This exports a spreadsheet for manual coding by a human reviewer.
# The coder reads the full-text methods section and assigns a final category.
#
# Coding categories (FINAL_CODE column):
#   CORRECT      – normality tested on model residuals (gold standard)
#   ACCEPTABLE   – normality tested separately per group (defensible for t-tests)
#   INCORRECT    – normality tested on pooled raw/outcome data (WRONG)
#   MIXED        – both correct and incorrect approaches used in same paper
#   UNCLEAR      – not enough information in text to determine
#   NOT_RELEVANT – paper mentions normality but not as model assumption check
#                  (e.g., the paper IS about normality testing methodology)
#
# Inter-rater reliability:
#   If two coders are used, export two copies. Cohen's kappa will be computed
#   in Part 5.

coding_sheet <- df_flagged %>%
  select(
    pmid, year, journal, first_author, title,
    auto_class,                     # provisional flag (not binding)
    abstract
  ) %>%
  mutate(
    # Columns to be filled in manually
    FULL_TEXT_AVAILABLE = "",       # Y / N / NA
    FINAL_CODE          = "",       # see categories above
    WHAT_WAS_TESTED     = "",       # e.g., "outcome variable", "residuals", "each group"
    STATISTICAL_TEST    = "",       # e.g., "t-test", "ANOVA", "regression"
    NORMALITY_TEST_USED = "",       # e.g., "Shapiro-Wilk", "K-S", "both"
    SAMPLE_SIZE_N       = NA_real_, # total N reported in paper
    NOTES               = ""        # free text
  ) %>%
  arrange(journal, year)

output_dir <- dirname(rstudioapi::getActiveDocumentContext()$path)
if (!nzchar(output_dir) || output_dir == ".") output_dir <- getwd()

coding_path <- file.path(output_dir, "coding_sheet_physiotherapy_normality.xlsx")
write_xlsx(coding_sheet, coding_path)
cat(sprintf("\nCoding sheet saved to:\n  %s\n", coding_path))
cat(sprintf("Papers to code: %d\n", nrow(coding_sheet)))
cat("\n*** STOP HERE — code the spreadsheet, then continue with PART 5 ***\n\n")


# ════════════════════════════════════════════════════════════════════════════
#  ↓↓↓  CONTINUE BELOW ONLY AFTER MANUAL CODING IS COMPLETE  ↓↓↓
# ════════════════════════════════════════════════════════════════════════════


# ── PART 5: LOAD CODED DATA & DESCRIPTIVE ANALYSIS ───────────────────────────

# --- 5.1 Load ---
coded_path <- file.path(output_dir, "coding_sheet_physiotherapy_normality.xlsx")
df_coded   <- readxl::read_xlsx(coded_path)

# Keep only papers with a final code (exclude not yet coded)
df_coded <- df_coded %>%
  filter(!is.na(FINAL_CODE) & FINAL_CODE != "") %>%
  mutate(
    year         = as.integer(year),
    FINAL_CODE   = trimws(FINAL_CODE),
    SAMPLE_SIZE_N = as.numeric(SAMPLE_SIZE_N)
  )

cat(sprintf("Coded papers: %d\n", nrow(df_coded)))

# --- 5.2 Inter-rater reliability (if second coder used) ---
# Uncomment and adapt if you have a second coding column:
#
# library(irr)
# df_irr <- df_coded %>% filter(!is.na(FINAL_CODE_CODER2))
# kappa_result <- kappa2(df_irr[, c("FINAL_CODE", "FINAL_CODE_CODER2")])
# cat("\nCohen's kappa:", round(kappa_result$value, 3), "\n")

# --- 5.3 Main result: proportion of incorrect coding by journal ---

# Collapse to binary: INCORRECT vs. everything else interpretable
analysis_df <- df_coded %>%
  filter(FINAL_CODE %in% c("CORRECT", "ACCEPTABLE", "INCORRECT", "MIXED")) %>%
  mutate(
    is_incorrect = FINAL_CODE %in% c("INCORRECT", "MIXED")
  )

overall_rate <- mean(analysis_df$is_incorrect, na.rm = TRUE)
cat(sprintf("\nOverall incorrect rate: %.1f%%  (n = %d papers)\n",
            overall_rate * 100, nrow(analysis_df)))

# By journal
by_journal <- analysis_df %>%
  group_by(journal) %>%
  summarise(
    n_papers    = n(),
    n_incorrect = sum(is_incorrect),
    pct_incorrect = mean(is_incorrect) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(pct_incorrect))

cat("\nBy journal:\n")
print(by_journal)

# By year
by_year <- analysis_df %>%
  filter(!is.na(year)) %>%
  group_by(year) %>%
  summarise(
    n_papers      = n(),
    pct_incorrect = mean(is_incorrect) * 100,
    .groups = "drop"
  )

# Confidence intervals for the overall proportion (Wilson interval)
binom_ci <- function(x, n, conf = 0.95) {
  z    <- qnorm(1 - (1 - conf) / 2)
  phat <- x / n
  denom <- 1 + z^2 / n
  center <- (phat + z^2 / (2 * n)) / denom
  margin <- z * sqrt(phat * (1 - phat) / n + z^2 / (4 * n^2)) / denom
  c(lower = center - margin, upper = center + margin)
}

ci <- binom_ci(sum(analysis_df$is_incorrect), nrow(analysis_df))
cat(sprintf("95%% CI (Wilson): [%.1f%%, %.1f%%]\n",
            ci["lower"] * 100, ci["upper"] * 100))

# --- 5.4 Normality test used ---
test_freq <- df_coded %>%
  filter(!is.na(NORMALITY_TEST_USED) & NORMALITY_TEST_USED != "") %>%
  count(NORMALITY_TEST_USED, sort = TRUE)

cat("\nNormality tests used:\n")
print(test_freq)

# --- 5.5 Statistical context ---
stat_test_freq <- df_coded %>%
  filter(!is.na(STATISTICAL_TEST) & STATISTICAL_TEST != "") %>%
  count(STATISTICAL_TEST, sort = TRUE)

cat("\nStatistical tests paired with normality tests:\n")
print(stat_test_freq)

# --- 5.6 Sample size summary ---
cat("\nSample size summary:\n")
print(summary(df_coded$SAMPLE_SIZE_N))


# ── PART 6: VISUALISATIONS ───────────────────────────────────────────────────

theme_paper <- theme_bw(base_size = 11) +
  theme(
    panel.grid.minor  = element_blank(),
    strip.background  = element_rect(fill = "grey92"),
    legend.position   = "bottom"
  )

# --- 6.1 Stacked bar: coding categories by journal ---
p1_data <- df_coded %>%
  filter(FINAL_CODE %in% c("CORRECT","ACCEPTABLE","INCORRECT","MIXED","UNCLEAR")) %>%
  count(journal, FINAL_CODE) %>%
  group_by(journal) %>%
  mutate(pct = n / sum(n) * 100) %>%
  ungroup() %>%
  mutate(
    FINAL_CODE = factor(FINAL_CODE,
      levels = c("INCORRECT","MIXED","UNCLEAR","ACCEPTABLE","CORRECT")),
    journal    = str_wrap(journal, width = 30)
  )

cols_coding <- c(
  INCORRECT  = "#d62728",
  MIXED      = "#ff7f0e",
  UNCLEAR    = "#7f7f7f",
  ACCEPTABLE = "#aec7e8",
  CORRECT    = "#1f77b4"
)

p1 <- ggplot(p1_data, aes(x = reorder(journal, -pct, function(x) x[FINAL_CODE == "INCORRECT"]),
                           y = pct, fill = FINAL_CODE)) +
  geom_col(colour = "white", linewidth = 0.3) +
  scale_fill_manual(
    values = cols_coding,
    name   = "Normality test applied to:",
    labels = c(
      INCORRECT  = "Raw/pooled data (INCORRECT)",
      MIXED      = "Mixed",
      UNCLEAR    = "Unclear",
      ACCEPTABLE = "Each group separately",
      CORRECT    = "Model residuals (CORRECT)"
    )
  ) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  coord_flip() +
  labs(
    x = NULL,
    y = "Percentage of papers (%)",
    title = "Normality testing practices by physiotherapy journal",
    subtitle = paste0("n = ", nrow(df_coded), " coded papers, ", YEAR_FROM, "–", YEAR_TO)
  ) +
  theme_paper +
  theme(legend.position = "bottom",
        legend.direction = "vertical")

print(p1)
ggsave(file.path(output_dir, "fig1_coding_by_journal.pdf"), p1,
       width = 8, height = 5.5)
ggsave(file.path(output_dir, "fig1_coding_by_journal.png"), p1,
       width = 8, height = 5.5, dpi = 300)

# --- 6.2 Trend over time ---
p2 <- ggplot(by_year, aes(x = year, y = pct_incorrect)) +
  geom_line(colour = "#d62728") +
  geom_point(aes(size = n_papers), colour = "#d62728") +
  geom_smooth(method = "lm", se = TRUE, colour = "black", linetype = "dashed",
              linewidth = 0.8) +
  scale_size_continuous(name = "n papers", range = c(2, 6)) +
  scale_y_continuous(limits = c(0, 100),
                     labels = label_percent(scale = 1)) +
  labs(
    x = "Year",
    y = "% papers with incorrect normality test",
    title = "Trend in normality testing misuse over time",
    subtitle = "Linear trend (dashed)"
  ) +
  theme_paper

print(p2)
ggsave(file.path(output_dir, "fig2_trend_over_time.pdf"), p2,
       width = 7, height = 4.5)
ggsave(file.path(output_dir, "fig2_trend_over_time.png"), p2,
       width = 7, height = 4.5, dpi = 300)

# --- 6.3 Comparison with Midway & White (2025) ---
comparison_df <- tibble(
  discipline     = c("Ecology\n(Midway & White)", "Biology\n(Midway & White)",
                      "Physiotherapy\n(this study)"),
  pct_incorrect  = c(72.4, 89.5, overall_rate * 100),  # replace 72.4/89.5 with exact M&W values
  ci_lower       = c(NA, NA, ci["lower"] * 100),
  ci_upper       = c(NA, NA, ci["upper"] * 100),
  source         = c("Midway & White 2025", "Midway & White 2025", "This study")
)

p3 <- ggplot(comparison_df,
             aes(x = discipline, y = pct_incorrect, fill = source)) +
  geom_col(width = 0.55, colour = "grey30") +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                width = 0.15, colour = "grey30", na.rm = TRUE) +
  scale_fill_manual(values = c("Midway & White 2025" = "grey70",
                                "This study"          = "#d62728"),
                    name = NULL) +
  scale_y_continuous(limits = c(0, 100),
                     labels = label_percent(scale = 1)) +
  labs(
    x = NULL,
    y = "% papers with incorrect normality test",
    title = "Cross-disciplinary comparison of normality test misuse",
    caption = "Error bars: 95% Wilson CI (this study only)"
  ) +
  theme_paper +
  theme(legend.position = "top")

print(p3)
ggsave(file.path(output_dir, "fig3_comparison.pdf"), p3,
       width = 6, height = 4.5)
ggsave(file.path(output_dir, "fig3_comparison.png"), p3,
       width = 6, height = 4.5, dpi = 300)


# ── PART 7: SIMULATION STUDY ──────────────────────────────────────────────────
#
#  Following Midway & White (2025):
#  Compare STATISTICAL POWER of two decision workflows:
#
#    Workflow A (INCORRECT): Test normality on pooled raw data
#                            → if normal: t-test; else: Mann-Whitney U
#    Workflow B (CORRECT):   Test normality on residuals (= per group for t-test)
#                            → if normal: t-test; else: Mann-Whitney U
#    Workflow C (PRAGMATIC): Always use Welch t-test (no normality testing)
#    Workflow D (ROBUST):    Always use Mann-Whitney U
#
#  We add a PHYSIOTHERAPY-SPECIFIC SCENARIO: small n, Likert-type pain scores
#  (discrete, bounded, often skewed) — very common in PT research.
#
#  Distributions simulated:
#    1. Normal            (μ = 0, σ = 1)
#    2. Moderately skewed (gamma distribution)
#    3. Pain-score-like   (bounded 0–10, right-skewed, common in NRS/VAS)
#    4. Bimodal           (mixture of two normals)

set.seed(2025)  # for reproducibility

# --- 7.1 Helper functions ---

# Simulate one two-group dataset
sim_two_groups <- function(n_per_group, dist, effect_size) {
  # Effect size d (Cohen's d): group B shifted by d * pooled SD

  gen_sample <- function(n, shift = 0) {
    switch(dist,
      "normal"   = rnorm(n, mean = shift, sd = 1),
      "skewed"   = rgamma(n, shape = 2, rate = 1) - 2 + shift,
      "pain"     = {
        # Simulate NRS 0-10: beta distribution scaled to 0-10, right skewed
        raw <- rbeta(n, shape1 = 2, shape2 = 5) * 10 + shift
        pmin(pmax(round(raw), 0), 10)  # discretise & bound
      },
      "bimodal"  = {
        # 50% from N(-1,0.5), 50% from N(1,0.5)
        g <- rbinom(n, 1, 0.5)
        ifelse(g == 0, rnorm(n, -1, 0.5), rnorm(n, 1, 0.5)) + shift
      }
    )
  }

  list(
    group_A = gen_sample(n_per_group, shift = 0),
    group_B = gen_sample(n_per_group, shift = effect_size)
  )
}

# Apply normality test to vector; return TRUE if normal (p > 0.05)
is_normal <- function(x, alpha = 0.05) {
  if (length(x) < 3)  return(TRUE)
  if (length(x) > 50) {
    tryCatch(shapiro.test(x)$p.value > alpha, error = function(e) TRUE)
  } else {
    tryCatch(shapiro.test(x)$p.value > alpha, error = function(e) TRUE)
  }
}

# Workflow A: test pooled raw data
workflow_A <- function(g_A, g_B, alpha_test = 0.05, alpha_norm = 0.05) {
  pooled  <- c(g_A, g_B)
  use_param <- is_normal(pooled, alpha = alpha_norm)
  if (use_param) {
    t.test(g_A, g_B)$p.value < alpha_test
  } else {
    wilcox.test(g_A, g_B)$p.value < alpha_test
  }
}

# Workflow B: test residuals (equivalently: test each group separately)
workflow_B <- function(g_A, g_B, alpha_test = 0.05, alpha_norm = 0.05) {
  norm_A    <- is_normal(g_A, alpha = alpha_norm)
  norm_B    <- is_normal(g_B, alpha = alpha_norm)
  use_param <- norm_A & norm_B
  if (use_param) {
    t.test(g_A, g_B)$p.value < alpha_test
  } else {
    wilcox.test(g_A, g_B)$p.value < alpha_test
  }
}

# Workflow C: always Welch t-test
workflow_C <- function(g_A, g_B, alpha_test = 0.05, ...) {
  t.test(g_A, g_B)$p.value < alpha_test
}

# Workflow D: always Mann-Whitney
workflow_D <- function(g_A, g_B, alpha_test = 0.05, ...) {
  wilcox.test(g_A, g_B)$p.value < alpha_test
}

# --- 7.2 Simulation grid ---
sim_params <- expand.grid(
  n_per_group  = c(10, 20, 30, 50, 100),  # physiotherapy trials often n < 30
  effect_size  = c(0, 0.2, 0.5, 0.8),    # 0 = type I error check
  distribution = c("normal", "skewed", "pain", "bimodal"),
  stringsAsFactors = FALSE
)

N_SIM <- 2000  # number of simulations per cell

cat(sprintf("\nRunning simulation: %d parameter combinations × %d reps = %s runs\n",
            nrow(sim_params), N_SIM,
            format(nrow(sim_params) * N_SIM, big.mark = ",")))

# --- 7.3 Run simulation ---
run_simulation_cell <- function(row) {
  n   <- row$n_per_group
  d   <- row$effect_size
  dst <- row$distribution

  results <- replicate(N_SIM, {
    dat <- sim_two_groups(n, dst, d)
    c(
      A = workflow_A(dat$group_A, dat$group_B),
      B = workflow_B(dat$group_A, dat$group_B),
      C = workflow_C(dat$group_A, dat$group_B),
      D = workflow_D(dat$group_A, dat$group_B)
    )
  })

  data.frame(
    n_per_group  = n,
    effect_size  = d,
    distribution = dst,
    power_A      = mean(results["A",]),  # incorrect (pooled raw data)
    power_B      = mean(results["B",]),  # correct (per-group / residuals)
    power_C      = mean(results["C",]),  # always Welch
    power_D      = mean(results["D",]),  # always Mann-Whitney
    stringsAsFactors = FALSE
  )
}

sim_results <- map_dfr(
  seq_len(nrow(sim_params)),
  function(i) {
    if (i %% 10 == 0) cat(sprintf("  ... cell %d/%d\n", i, nrow(sim_params)))
    run_simulation_cell(sim_params[i, ])
  }
)

cat("\nSimulation complete.\n")

# Type I error check (effect_size = 0)
type1 <- sim_results %>% filter(effect_size == 0) %>%
  summarise(across(starts_with("power_"), mean))
cat("\nType I error rates (should be ~0.05):\n")
print(round(type1, 3))

# Save simulation results
write_csv(sim_results, file.path(output_dir, "simulation_results.csv"))

# --- 7.4 Visualise simulation ---

# Power curves: Workflow A vs B vs C vs D, by distribution
sim_long <- sim_results %>%
  filter(effect_size > 0) %>%
  pivot_longer(
    cols      = starts_with("power_"),
    names_to  = "workflow",
    values_to = "power"
  ) %>%
  mutate(
    workflow = recode(workflow,
      power_A = "A: Incorrect\n(pooled raw data)",
      power_B = "B: Correct\n(per-group / residuals)",
      power_C = "C: Always Welch t-test",
      power_D = "D: Always Mann-Whitney"
    ),
    distribution = recode(distribution,
      normal  = "Normal",
      skewed  = "Skewed (gamma)",
      pain    = "Pain score (NRS 0–10)",
      bimodal = "Bimodal"
    ),
    n_per_group = factor(n_per_group)
  )

p4 <- ggplot(
    sim_long %>% filter(effect_size == 0.5),
    aes(x = n_per_group, y = power, colour = workflow, group = workflow)
  ) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_hline(yintercept = 0.80, linetype = "dashed", colour = "grey50") +
  annotate("text", x = 5.3, y = 0.82, label = "80% power", size = 3,
           colour = "grey40") +
  facet_wrap(~ distribution, nrow = 2) +
  scale_y_continuous(limits = c(0, 1), labels = label_percent()) +
  scale_colour_brewer(palette = "Set1", name = "Workflow") +
  labs(
    x = "n per group",
    y = "Statistical power",
    title = "Statistical power by workflow and data distribution",
    subtitle = "Effect size d = 0.5 (medium); 2000 simulations per cell"
  ) +
  theme_paper

print(p4)
ggsave(file.path(output_dir, "fig4_power_curves.pdf"), p4,
       width = 9, height = 6.5)
ggsave(file.path(output_dir, "fig4_power_curves.png"), p4,
       width = 9, height = 6.5, dpi = 300)

# Power difference: A minus B (positive = A has MORE power, i.e., incorrect
# workflow accidentally does better; negative = correct workflow is better)
p5_data <- sim_results %>%
  filter(effect_size > 0) %>%
  mutate(diff_AB = (power_A - power_B) * 100) %>%
  mutate(
    distribution = recode(distribution,
      normal  = "Normal",
      skewed  = "Skewed",
      pain    = "Pain score",
      bimodal = "Bimodal"
    )
  )

p5 <- ggplot(p5_data,
             aes(x = factor(n_per_group), y = diff_AB,
                 fill = factor(effect_size))) +
  geom_col(position = position_dodge(0.8), colour = "grey40", linewidth = 0.3) +
  geom_hline(yintercept = 0, colour = "black") +
  facet_wrap(~ distribution) +
  scale_fill_brewer(palette = "Blues", name = "Effect size (d)") +
  labs(
    x = "n per group",
    y = "Power difference: Workflow A − B (percentage points)",
    title = "Power cost of using incorrect normality testing workflow",
    subtitle = "Positive = incorrect workflow accidentally better; Negative = correct workflow better"
  ) +
  theme_paper

print(p5)
ggsave(file.path(output_dir, "fig5_power_difference.pdf"), p5,
       width = 9, height = 6)
ggsave(file.path(output_dir, "fig5_power_difference.png"), p5,
       width = 9, height = 6, dpi = 300)


# ── PART 8: RESULTS TABLES FOR PAPER ─────────────────────────────────────────

# Table 1: Journals searched + results
table1 <- by_journal %>%
  rename(
    Journal       = journal,
    `Papers coded` = n_papers,
    `N incorrect`  = n_incorrect,
    `% incorrect`  = pct_incorrect
  ) %>%
  mutate(`% incorrect` = round(`% incorrect`, 1))

cat("\n=== TABLE 1: Results by journal ===\n")
knitr::kable(table1, format = "simple")

# Table 2: Simulation summary (d = 0.5, selected n)
table2 <- sim_results %>%
  filter(effect_size == 0.5, n_per_group %in% c(10, 20, 30, 50)) %>%
  select(distribution, n_per_group, power_A, power_B, power_C, power_D) %>%
  mutate(across(starts_with("power_"), ~ round(. * 100, 1))) %>%
  rename(
    Distribution        = distribution,
    `n/group`           = n_per_group,
    `A: Incorrect (%)` = power_A,
    `B: Correct (%)`   = power_B,
    `C: Welch (%)`     = power_C,
    `D: Mann-Whit. (%)` = power_D
  )

cat("\n=== TABLE 2: Power at d = 0.5 ===\n")
knitr::kable(table2, format = "simple")

# Export tables as CSV
write_csv(table1, file.path(output_dir, "table1_results_by_journal.csv"))
write_csv(table2, file.path(output_dir, "table2_simulation_power.csv"))

cat("\n\nAll outputs saved to:", output_dir, "\n")
cat("Done!\n")
