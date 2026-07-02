# ============================================================================
#  Sanity check for the Methods claim that the t-test and the Mann-Whitney U
#  test do NOT in general test the same hypothesis:
#    * the t-test concerns the difference in MEANS;
#    * Mann-Whitney concerns stochastic ordering, P(X < Y) != 1/2.
#
#  Two facts are demonstrated, matching the paper (cf. Fay & Proschan 2010,
#  Statistics Surveys 4:1-39):
#   (1) Under a PURE LOCATION SHIFT the two hypotheses coincide -- the mean
#       shift, the median shift and the stochastic-dominance quantity
#       (P(X<Y) - 1/2) all carry the SAME sign, so the two tests agree in
#       direction. This is the scope condition under which our power comparison
#       is well defined.
#   (2) When the SHAPE also changes between groups, the two can point in
#       OPPOSITE directions: one group has the larger mean while the other is
#       stochastically larger (P(X<Y) - 1/2 has the opposite sign to the mean
#       difference), so a "significant" t-test and a "significant" Mann-Whitney
#       test answer materially different questions.
#
#  Not part of the paper -- a methods sanity check.
# ============================================================================

set.seed(2025)

# Population P(X < Y) for independent X (group A) and Y (group B), the quantity
# the Mann-Whitney test is consistent for. Estimated from a huge sample so the
# numbers below are essentially the POPULATION truths, not sampling noise.
P_XlessY <- function(rA, rB, M = 5e6) {
  x <- rA(M); y <- rB(M)
  mean(x < y) + 0.5 * mean(x == y)          # mid-rank handling of ties
}

report <- function(label, rA, rB) {
  M  <- 5e6
  xa <- rA(M); xb <- rB(M)
  dmean <- mean(xb)   - mean(xa)            # mean(B) - mean(A)
  dmed  <- median(xb) - median(xa)          # median(B) - median(A)
  p     <- P_XlessY(rA, rB)                 # P(A < B)
  sm <- sign(dmean); smd <- sign(dmed); sp <- sign(p - 0.5)
  cat(sprintf("  %-34s mean(B)-mean(A) %+6.3f | median(B)-median(A) %+6.3f | P(A<B)-1/2 %+6.3f\n",
              label, dmean, dmed, p - 0.5))
  cat(sprintf("  %-34s sign(mean diff)=%+d  sign(median diff)=%+d  sign(P(A<B)-1/2)=%+d  -> %s\n\n",
              "", sm, smd, sp,
              if (sm == sp) "AGREE in direction" else "OPPOSITE directions"))
  invisible(c(dmean = dmean, dmed = dmed, pmid = p - 0.5))
}

cat("== (1) PURE LOCATION SHIFT: hypotheses coincide (all signs agree) ==\n")
cat("   B is A shifted right by delta>0; only the location changes.\n\n")
shift <- 0.6
report("normal,   shift +0.6",  function(n) rnorm(n),               function(n) rnorm(n) + shift)
report("skewed,   shift +0.6",  function(n) rgamma(n, 2, 1) - 2,    function(n) rgamma(n, 2, 1) - 2 + shift)
report("heavy t3, shift +0.6",  function(n) rt(n, 3),               function(n) rt(n, 3) + shift)

cat("== (2) SHAPE CHANGES TOO: t-test and Mann-Whitney point OPPOSITE ways ==\n")
cat("   A ~ N(0,1).  B is small 90% of the time but has a rare huge spike, so\n")
cat("   mean(B) > mean(A) (t-test favours B) yet a random A usually exceeds a\n")
cat("   random B, i.e. P(A<B) < 1/2 (Mann-Whitney favours A).\n\n")
rA <- function(n) rnorm(n, 0, 1)
rB <- function(n) {                          # 90% near -1, 10% a large spike at +20
  z <- rbinom(n, 1, 0.10)
  ifelse(z == 1, rnorm(n, 20, 1), rnorm(n, -1, 0.5))
}
report("A=N(0,1) vs B=spiked mixture", rA, rB)

# Confirm it shows up in the actual TESTS on a finite sample (not just the
# population quantities): same data, opposite verdicts.
n <- 400
a <- rA(n); b <- rB(n)
pt <- t.test(a, b)                            # H0: equal means
pw <- suppressWarnings(wilcox.test(a, b))     # H0: P(A<B) = 1/2
cat(sprintf("\n  finite sample (n=%d/group):\n", n))
cat(sprintf("    t-test:        mean(A)=%+.2f mean(B)=%+.2f  diff=%+.2f  p=%.1e  -> B has larger MEAN\n",
            mean(a), mean(b), mean(b) - mean(a), pt$p.value))
cat(sprintf("    Mann-Whitney:  P(A<B)-hat=%.3f  p=%.1e  -> A is stochastically LARGER\n",
            mean(outer(a, b, "<")) + 0.5 * mean(outer(a, b, "==")), pw$p.value))
cat("    => both 'significant', opposite directions: they test different hypotheses.\n")

cat("\nConclusion: under a location shift the t-test and Mann-Whitney agree in\n")
cat("direction (our simulation's scope condition); once shapes differ they can\n")
cat("disagree outright -- exactly as stated in the Methods (Fay & Proschan 2010).\n")
