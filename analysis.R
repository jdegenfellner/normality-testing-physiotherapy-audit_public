# ============================================================
#  Analysis, figures and tables for the physiotherapy normality audit.
#  Inputs:  coded_auto.csv (classifier output), simulation_results.csv
#  Outputs: fig1-5 (pdf+png), table1/table2 csv + LaTeX, results_summary.txt
# ============================================================
suppressMessages({library(tidyverse); library(scales)})
options(width = 120)

sink("results_summary.txt", split = TRUE)

df <- read_csv("coded_auto.csv", show_col_types = FALSE) %>%
  mutate(year = as.integer(year),
         auto_code = factor(auto_code,
           levels = c("CORRECT","ACCEPTABLE","INCORRECT","MIXED","UNCLEAR","NOT_RELEVANT"))) %>%
  # Restrict to full publication years 2015-2024 (the stated study window);
  # online-first records dated 2025 that the search returned are excluded.
  filter(year >= 2015, year <= 2024)

cat("===== CORPUS =====\n")
cat(sprintf("Total papers: %d\n", nrow(df)))
cat(sprintf("Year range: %d-%d\n", min(df$year, na.rm=TRUE), max(df$year, na.rm=TRUE)))
cat("\nOverall code distribution:\n")
print(df %>% count(auto_code) %>% mutate(pct = round(100*n/sum(n),1)))

# ---- primary outcome: incorrect among definitively coded ----
definitive <- df %>% filter(auto_code %in% c("CORRECT","ACCEPTABLE","INCORRECT","MIXED")) %>%
  mutate(is_incorrect = auto_code %in% c("INCORRECT","MIXED"))
x <- sum(definitive$is_incorrect); n <- nrow(definitive)
rate <- x/n
wilson <- function(x, n, conf=0.95){ z<-qnorm(1-(1-conf)/2); p<-x/n; d<-1+z^2/n
  c((p+z^2/(2*n))/d - z*sqrt(p*(1-p)/n+z^2/(4*n^2))/d,
    (p+z^2/(2*n))/d + z*sqrt(p*(1-p)/n+z^2/(4*n^2))/d) }
ci <- wilson(x, n)
cat(sprintf("\n===== PRIMARY OUTCOME =====\n"))
cat(sprintf("Definitively coded: %d\n", n))
cat(sprintf("Incorrect (INCORRECT+MIXED): %d (%.1f%%), 95%% Wilson CI [%.1f, %.1f]\n",
            x, 100*rate, 100*ci[1], 100*ci[2]))
cat(sprintf("Correct (residuals): %d (%.1f%%)\n", sum(definitive$auto_code=="CORRECT"),
            100*mean(definitive$auto_code=="CORRECT")))
cat(sprintf("Acceptable (per group): %d (%.1f%%)\n", sum(definitive$auto_code=="ACCEPTABLE"),
            100*mean(definitive$auto_code=="ACCEPTABLE")))

# ---- by journal ----
by_journal <- definitive %>% group_by(journal_full) %>%
  summarise(n_papers=n(), n_incorrect=sum(is_incorrect),
            pct_incorrect=round(100*mean(is_incorrect),1), .groups="drop") %>%
  arrange(desc(n_papers))
cat("\n===== BY JOURNAL (definitive) =====\n"); print(by_journal, n=50)

# ---- by year (purely descriptive; no trend model fitted) ----
by_year <- definitive %>% filter(!is.na(year)) %>% group_by(year) %>%
  summarise(n_papers=n(), n_incorrect=sum(is_incorrect),
            pct_incorrect=100*mean(is_incorrect), .groups="drop")
cat("\n===== BY YEAR =====\n"); print(by_year)
# The temporal trend is reported descriptively only: the yearly proportions,
# weighted by their sample sizes, already show the (absence of a) trend, so no
# logistic or linear regression is fitted (cf. Wasserstein 2019).
cat(sprintf("\nTrend (descriptive): yearly range %.1f%%-%.1f%%\n",
            min(by_year$pct_incorrect), max(by_year$pct_incorrect)))

# ---- normality test used (all papers w/ a test) ----
cat("\n===== NORMALITY TEST USED =====\n")
tests_tab <- df %>% filter(norm_tests != "") %>%
  separate_rows(norm_tests, sep="; ") %>% count(norm_tests, sort=TRUE)
