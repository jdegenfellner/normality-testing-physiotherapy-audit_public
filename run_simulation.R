suppressMessages({library(tidyverse)})
set.seed(2025)

# ---------------------------------------------------------------------------
# Data-generating distributions (null shape) and their SDs. The group effect is
# applied in SD units so that effect_size is a genuine Cohen's d for every
# distribution (normal has SD 1, so it is unchanged).
#   pain = realistic zero-inflated 0-10 NRS, calibrated to published clinical
#   pain data (Goulet et al. 2016: mean ~3, var ~7.5, ~34% zeros, ~13% >=7):
#   34% structural zeros + a right-skewed gamma positive part, rounded to 0-10.
# ---------------------------------------------------------------------------
pain_null <- function(n) {
  z <- rbinom(n, 1, 0.34)                              # structural "no pain"
  y <- pmax(1, round(rgamma(n, shape = 2.5, rate = 0.55)))
  pmin(ifelse(z == 1, 0, y), 10)
}
SD_PAIN <- sd(pain_null(2e6))                          # ~2.95
SDs <- c(normal = 1, skewed = sqrt(2), bimodal = sqrt(1.25), pain = SD_PAIN)

gen_null <- function(n, dist) switch(dist,
  "normal"  = rnorm(n, 0, 1),
  "skewed"  = rgamma(n, shape = 2, rate = 1) - 2,
  "pain"    = pain_null(n),
  "bimodal" = { g <- rbinom(n, 1, 0.5); ifelse(g == 0, rnorm(n, -1, 0.5), rnorm(n, 1, 0.5)) }
)
gen_sample <- function(n, dist, d) {
  x <- gen_null(n, dist) + d * SDs[[dist]]             # effect in SD units = Cohen's d
  if (dist == "pain") x <- pmin(pmax(round(x), 0), 10) # keep pain on the 0-10 NRS
  x
}
sim_two_groups <- function(n_per_group, dist, effect_size)
  list(group_A = gen_sample(n_per_group, dist, 0),
       group_B = gen_sample(n_per_group, dist, effect_size))

is_normal <- function(x, alpha = 0.05) {
  if (length(x) < 3) return(TRUE)
  tryCatch(shapiro.test(x)$p.value > alpha, error = function(e) TRUE)
}
.wx <- function(a, b) suppressWarnings(wilcox.test(a, b)$p.value)   # ties -> normal approx
workflow_A <- function(a,b,at=0.05,an=0.05){ if(is_normal(c(a,b),an)) t.test(a,b)$p.value<at else .wx(a,b)<at }
workflow_B <- function(a,b,at=0.05,an=0.05){ if(is_normal(a,an)&is_normal(b,an)) t.test(a,b)$p.value<at else .wx(a,b)<at }
workflow_C <- function(a,b,at=0.05,...) t.test(a,b)$p.value<at
workflow_D <- function(a,b,at=0.05,...) .wx(a,b)<at

sim_params <- expand.grid(n_per_group=c(10,20,30,50,100), effect_size=c(0,0.2,0.5,0.8),
  distribution=c("normal","skewed","pain","bimodal"), stringsAsFactors=FALSE)
N_SIM <- 10000

run_cell <- function(row){
  n<-row$n_per_group; d<-row$effect_size; dst<-row$distribution
  res <- replicate(N_SIM,{ dat<-sim_two_groups(n,dst,d)
    c(A=workflow_A(dat$group_A,dat$group_B), B=workflow_B(dat$group_A,dat$group_B),
      C=workflow_C(dat$group_A,dat$group_B), D=workflow_D(dat$group_A,dat$group_B)) })
  data.frame(n_per_group=n, effect_size=d, distribution=dst,
    power_A=mean(res["A",]), power_B=mean(res["B",]), power_C=mean(res["C",]), power_D=mean(res["D",]))
}
cat(sprintf("SD_PAIN = %.2f\n", SD_PAIN))
cat(sprintf("Running %d cells x %d reps...\n", nrow(sim_params), N_SIM))
sim_results <- map_dfr(seq_len(nrow(sim_params)), function(i){ run_cell(sim_params[i,]) })
write_csv(sim_results, "simulation_results.csv")
cat("SIMULATION DONE. Rows:", nrow(sim_results), "\n")
type1 <- sim_results %>% filter(effect_size==0) %>% summarise(across(starts_with("power_"), mean))
cat("Type I error rates:\n"); print(round(type1,3))

# ---------------------------------------------------------------------------
# Heteroscedastic scenario: the adversarial case for the raw-vs-residual error.
# Both groups are NORMAL, but group B has a larger SD (SD ratio r). Pooling
# two normals of different variance can look non-normal, so the INCORRECT pooled
# workflow A may flip to Mann-Whitney while the per-group workflow B correctly
# keeps the (Welch) t-test. The downstream t-test is Welch throughout, which
# isolates the effect of WHERE normality is tested from the separate issue of
# unequal variances. d is the mean shift in control-group SD units (Glass's delta).
# ---------------------------------------------------------------------------
gen_hetero <- function(n, d, r) list(group_A = rnorm(n, 0, 1),
                                     group_B = rnorm(n, d, r))
het_params <- expand.grid(n_per_group=c(10,20,30,50,100), effect_size=c(0,0.2,0.5,0.8),
  ratio=c(2,3), stringsAsFactors=FALSE)
run_het <- function(row){
  n<-row$n_per_group; d<-row$effect_size; r<-row$ratio
  res <- replicate(N_SIM,{ dat<-gen_hetero(n,d,r)
    c(A=workflow_A(dat$group_A,dat$group_B), B=workflow_B(dat$group_A,dat$group_B),
      C=workflow_C(dat$group_A,dat$group_B), D=workflow_D(dat$group_A,dat$group_B)) })
  data.frame(n_per_group=n, effect_size=d, ratio=r,
    power_A=mean(res["A",]), power_B=mean(res["B",]), power_C=mean(res["C",]), power_D=mean(res["D",]))
}
het_results <- map_dfr(seq_len(nrow(het_params)), function(i) run_het(het_params[i,]))
write_csv(het_results, "simulation_hetero.csv")
cat("HETERO SIM DONE. Rows:", nrow(het_results), "\n")
het_t1 <- het_results %>% filter(effect_size==0) %>% group_by(ratio) %>%
  summarise(across(starts_with("power_"), mean), .groups="drop")
cat("Hetero Type I (d=0) by SD ratio:\n"); print(as.data.frame(round(het_t1,3)))
het_div <- het_results %>% mutate(div=abs(power_A-power_B))
cat(sprintf("Hetero |power_A - power_B|: max=%.1f pp, mean=%.1f pp\n",
            100*max(het_div$div), 100*mean(het_div$div)))
