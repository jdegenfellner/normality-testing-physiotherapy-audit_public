# ============================================================================
#  Sanity check: for a paired t-test, is testing pre and post SEPARATELY for
#  normality methodologically OK, or is it the wrong target?
#
#  The paired t-test == intercept-only linear model on the differences
#  d = post - pre.  Its normality assumption concerns the DIFFERENCES (the model
#  residuals), NOT the marginal distributions of pre and post.
#
#  Testing pre and post separately is neither NECESSARY nor SUFFICIENT for the
#  normality of d.  Two constructed counterexamples make both failures explicit.
#  Not part of the paper — a methods sanity check.
# ============================================================================

set.seed(2025)
n  <- 5000                                   # Shapiro-Wilk handles up to 5000
sw <- function(x) signif(shapiro.test(x)$p.value, 3)
verdict <- function(p) ifelse(p < 0.05, "REJECT normal", "looks normal")
line <- function(lab, p) cat(sprintf("  %-26s Shapiro p = %-9s -> %s\n",
                                      lab, format(p), verdict(p)))

# ----------------------------------------------------------------------------
# Counterexample A — separate testing is NOT NECESSARY.
#   pre and post each strongly skewed, but the differences are exactly normal.
#   Shared skewed baseline Z (e.g. a bounded/skewed physiotherapy score) plus an
#   independent normal change d:  pre = Z,  post = Z + d  =>  post - pre = d ~ N.
# ----------------------------------------------------------------------------
cat("== Case A: pre & post non-normal, but DIFFERENCES normal ==\n")
Z    <- rgamma(n, shape = 1.5, rate = 1)     # skewed baseline (same subjects)
dA   <- rnorm(n, mean = 0.5, sd = 0.5)       # true change, normal
preA <- Z
postA <- Z + dA
line("pre  (separate test)",  sw(preA))
line("post (separate test)",  sw(postA))
line("differences (correct)", sw(postA - preA))
cat("  -> separate tests REJECT, yet the paired t-test assumption is perfectly met.\n\n")

# ----------------------------------------------------------------------------
# Counterexample B — separate testing is NOT SUFFICIENT.
#   pre and post each EXACTLY standard normal (marginally), but the differences
#   are grossly non-normal.  Reflect U about 0 on its central region: this leaves
#   each marginal N(0,1) (the normal density is symmetric) yet makes pre - post
#   degenerate in the tails and bimodal in the centre -> not bivariate normal.
# ----------------------------------------------------------------------------
cat("== Case B: pre & post each exactly N(0,1), but DIFFERENCES non-normal ==\n")
U    <- rnorm(n)
cc   <- 1.0
preB <- U
postB <- ifelse(abs(U) <= cc, -U, U)         # still N(0,1) marginally
line("pre  (separate test)",  sw(preB))
line("post (separate test)",  sw(postB))
line("differences (correct)", sw(preB - postB))
cat("  -> separate tests PASS, yet the differences badly violate normality.\n\n")

# ----------------------------------------------------------------------------
# And: the 'differences' test IS the residual test of the paired-t linear model.
# ----------------------------------------------------------------------------
cat("== The correct target equals the linear-model residuals ==\n")
dB  <- preB - postB
mB  <- lm(dB ~ 1)                             # paired t-test as a linear model
cat(sprintf("  Shapiro on differences      p = %s\n", format(sw(dB))))
cat(sprintf("  Shapiro on lm(d~1) residuals p = %s   (identical target)\n",
            format(sw(resid(mB)))))

cat("\nConclusion: testing pre and post separately tests the WRONG quantity.\n")
cat("For a paired/pre-post design the normality check belongs on the\n")
cat("within-pair differences (= the model residuals), not on the two\n")
cat("time points individually. Separate testing is therefore incorrect,\n")
cat("not merely the 'acceptable' per-group practice of a between-subjects design.\n")