print(tests_tab)
n_sw <- df %>% filter(str_detect(norm_tests,"Shapiro")) %>% nrow()
n_ks <- df %>% filter(str_detect(norm_tests,"Kolmogorov")) %>% nrow()
cat(sprintf("Papers mentioning Shapiro-Wilk: %d (%.1f%%)\n", n_sw, 100*n_sw/nrow(df)))
cat(sprintf("Papers mentioning K-S/Lilliefors: %d (%.1f%%)\n", n_ks, 100*n_ks/nrow(df)))

cat("\n===== STATISTICAL CONTEXT =====\n")
ctx_tab <- df %>% filter(stat_context != "") %>%
  separate_rows(stat_context, sep="; ") %>% count(stat_context, sort=TRUE)
print(ctx_tab)

# ---- sensitivity: prevalence restricted to clear linear-model contexts ----
# The residuals-vs-raw criterion is unambiguous only for the linear model
# (t-test / ANOVA / ANCOVA / regression). Re-compute the incorrect rate on the
# subset whose normality sentence sits next to such an analysis, and separately
# for the most common non-linear-model context (Pearson correlation).
lm_ctx  <- "t-test|ANOVA|ANCOVA|regression|mixed"
lm_only <- definitive %>% filter(grepl(lm_ctx, stat_context, ignore.case = TRUE))
cor_only <- definitive %>%
  filter(grepl("correlation", stat_context, ignore.case = TRUE),
         !grepl(lm_ctx, stat_context, ignore.case = TRUE))
cat(sprintf("\nSensitivity (linear-model context): %d/%d = %.1f%% incorrect (%.0f%% of corpus)\n",
            sum(lm_only$is_incorrect), nrow(lm_only),
            100*mean(lm_only$is_incorrect), 100*nrow(lm_only)/n))
cat(sprintf("Correlation-only context:           %d/%d = %.1f%% incorrect\n",
            sum(cor_only$is_incorrect), nrow(cor_only), 100*mean(cor_only$is_incorrect)))

# ============================================================
#  FIGURES
# ============================================================
theme_paper <- theme_bw(base_size = 11) +
  theme(panel.grid.minor=element_blank(),
        strip.background=element_rect(fill="grey92"), legend.position="bottom",
        plot.title    = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5))

# --- Fig 1: coding categories by journal (journals with n>=10 definitive) ---
keep_j <- by_journal %>% filter(n_papers >= 10) %>% pull(journal_full)
p1d <- df %>% filter(journal_full %in% keep_j,
                     auto_code %in% c("CORRECT","ACCEPTABLE","INCORRECT","MIXED","UNCLEAR")) %>%
  count(journal_full, auto_code) %>% group_by(journal_full) %>%
  mutate(pct=100*n/sum(n)) %>% ungroup() %>%
  mutate(auto_code=factor(auto_code, levels=c("INCORRECT","MIXED","UNCLEAR","ACCEPTABLE","CORRECT")),
         journal_full=str_wrap(journal_full,30))
cols <- c(INCORRECT="#d62728",MIXED="#ff7f0e",UNCLEAR="#7f7f7f",ACCEPTABLE="#aec7e8",CORRECT="#1f77b4")
ord <- p1d %>% filter(auto_code=="INCORRECT") %>% arrange(pct) %>% pull(journal_full)
p1 <- ggplot(p1d, aes(factor(journal_full, levels=ord), pct, fill=auto_code)) +
  geom_col(colour="white", linewidth=0.3) +
  scale_fill_manual(values=cols, name="Normality test applied to:",
    labels=c(INCORRECT="Pooled raw data (incorrect)",MIXED="Mixed",UNCLEAR="Unclear",
             ACCEPTABLE="Each group (acceptable)",CORRECT="Residuals (correct)")) +
  scale_y_continuous(labels=label_number(suffix="%")) + coord_flip() +
  labs(x=NULL, y="Percentage of papers",
       title="Normality-testing practice by physiotherapy journal",
       subtitle=sprintf("Journals with >=10 coded papers; %d papers total, 2015-2024", nrow(df))) +
  theme_paper + theme(legend.direction="vertical")
ggsave("fig1_coding_by_journal.pdf", p1, width=8, height=5.5)
ggsave("fig1_coding_by_journal.png", p1, width=8, height=5.5, dpi=300)

# --- Fig 2: trend over time (descriptive only; no fitted trend line) ---
p2 <- ggplot(by_year, aes(year, pct_incorrect)) +
  geom_line(colour="#d62728") + geom_point(aes(size=n_papers), colour="#d62728") +
  scale_size_continuous(name="n papers", range=c(2,6)) +
  scale_x_continuous(breaks=seq(min(by_year$year), max(by_year$year), 1)) +
  scale_y_continuous(limits=c(0,100), labels=label_number(suffix="%")) +
  labs(x="Year", y="% papers with incorrect normality test",
       title="Incorrect normality testing over time",
       subtitle="Points sized by number of coded papers") + theme_paper
