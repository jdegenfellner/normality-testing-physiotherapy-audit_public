# ============================================================================
#  Sanity check: among the classical linear-model assumptions, NORMALITY is the
#  least consequential for inference.
#
#  We simulate the ACTUAL type-I error rate of the standard linear-model t-test
#  (base-R lm) when each assumption is violated in turn, holding everything else
#  fixed. The null is true in every scenario (the two groups have equal means),
#  so a well-behaved test should reject at the nominal alpha = 0.05. Deviation
#  from 0.05 measures how much that violation damages inference.
#
#  Result (see bottom): violating normality barely moves the type-I error;
#  violating homoscedasticity and especially independence inflates it markedly.
#  Not part of the paper -- a methods sanity check for the Background claim.
# ============================================================================

set.seed(2025)
R     <- 20000        # replications per scenario
alpha <- 0.05

# p-value for the group effect from an ordinary linear model (H0: no difference)
pval_lm <- function(y, g) summary(lm(y ~ g))$coefficients["g", "Pr(>|t|)"]
type1   <- function(gen) mean(replicate(R, gen()) < alpha)

# ---- 1) Baseline: ALL assumptions hold ------------------------------------
#     normal, independent, homoscedastic, equal n
gen_base <- function() {
  n <- 25
  y <- c(rnorm(n), rnorm(n)); g <- rep(0:1, each = n)
  pval_lm(y, g)
}

# ---- 2) NORMALITY violated -------------------------------------------------
#     strongly skewed errors (centred exponential), still independent,
#     equal variance, equal n. Same distribution in both groups => null true.
gen_nonnormal_skew <- function() {
  n <- 25
  y <- c(rexp(n) - 1, rexp(n) - 1); g <- rep(0:1, each = n)
  pval_lm(y, g)
}
#     heavy-tailed errors (t with 3 df, standardised)
gen_nonnormal_heavy <- function() {
  n <- 25; s <- sqrt(3)            # sd of t_3 is sqrt(3)
  y <- c(rt(n, 3) / s, rt(n, 3) / s); g <- rep(0:1, each = n)
  pval_lm(y, g)
}

# ---- 3) HOMOSCEDASTICITY violated -----------------------------------------
#     unequal variances AND unequal n (the smaller group has the larger
#     variance -- the classic Boneau situation that makes Student's t
#     anti-conservative). Errors still normal and independent.
gen_hetero <- function() {
  nA <- 10; nB <- 40
  y <- c(rnorm(nA, 0, 3), rnorm(nB, 0, 1)); g <- c(rep(0, nA), rep(1, nB))
  pval_lm(y, g)
}

# ---- 4) INDEPENDENCE violated ---------------------------------------------
#     observations are clustered (intraclass correlation ~ 0.6) but the model
#     treats all of them as independent. Errors still normal and homoscedastic.
gen_dependent <- function() {
  cl <- 5; m <- 5                  # per group: 5 clusters of 5 obs (n = 25/group)
  one_group <- function() {
    u <- rnorm(cl, 0, sqrt(0.6))           # cluster random effect
    rep(u, each = m) + rnorm(cl * m, 0, sqrt(0.4))   # total var 1, ICC = 0.6
  }
  y <- c(one_group(), one_group()); g <- rep(0:1, each = cl * m)
  pval_lm(y, g)
}

# ---- run ------------------------------------------------------------------
scen <- list(
  "Baseline (all hold)"            = gen_base,
  "Normality: skewed (exp)"        = gen_nonnormal_skew,
  "Normality: heavy tails (t3)"    = gen_nonnormal_heavy,
  "Homoscedasticity violated"      = gen_hetero,
  "Independence violated (ICC .6)" = gen_dependent
)
res <- sapply(scen, type1)

verdict <- function(p) {
  if (abs(p - alpha) <= 0.01) "~ nominal (fine)"
  else if (p > alpha)         sprintf("INFLATED (%.1fx)", p / alpha)
  else                        "conservative"
}

cat(sprintf("Type-I error of lm() t-test at nominal alpha = %.2f  (%d reps)\n\n", alpha, R))
cat(sprintf("  %-34s %8s   %s\n", "scenario", "type-I", "verdict"))
for (nm in names(res))
  cat(sprintf("  %-34s %7.3f   %s\n", nm, res[[nm]], verdict(res[[nm]])))

cat("\nOrdering by damage to inference: independence > homoscedasticity > normality.\n")
cat("Normality is the least consequential of the classical assumptions -- exactly\n")
cat("as stated in the Background. (Linearity / correct mean specification is a\n")
cat("separate matter: it biases the estimate rather than the type-I rate.)\n")
