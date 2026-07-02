# ============================================================================
#  Sanity check: t-tests and ANOVA are special cases of the linear model.
#  Not part of the paper — just demonstrates the three equivalences claimed in
#  the Background, using R's built-in datasets. Base R only (lme4 optional).
#
#  Equivalence is shown by reproducing the SAME estimate, t/F statistic and
#  p-value from the classical test and from lm().
# ============================================================================

cat("R", as.character(getRversion()), "\n\n")

approx_eq <- function(a, b, tol = 1e-8)
  isTRUE(all.equal(unname(a), unname(b), tolerance = tol))
ok <- function(x) if (x) "  [MATCH]" else "  [** MISMATCH **]"

# ----------------------------------------------------------------------------
# 1) Independent-samples t-test  ==  lm(y ~ binary indicator)
#    mtcars: mpg by transmission (am: 0 = automatic, 1 = manual).
#    NB: use var.equal = TRUE — OLS assumes a single common error variance,
#    so it matches the pooled (Student) t-test, not the Welch default.
# ----------------------------------------------------------------------------
cat("== 1. Independent-samples t-test  vs  lm(mpg ~ am) ==\n")
tt1 <- t.test(mpg ~ am, data = mtcars, var.equal = TRUE)
m1  <- lm(mpg ~ am, data = mtcars)
s1  <- summary(m1)$coefficients["am", ]

# t.test gives mean(group0) - mean(group1); lm's am coef gives group1 - group0.
diff_tt  <- diff(tt1$estimate)                 # mean(am=0) - mean(am=1)
diff_lm  <- unname(coef(m1)["am"])              # mean(am=1) - mean(am=0)
cat(sprintf("  mean difference : t.test % .4f | lm % .4f%s\n",
            diff_tt, diff_lm, ok(approx_eq(diff_tt, -diff_lm))))
cat(sprintf("  |t| statistic   : t.test % .4f | lm % .4f%s\n",
            abs(tt1$statistic), abs(s1["t value"]), ok(approx_eq(abs(unname(tt1$statistic)), abs(s1["t value"])))))
cat(sprintf("  p-value         : t.test % .6f | lm % .6f%s\n\n",
            tt1$p.value, s1["Pr(>|t|)"], ok(approx_eq(unname(tt1$p.value), unname(s1["Pr(>|t|)"])))))

# ----------------------------------------------------------------------------
# 2) One-way ANOVA  ==  lm(y ~ categorical factor)
#    PlantGrowth: dried plant weight under three conditions (ctrl, trt1, trt2).
# ----------------------------------------------------------------------------
cat("== 2. One-way ANOVA  vs  lm(weight ~ group) ==\n")
av2  <- summary(aov(weight ~ group, data = PlantGrowth))[[1]]
m2   <- lm(weight ~ group, data = PlantGrowth)
flm2 <- summary(m2)$fstatistic
F_aov <- av2["group", "F value"]
p_aov <- av2["group", "Pr(>F)"]
F_lm  <- unname(flm2["value"])
p_lm  <- pf(F_lm, flm2["numdf"], flm2["dendf"], lower.tail = FALSE)
cat(sprintf("  F statistic     : aov % .4f | lm % .4f%s\n",
            F_aov, F_lm, ok(approx_eq(F_aov, F_lm))))
cat(sprintf("  p-value         : aov % .6f | lm % .6f%s\n\n",
            p_aov, p_lm, ok(approx_eq(p_aov, unname(p_lm)))))

# ----------------------------------------------------------------------------
# 3) Paired t-test  ==  intercept-only lm on the within-pair differences
#    ==  linear model with a subject-specific intercept (subject as a fixed
#       factor; exact in base R) ==  random-intercept mixed model (lme4).
#    sleep: extra sleep for 10 subjects under two drugs (group 1 vs 2), ID-paired.
# ----------------------------------------------------------------------------
cat("== 3. Paired t-test  vs  lm(differences ~ 1)  vs  lm(+ subject intercept)  vs  mixed model ==\n")
g1  <- sleep$extra[sleep$group == 1]                         # ID-ordered 1..10
g2  <- sleep$extra[sleep$group == 2]
tt3 <- t.test(g1, g2, paired = TRUE)                         # group1 - group2
d   <- g1 - g2                                               # within-pair diffs
m3  <- lm(d ~ 1)                                             # intercept-only
s3  <- summary(m3)$coefficients["(Intercept)", ]
cat(sprintf("  mean difference : paired t % .4f | lm(d~1) % .4f%s\n",
            unname(tt3$estimate), unname(coef(m3)[1]), ok(approx_eq(unname(tt3$estimate), unname(coef(m3)[1])))))
cat(sprintf("  t statistic     : paired t % .4f | lm(d~1) % .4f%s\n",
            unname(tt3$statistic), s3["t value"], ok(approx_eq(unname(tt3$statistic), unname(s3["t value"])))))
cat(sprintf("  p-value         : paired t % .6f | lm(d~1) % .6f%s\n",
            tt3$p.value, s3["Pr(>|t|)"], ok(approx_eq(unname(tt3$p.value), unname(s3["Pr(>|t|)"])))))

# Equivalently: a linear model with a SUBJECT-SPECIFIC INTERCEPT, i.e. subject
# entered as a fixed factor. This reproduces the paired t-test exactly (same
# estimate, |t| and p), in base R with no mixed-model machinery. The sign of the
# group coefficient is flipped (group2 - group1 vs group1 - group2), so compare
# absolute values.
m3c <- lm(extra ~ group + factor(ID), data = sleep)        # subject-specific intercept
s3c <- summary(m3c)$coefficients["group2", ]
cat(sprintf("  |estimate|      : paired t % .4f | lm(+subj) % .4f%s\n",
            abs(unname(tt3$estimate)), abs(unname(s3c["Estimate"])),
            ok(approx_eq(abs(unname(tt3$estimate)), abs(unname(s3c["Estimate"]))))))
cat(sprintf("  |t| statistic   : paired t % .4f | lm(+subj) % .4f%s\n",
            abs(unname(tt3$statistic)), abs(unname(s3c["t value"])),
            ok(approx_eq(abs(unname(tt3$statistic)), abs(unname(s3c["t value"]))))))
cat(sprintf("  p-value         : paired t % .6f | lm(+subj) % .6f%s\n",
            tt3$p.value, s3c["Pr(>|t|)"], ok(approx_eq(unname(tt3$p.value), unname(s3c["Pr(>|t|)"])))))

# And once more as a random-intercept mixed model. With lme4 the fixed effect for
# group reproduces the paired estimate. (Optional — only runs if lme4 is installed.)
if (requireNamespace("lme4", quietly = TRUE)) {
  m3b <- lme4::lmer(extra ~ group + (1 | ID), data = sleep)
  fe  <- lme4::fixef(m3b)["group2"]
  cat(sprintf("  (mixed model)   : group2 fixed effect % .4f  vs  group2 - group1 % .4f%s\n",
              unname(fe), mean(g2) - mean(g1), ok(approx_eq(unname(fe), mean(g2) - mean(g1)))))
} else {
  cat("  (mixed-model check skipped: package 'lme4' not installed)\n")
}
cat("\nAll three classical tests are linear models in disguise.\n")