ggsave("fig2_trend_over_time.pdf", p2, width=7, height=4.5)
ggsave("fig2_trend_over_time.png", p2, width=7, height=4.5, dpi=300)

# --- Fig 3: cross-disciplinary comparison ---
# Physiotherapy value = misclassification-corrected prevalence (Estimand A, the
# primary conservative estimand) with its bootstrap CI, from validation_analyze.py
# (not the raw classifier census).
phys_corrected <- 89.0; phys_lo <- 81.4; phys_hi <- 95.2
# Comparator 95% binomial (Wilson) CIs: Midway & White coded 50 papers/field,
# ecology 70% (35/50), biology 90% (45/50). Shown so the comparison does not
# overstate how cleanly physiotherapy "exceeds ecology / matches biology".
eco_ci <- 100*wilson(35, 50); bio_ci <- 100*wilson(45, 50)
comp <- tibble(
  discipline=c("Ecology\n(Midway & White)","Biology\n(Midway & White)","Physiotherapy\n(this study)"),
  pct=c(70, 90, phys_corrected),
  lo=c(eco_ci[1], bio_ci[1], phys_lo), hi=c(eco_ci[2], bio_ci[2], phys_hi),
  src=c("Midway & White 2025","Midway & White 2025","This study"))
cat(sprintf("Fig3 comparator CIs: ecology 70%% [%.1f, %.1f], biology 90%% [%.1f, %.1f]\n",
            eco_ci[1], eco_ci[2], bio_ci[1], bio_ci[2]))
p3 <- ggplot(comp, aes(discipline, pct, fill=src)) +
  geom_col(width=0.55, colour="grey30") +
  geom_errorbar(aes(ymin=lo, ymax=hi), width=0.15, na.rm=TRUE) +
  scale_fill_manual(values=c("Midway & White 2025"="grey70","This study"="#d62728"), name=NULL) +
  scale_y_continuous(limits=c(0,100), labels=label_number(suffix="%")) +
  labs(x=NULL, y="% papers testing normality on raw data",
       title="Cross-disciplinary comparison of normality-test misuse",
       caption="Ecology/biology: Midway & White (2025), 50 papers/field (error bars = 95% Wilson CIs). Physiotherapy: misclassification-corrected (Estimand A); 95% bootstrap CI.") +
  theme_paper + theme(legend.position="top")
ggsave("fig3_comparison.pdf", p3, width=6, height=4.5)
ggsave("fig3_comparison.png", p3, width=6, height=4.5, dpi=300)

# ============================================================
#  SIMULATION figures + table
# ============================================================
sim <- read_csv("simulation_results.csv", show_col_types=FALSE)
cat("\n===== SIMULATION: Type I error (d=0) =====\n")
print(sim %>% filter(effect_size==0) %>%
        summarise(across(starts_with("power_"), ~round(mean(.),3))))

sim_long <- sim %>% filter(effect_size>0) %>%
  pivot_longer(starts_with("power_"), names_to="workflow", values_to="power") %>%
  mutate(workflow=recode(workflow,
            power_A="A: Incorrect (pooled)", power_B="B: Per-group",
            power_C="C: Welch t-test", power_D="D: Mann-Whitney"),
         distribution=recode(distribution, normal="Normal", skewed="Skewed (gamma)",
            pain="Pain score (NRS 0-10)", bimodal="Bimodal"),
         n_per_group=factor(n_per_group))

p4 <- ggplot(filter(sim_long, effect_size==0.5),
             aes(n_per_group, power, colour=workflow, group=workflow)) +
  geom_line(linewidth=0.9) + geom_point(size=2) +
  geom_hline(yintercept=0.8, linetype="dashed", colour="grey50") +
  facet_wrap(~distribution, nrow=2) +
  scale_y_continuous(limits=c(0,1), labels=label_percent()) +
  scale_colour_brewer(palette="Set1", name="Workflow") +
  labs(x="n per group", y="Statistical power",
       title="Statistical power by workflow and data distribution",
       subtitle="Effect size d = 0.5; 10,000 simulations per cell; dashed = 80% power") +
  theme_paper
ggsave("fig4_power_curves.pdf", p4, width=9, height=6.5)
ggsave("fig4_power_curves.png", p4, width=9, height=6.5, dpi=300)

