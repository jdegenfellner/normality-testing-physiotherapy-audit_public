# ============================================================================
#  Sanity check for the Methods claim that, for a BALANCED two-group design,
#  testing normality WITHIN EACH GROUP is equivalent to testing the model
#  RESIDUALS -- and that both differ fundamentally from testing the POOLED RAW
#  data (the audited error).
#
#  Three facts:
#   (1) EXACT identity. The OLS residuals of a two-group model are the
#       within-group centred values, and Shapiro-Wilk is location-invariant, so
#       the per-group test and the residual test operate on the SAME numbers and
#       return IDENTICAL p-values.
#   (2) WHY IT MATTERS. Residual / per-group testing is immune to the
#       between-group mean difference, whereas testing the pooled raw data
#       rejects ever more often as that difference grows -- even when BOTH groups
#       are perfectly normal. (per-group runs two tests, so it sits a little above
#       the residual rate by multiplicity alone, but is equally flat in the gap.)
#   (3) WHY "BALANCED". The pooled-residual test weights the groups by sample
#       size, whereas per-group testing weights them equally. With equal n the two
#       coincide; with unequal n the pooled residuals are dominated by the larger
#       group, so a single non-normal group is increasingly DILUTED and the
#       residual test misses what per-group testing still catches.
#
#  Not part of the paper -- a methods sanity check.
# ============================================================================

set.seed(2025)
alpha <- 0.05
sw <- function(x) shapiro.test(x)$p.value

# ---- (1) residuals ARE within-group centred values; SW is location-invariant -
cat("== (1) per-group test  ==  residual test  (exactly the same numbers) ==\n")
nA <- nB <- 30
a <- rnorm(nA, mean = 5,  sd = 2)          # group A
b <- rnorm(nB, mean = 50, sd = 2)          # group B, far higher mean
g <- factor(rep(c("A", "B"), c(nA, nB))); y <- c(a, b)
res  <- residuals(lm(y ~ g))               # OLS residuals = y - its group mean
resA <- res[g == "A"]; resB <- res[g == "B"]
cat(sprintf("  residuals == within-group deviations?  max|resA-(a-mean a)|=%.1e  max|resB-(b-mean b)|=%.1e\n",
            max(abs(resA - (a - mean(a)))), max(abs(resB - (b - mean(b))))))
cat(sprintf("  SW(group A raw)=%.4f  SW(residuals of A)=%.4f  identical: %s\n",
            sw(a), sw(resA), isTRUE(all.equal(sw(a), sw(resA)))))
cat(sprintf("  SW(group B raw)=%.4f  SW(residuals of B)=%.4f  identical: %s\n",
            sw(b), sw(resB), isTRUE(all.equal(sw(b), sw(resB)))))

# ---- (2) immune to the between-group shift (both groups NORMAL, n=30/grp) -----
cat("\n== (2) rejection rate vs between-group mean gap (both groups NORMAL) ==\n")
R <- 5000
rates <- function(delta) {
  raw <- rp <- pg <- 0
  for (i in 1:R) {
    a <- rnorm(30, 0, 1); b <- rnorm(30, delta, 1)
    g <- factor(rep(c("A", "B"), each = 30)); y <- c(a, b)
    rr <- residuals(lm(y ~ g))
    raw <- raw + (sw(y)  < alpha)                       # WRONG: pooled raw data
    rp  <- rp  + (sw(rr) < alpha)                       # residuals
    pg  <- pg  + ((sw(a) < alpha) | (sw(b) < alpha))    # per-group (either fails)
  }
  c(raw = raw / R, residuals = rp / R, per_group = pg / R)
}
cat(sprintf("  %-7s %11s %11s %11s\n", "gap d", "pooled-RAW", "residuals", "per-group"))
for (d in c(0, 1, 2, 4, 8)) {
  r <- rates(d)
  cat(sprintf("  %-7.0f %10.1f%% %10.1f%% %10.1f%%\n",
              d, 100 * r["raw"], 100 * r["residuals"], 100 * r["per_group"]))
}
cat("  -> residuals & per-group stay flat (immune to the gap); pooled-raw inflates with it.\n")

# ---- (3) why the equivalence needs BALANCED n --------------------------------
cat("\n== (3) balanced vs unbalanced: power to detect a non-normal small group ==\n")
cat("   group A NORMAL, group B SKEWED (exp). Detection = test of B's distribution.\n\n")
detect <- function(nA, nB) {
  rp <- pg <- 0
  for (i in 1:R) {
    a <- rnorm(nA, 0, 1); b <- (rexp(nB, 1) - 1)            # B is skewed
    g <- factor(rep(c("A", "B"), c(nA, nB))); y <- c(a, b)
    rr <- residuals(lm(y ~ g))
    rp <- rp + (sw(rr)        < alpha)        # one test on the pooled residuals
    pg <- pg + (sw(b)         < alpha)        # per-group: test group B directly
  }
  c(pooled_residuals = rp / R, per_group_B = pg / R)
}
bal <- detect(30, 30); unb <- detect(90, 10)
cat(sprintf("  BALANCED   nA=30 nB=30:  pooled-residual test %5.1f%%  |  per-group(B) %5.1f%%  (both flag B)\n",
            100 * bal["pooled_residuals"], 100 * bal["per_group_B"]))
cat(sprintf("  UNBALANCED nA=90 nB=10:  pooled-residual test %5.1f%%  |  per-group(B) %5.1f%%  (residual misses)\n",
            100 * unb["pooled_residuals"], 100 * unb["per_group_B"]))
cat("  -> the large normal group dilutes B's skew in the pooled residuals; the dilution is mild\n")
cat("     when balanced (both still flag B) but severe when unbalanced (the residual test largely\n")
cat("     misses what per-group still catches). Hence the equivalence is stated for BALANCED designs.\n")
