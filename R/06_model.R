# Step 7: baseline adjusted logistic regression (inference, no interactions).
# Run from the project root: source("R/06_model.R")
# Install once if needed: install.packages(c("dplyr", "readr", "sandwich"))
# Cluster-robust covariance documentation:
# https://sandwich.r-forge.r-project.org/reference/vcovCL.html
# Predictive train/test evaluation and interaction models are later steps.

for (pkg in c("dplyr", "readr", "sandwich")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr)})
input_path <- "data/processed/occupants_scenarios.rds"
occ <- readRDS(input_path)
stopifnot(!anyNA(occ$accident_no),
          !anyDuplicated(occ[c("accident_no", "person_id")]),
          !anyNA(occ$ksi), all(occ$ksi %in% c(0L, 1L)))

# Use the existing cleaning decisions. Unknown configurations are not
# treated as known crash circumstances. All exclusions below are local
# to this model; the source data remains unchanged.
# Calendar year also controls for broad changes during the study period.
data <- occ %>% mutate(
  sex = factor(sex, levels = c("Male", "Female")),
  age_band = factor(age_band, levels = c("16-25", "26-39", "40-59", "60+")),
  seat = factor(seat, levels = c("Driver", "Front passenger")),
  speed_band = factor(speed_band, levels = c("50 or less", "60-70", "75-90", "100-110")),
  impact = factor(impact, levels = c("Front", "Side", "Rear", "Other")),
  crash_configuration = factor(crash_configuration, levels = c(
    "Rear-end", "Head-on (not overtaking)", "Adjacent-direction intersection",
    "Opposing-direction turning", "Run-off-road", "Loss of control on carriageway",
    "Other known configurations")),
  crash_year_numeric = as.integer(accident_year),
  vehicle_year_model = ifelse(vehicle_year > crash_year_numeric, NA, vehicle_year),
  vehicle_year_10 = (vehicle_year_model - 2010) / 10,
  tare_500kg = (tare_kg - 1500) / 500,
  vehicle_count = as.integer(no_of_vehicles),
  vehicle_count_group = factor(case_when(
    vehicle_count == 1 ~ "1", vehicle_count == 2 ~ "2", vehicle_count >= 3 ~ "3+"
  ), levels = c("1", "2", "3+")),
  crash_year = factor(crash_year_numeric)
)
formula <- ksi ~ sex + age_band + seat + speed_band + crash_configuration +
  impact + vehicle_count_group + vehicle_year_10 + tare_500kg + crash_year
variables <- all.vars(formula)
missing_counts <- tibble(variable = variables,
                         missing_or_unknown = colSums(is.na(data[variables])))
eligible <- complete.cases(data[variables])
cohort <- droplevels(data[eligible, ])
stopifnot(nrow(cohort) > 0, n_distinct(cohort$sex) == 2)

# Sequential counts are additive; per-variable missing counts overlap.
keep <- rep(TRUE, nrow(data))
filter_counts <- tibble(step = "All clean occupants", before = nrow(data),
                        after = nrow(data), removed = 0L)
for (nm in variables) {
  before <- sum(keep)
  keep <- keep & !is.na(data[[nm]])
  filter_counts <- bind_rows(filter_counts, tibble(
    step = paste("Require", nm), before = before, after = sum(keep), removed = before - sum(keep)))
}
stopifnot(identical(keep, eligible))
coverage <- data %>% mutate(included = eligible) %>% group_by(included, sex) %>%
  summarise(occupants = n(), ksi_count = sum(ksi), ksi_pct = 100 * mean(ksi), .groups = "drop")
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
write_csv(missing_counts, "outputs/tables/07_baseline_missing.csv")
write_csv(filter_counts, "outputs/tables/07_baseline_filter_counts.csv")
write_csv(coverage, "outputs/tables/07_baseline_coverage.csv")
cat("Modelling", nrow(cohort), "occupants across", n_distinct(cohort$accident_no), "crashes.\n")
print(coverage)

# Full complete-case cohort for association estimates. No held-out
# predictive-performance claim is made. All continuous effects are linear
# on the log-odds scale in this first model; later checks can relax that.
fit <- glm(formula, data = cohort, family = binomial(link = "logit"),
           na.action = na.fail, control = glm.control(maxit = 50))
if (!fit$converged || anyNA(coef(fit)) || any(!is.finite(coef(fit)))) {
  stop("Model did not converge or has unidentified coefficients; inspect before interpreting.")
}
stopifnot(nobs(fit) == nrow(cohort))
robust_vcov <- sandwich::vcovCL(fit, cluster = cohort$accident_no,
                              type = "HC1", cadjust = TRUE)