p5d <- sim %>% filter(effect_size>0) %>% mutate(diff_AB=(power_A-power_B)*100,
  distribution=recode(distribution, normal="Normal", skewed="Skewed",
     pain="Pain score", bimodal="Bimodal"))
p5 <- ggplot(p5d, aes(factor(n_per_group), diff_AB, fill=factor(effect_size))) +
  geom_col(position=position_dodge(0.8), colour="grey40", linewidth=0.3) +
  geom_hline(yintercept=0) + facet_wrap(~distribution) +
  scale_fill_brewer(palette="Blues", name="Effect size d") +
  labs(x="n per group", y="Power difference A - B (percentage points)",
       title="Power cost of the incorrect (A) vs per-group (B) workflow",
       subtitle="Positive = incorrect better; negative = correct better") + theme_paper
ggsave("fig5_power_difference.pdf", p5, width=9, height=6)
ggsave("fig5_power_difference.png", p5, width=9, height=6, dpi=300)

# Max divergence between best and incorrect workflow (for abstract/discussion)
cat("\n===== SIMULATION: workflow gaps (d>0) =====\n")
gap <- sim %>% filter(effect_size>0) %>%
  mutate(best=pmax(power_B,power_C,power_D), gap_vs_A=(best-power_A)*100,
         gap_DA=(power_D-power_A)*100)
cat(sprintf("Max (best - A) power gap: %.1f pp\n", max(gap$gap_vs_A)))
print(gap %>% group_by(distribution) %>%
        summarise(max_gap_vs_A=round(max(gap_vs_A),1),
                  max_D_minus_A=round(max(gap_DA),1), .groups="drop"))
cat("\nPain-score, small n (<=20), d=0.5:\n")
print(sim %>% filter(distribution=="pain", n_per_group<=20, effect_size==0.5) %>%
        mutate(across(starts_with("power_"), ~round(100*.,1))) %>%
        select(n_per_group, power_A, power_B, power_C, power_D))

# ============================================================
#  TABLES
# ============================================================
table1 <- by_journal %>%
  transmute(Journal=journal_full, `Papers coded`=n_papers,
            `n incorrect`=n_incorrect, `% incorrect`=pct_incorrect)
write_csv(table1, "table1_results_by_journal.csv")

table2 <- sim %>% filter(effect_size==0.5, n_per_group %in% c(10,20,30,50)) %>%
  transmute(Distribution=recode(distribution, normal="Normal", skewed="Skewed",
              pain="Pain score", bimodal="Bimodal"),
            `n/group`=n_per_group,
            `A: Incorrect`=round(100*power_A,1), `B: Per-group`=round(100*power_B,1),
            `C: Welch`=round(100*power_C,1), `D: Mann-Whitney`=round(100*power_D,1))
write_csv(table2, "table2_simulation_power.csv")

cat("\n===== TABLE 1 =====\n"); print(table1, n=50)
cat("\n===== TABLE 2 =====\n"); print(table2, n=50)

# ---- Table 3: heteroscedastic scenario (unequal variances) ----
if (file.exists("simulation_hetero.csv")) {
  het <- read_csv("simulation_hetero.csv", show_col_types=FALSE)
  table3 <- het %>% filter(effect_size==0.5, n_per_group %in% c(10,20,30,50,100)) %>%
    transmute(`SD ratio`=ratio, `n/group`=n_per_group,
              `A: Incorrect`=round(100*power_A,1), `B: Per-group`=round(100*power_B,1),
              `C: Welch`=round(100*power_C,1), `D: Mann-Whitney`=round(100*power_D,1),
              `|A-B|`=round(100*abs(power_A-power_B),1)) %>%
    arrange(`SD ratio`, `n/group`)
  write_csv(table3, "table3_simulation_hetero.csv")
  het_t1 <- het %>% filter(effect_size==0) %>% group_by(ratio) %>%
    summarise(across(starts_with("power_"), ~round(100*mean(.x),1)), .groups="drop")
  cat("\n===== TABLE 3 (heteroscedastic, d=0.5) =====\n"); print(table3, n=50)
  cat("\nHeteroscedastic Type I (d=0), % by SD ratio:\n"); print(as.data.frame(het_t1))
  cat(sprintf("Heteroscedastic |A-B|: max=%.1f pp, mean=%.1f pp\n",
              100*max(abs(het$power_A-het$power_B)), 100*mean(abs(het$power_A-het$power_B))))
}

sink()
cat("\nAll figures and tables written.\n")
