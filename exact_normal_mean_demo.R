# ============================================================================
#  Sanity check for the Background claim: for NORMAL data the sample mean
#  (one-sample) and the difference in means (two-sample) are EXACTLY normal at
#  any sample size. This is a finite-sample consequence of the normal family
#  being closed under linear combinations of independent variables -- NOT the
#  central limit theorem.
#
#  Shown two ways:
#   (1)/(2) the statistic matches its exact theoretical N(.,.) already at tiny n;
#   (3) contrast with a non-normal (exponential) source, where the mean is only
#       approximately normal and the approximation merely improves with n (CLT).
#  Not part of the paper -- a methods sanity check.
# ============================================================================

set.seed(2025)
R <- 200000                                      # replications of the statistic
skew   <- function(x) mean(((x - mean(x)) / sd(x))^3)
exkurt <- function(x) mean(((x - mean(x)) / sd(x))^4) - 3
# distance to the EXACT theoretical normal (KS statistic D; ~0.86/sqrt(R) is the
# pure-sampling floor under H0, so values near it mean "indistinguishable from N")
Dnorm <- function(x, mu, sd) as.numeric(suppressWarnings(
  ks.test(x, "pnorm", mean = mu, sd = sd)$statistic))

cat(sprintf("R = %d replications;  pure-sampling KS floor ~ %.4f\n\n", R, 0.86/sqrt(R)))

# ---- (1) one-sample mean of NORMAL data: Xbar ~ N(mu, sigma^2/n) -------------
cat("== (1) one-sample mean, NORMAL source: Xbar ~ N(mu, sigma^2/n) ==\n")
mu <- 3; sigma <- 2
for (n in c(2, 3, 5, 10)) {
  xbar  <- replicate(R, mean(rnorm(n, mu, sigma)))
  th_sd <- sigma / sqrt(n)
  cat(sprintf("  n=%2d: mean %.3f (theo %.3f) | sd %.4f (theo %.4f) | skew %+.3f | exkurt %+.3f | D-to-N %.4f\n",
      n, mean(xbar), mu, sd(xbar), th_sd, skew(xbar), exkurt(xbar), Dnorm(xbar, mu, th_sd)))
}

# ---- (2) two-sample difference of means:
#          Xbar - Ybar ~ N(muX - muY, sigma^2 (1/m + 1/n)) ---------------------
cat("\n== (2) two-sample difference of means, NORMAL source ==\n")
muX <- 5; muY <- 3; sigma <- 2
for (mn in list(c(2, 2), c(3, 5), c(4, 10))) {
  m <- mn[1]; n <- mn[2]
  d     <- replicate(R, mean(rnorm(m, muX, sigma)) - mean(rnorm(n, muY, sigma)))
  th_sd <- sigma * sqrt(1/m + 1/n)
  cat(sprintf("  m=%d n=%2d: mean %.3f (theo %.3f) | sd %.4f (theo %.4f) | skew %+.3f | D-to-N %.4f\n",
      m, n, mean(d), muX - muY, sd(d), th_sd, skew(d), Dnorm(d, muX - muY, th_sd)))
}

# ---- (3) contrast: EXPONENTIAL source -> mean only approximately normal (CLT) -
cat("\n== (3) contrast: EXPONENTIAL source -- mean is NOT exactly normal ==\n")
for (n in c(2, 3, 5, 30, 200)) {
  xbar <- replicate(R, mean(rexp(n, rate = 1)))    # mean 1, sd 1/sqrt(n)
  cat(sprintf("  n=%3d: skew %+.3f | D-to-N %.4f\n", n, skew(xbar), Dnorm(xbar, 1, 1/sqrt(n))))
}

cat("\nNORMAL source: skew ~ 0 and D-to-N sits at the sampling floor for EVERY n\n")
cat("  (n = 2 included) -> the sample mean is EXACTLY normal; no CLT involved.\n")
cat("EXPONENTIAL source: skew and D-to-N are large at small n and only shrink as\n")
cat("  n grows -> normality there is asymptotic (the CLT), never exact.\n")