if (any(!is.finite(robust_vcov)) || any(diag(robust_vcov) <= 0)) {
  stop("Invalid cluster-robust covariance matrix.")
}
beta <- coef(fit)
se <- sqrt(diag(robust_vcov))
critical <- qnorm(0.975)
odds_ratios <- tibble(
  term = names(beta), log_odds = unname(beta), robust_se = unname(se),
  adjusted_odds_ratio = exp(beta), ci_low = exp(beta - critical * se),
  ci_high = exp(beta + critical * se),
  p_value = 2 * pnorm(abs(beta / se), lower.tail = FALSE)
)
write_csv(odds_ratios, "outputs/tables/07_baseline_odds_ratios.csv")

# Reference levels and continuous scales make the coefficient table usable.
references <- tibble(
  variable = c("sex", "age_band", "seat", "speed_band", "crash_configuration",
               "impact", "vehicle_count_group", "crash_year", "vehicle_year_10", "tare_500kg"),
  interpretation = c("Female versus Male", "Versus age 16-25", "Front passenger versus Driver",
    "Versus speed zone 50 or less", "Versus Rear-end", "Versus Front impact",
    "Versus 1 vehicle; 3+ combines crashes with three or more vehicles",
    paste("Versus crash year", levels(cohort$crash_year)[1]),
    "Per 10 newer manufacturing years; centred at 2010",
    "Per 500 kg higher tare weight; centred at 1500 kg")
)
write_csv(references, "outputs/tables/07_baseline_references.csv")

# Standardise over the SAME observed covariate distribution for both sexes.
# These are model-based associations, not causal intervention estimates.
# Delta-method intervals use the clustered covariance, treating the
# empirical covariate distribution as fixed. Logistic intervals stay in 0-1.
standardised <- bind_rows(lapply(c("Male", "Female"), function(label) {
  newdata <- cohort
  newdata$sex <- factor(label, levels = levels(cohort$sex))
  design <- model.matrix(delete.response(terms(fit)), newdata,
                         contrasts.arg = fit$contrasts, xlev = fit$xlevels)
  stopifnot(identical(colnames(design), names(beta)))
  probability <- plogis(drop(design %*% beta))
  mean_probability <- mean(probability)
  gradient <- colMeans(design * as.numeric(probability * (1 - probability)))
  variance <- drop(t(gradient) %*% robust_vcov %*% gradient)
  stopifnot(is.finite(variance), variance >= 0)
  logit_se <- sqrt(variance) / (mean_probability * (1 - mean_probability))
  tibble(sex = label, standardised_ksi_pct = 100 * mean_probability,
         ci_low_pct = 100 * plogis(qlogis(mean_probability) - critical * logit_se),
         ci_high_pct = 100 * plogis(qlogis(mean_probability) + critical * logit_se))
}))
write_csv(standardised, "outputs/tables/07_baseline_standardised_rates.csv")

diagnostics <- tibble(
  occupants = nrow(cohort), excluded = sum(!eligible), crashes = n_distinct(cohort$accident_no),
  ksi_cases = sum(cohort$ksi), parameters = length(beta), converged = fit$converged,
  iterations = fit$iter, min_fitted = min(fitted(fit)), max_fitted = max(fitted(fit)),
  future_manufacture_rows = sum(occ$vehicle_year > as.integer(occ$accident_year), na.rm = TRUE)
)
write_csv(diagnostics, "outputs/tables/07_baseline_diagnostics.csv")
saveRDS(list(model = fit, cluster_robust_vcov = robust_vcov,
             cohort_keys = cohort[c("accident_no", "vehicle_id", "person_id")],
             purpose = "Full-cohort baseline association model; no predictive evaluation",
             input_md5 = unname(tools::md5sum(input_path)), session_info = sessionInfo()),
        "data/processed/baseline_logistic_model.rds")
capture.output(
  cat("MODEL-BASED STANDARD ERRORS BELOW. For inference use 07_baseline_odds_ratios.csv,\n",
      "which uses crash-cluster-robust HC1 standard errors and confidence intervals.\n\n"),
  summary(fit), file = "outputs/tables/07_baseline_glm_summary.txt")
# glm's summary contains model-based SEs. Use the saved robust OR table for inference.
capture.output(sessionInfo(), file = "outputs/tables/07_baseline_session_info.txt")
cat("\nFemale versus male, adjusted odds ratio with crash-robust 95% CI:\n")
print(filter(odds_ratios, term == "sexFemale"))
cat("\nStandardised KSI percentages:\n")
print(standardised)
cat("\nSaved baseline model and tables. Interactions and predictive evaluation remain.\n")
