# Step 7: does the adjusted female/male gap change with vehicle year?
# Run after R/06_model.R from the project root.
# Adds one sex x manufacture-year term; keeps the baseline cohort/controls.
# Inference uses crash-cluster-robust HC1 covariance, as in the baseline.
# https://sandwich.r-forge.r-project.org/reference/vcovCL.html

for (pkg in c("dplyr", "readr", "ggplot2", "sandwich")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
baseline_path <- "data/processed/baseline_logistic_model.rds"
baseline <- readRDS(baseline_path)
stopifnot(identical(baseline$input_md5,
                    unname(tools::md5sum("data/processed/occupants_scenarios.rds"))))
cohort <- baseline$model$model
stopifnot(nrow(cohort) == nrow(baseline$cohort_keys))
interaction_formula <- update(formula(baseline$model), . ~ . + sex:vehicle_year_10)
fit <- glm(interaction_formula, data = cohort, family = binomial(),
           na.action = na.fail, control = glm.control(maxit = 50))
stopifnot(fit$converged, !anyNA(coef(fit)), all(is.finite(coef(fit))),
          nobs(fit) == nobs(baseline$model),
          identical(rownames(fit$model), rownames(baseline$model$model)))
V <- sandwich::vcovCL(fit, cluster = baseline$cohort_keys$accident_no,
                      type = "HC1", cadjust = TRUE)
stopifnot(all(is.finite(V)), all(diag(V) > 0))
beta <- coef(fit)
se <- sqrt(diag(V))
critical <- qnorm(0.975)
term <- "sexFemale:vehicle_year_10"
stopifnot(term %in% names(beta))
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

# The interaction OR is a RATIO OF ODDS RATIOS per decade. The sex main
# effect now applies to manufacture year 2010, not all years equally.
coefficients <- tibble(term = names(beta), log_odds = unname(beta),
  robust_se = unname(se), odds_ratio = exp(beta),
  ci_low = exp(beta - critical * se), ci_high = exp(beta + critical * se),
  p_value = 2 * pnorm(abs(beta / se), lower.tail = FALSE))
interaction_test <- tibble(
  term = term, log_or_change_per_decade = unname(beta[term]),
  ratio_of_odds_ratios_per_decade = unname(exp(beta[term])),
  ci_low = unname(exp(beta[term] - critical * se[term])),
  ci_high = unname(exp(beta[term] + critical * se[term])),
  wald_chisq = unname((beta[term] / se[term])^2), df = 1L,
  p_value = unname(pchisq((beta[term] / se[term])^2, df = 1, lower.tail = FALSE))
)
write_csv(coefficients, "outputs/tables/07_year_interaction_coefficients.csv")
write_csv(interaction_test, "outputs/tables/07_year_interaction_test.csv")

# Plot a well-populated range, not the sparse extremes of 1960-2024.
# Fit still uses the FULL baseline cohort. Support counts are exported.
years <- seq(1995L, 2020L, by = 5L)
support <- cohort %>%
  mutate(vehicle_year = as.integer(round(vehicle_year_10 * 10 + 2010))) %>%
  count(vehicle_year, sex, name = "occupants")
write_csv(support, "outputs/tables/07_year_interaction_support.csv")
or_by_year <- bind_rows(lapply(years, function(year) {
  contrast <- setNames(rep(0, length(beta)), names(beta))
  contrast["sexFemale"] <- 1
  contrast[term] <- (year - 2010) / 10
  estimate <- sum(contrast * beta)
  error <- sqrt(drop(t(contrast) %*% V %*% contrast))
  tibble(vehicle_year = year, female_male_adjusted_or = exp(estimate),
         ci_low = exp(estimate - critical * error), ci_high = exp(estimate + critical * error))
}))
write_csv(or_by_year, "outputs/tables/07_year_interaction_sex_or.csv")

# For probability curves use ONE fixed reference population: complete-case
# occupants in crashes from 2020 onward. This avoids assigning a 2020
# vehicle to a crash that happened before 2020. Both sexes/all plotted years
# use the same covariates. Probabilities therefore describe this reference
# population, not raw rates or the entire 2012-2024 population.
reference <- cohort[as.integer(as.character(cohort$crash_year)) >= max(years), ]
stopifnot(nrow(reference) > 0)
standardise <- function(year, label) {
  newdata <- reference
  newdata$sex <- factor(label, levels = levels(cohort$sex))
  newdata$vehicle_year_10 <- (year - 2010) / 10
  X <- model.matrix(delete.response(terms(fit)), newdata,
                     contrasts.arg = fit$contrasts, xlev = fit$xlevels)
  stopifnot(identical(colnames(X), names(beta)))
  probabilities <- plogis(drop(X %*% beta))
  mean_p <- mean(probabilities)
  gradient <- colMeans(X * as.numeric(probabilities * (1 - probabilities)))
  variance <- drop(t(gradient) %*% V %*% gradient)
  stopifnot(is.finite(variance), variance >= 0)
  logit_se <- sqrt(variance) / (mean_p * (1 - mean_p))
  list(probability = mean_p, gradient = gradient,
       row = tibble(vehicle_year = year, sex = label,
         reference_occupants = nrow(reference), ksi_pct = 100 * mean_p,
         ci_low_pct = 100 * plogis(qlogis(mean_p) - critical * logit_se),
         ci_high_pct = 100 * plogis(qlogis(mean_p) + critical * logit_se)))
}
rate_rows <- list()
gap_rows <- list()
gap_gradients <- list()
for (i in seq_along(years)) {
  male <- standardise(years[i], "Male")
  female <- standardise(years[i], "Female")
  rate_rows[[i]] <- bind_rows(male$row, female$row)
  gap <- female$probability - male$probability
  gradient <- female$gradient - male$gradient
  gap_se <- sqrt(drop(t(gradient) %*% V %*% gradient))
  gap_gradients[[i]] <- gradient
  gap_rows[[i]] <- tibble(vehicle_year = years[i], gap_percentage_points = 100 * gap,
    ci_low = 100 * (gap - critical * gap_se), ci_high = 100 * (gap + critical * gap_se))
}
rates <- bind_rows(rate_rows)
gaps <- bind_rows(gap_rows)
# The odds-scale interaction need not imply a widening absolute risk gap.
# Test the endpoint probability-gap change using their joint covariance.
change <- last(gaps$gap_percentage_points) - first(gaps$gap_percentage_points)
change_gradient <- gap_gradients[[length(years)]] - gap_gradients[[1]]
change_se <- 100 * sqrt(drop(t(change_gradient) %*% V %*% change_gradient))
gap_change <- tibble(from_year = first(years), to_year = last(years),
  change_percentage_points = change, ci_low = change - critical * change_se,
  ci_high = change + critical * change_se,
  p_value = 2 * pnorm(abs(change / change_se), lower.tail = FALSE))
write_csv(rates, "outputs/tables/07_year_interaction_standardised_rates.csv")
write_csv(gaps, "outputs/tables/07_year_interaction_probability_gaps.csv")
write_csv(gap_change, "outputs/tables/07_year_interaction_gap_change.csv")

colours <- c(Male = "#2a78d6", Female = "#eb6834")
rate_chart <- ggplot(rates, aes(vehicle_year, ksi_pct, colour = sex, fill = sex)) +
  geom_ribbon(aes(ymin = ci_low_pct, ymax = ci_high_pct), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.9) + geom_point(size = 2) +
  scale_colour_manual(values = colours) + scale_fill_manual(values = colours) +
  scale_x_continuous(breaks = years) +
  labs(title = "Adjusted KSI probability by sex and vehicle manufacture year",
       subtitle = paste("Same covariates for both sexes;", format(nrow(reference), big.mark = ","),
                        "reference occupants in 2020-2024 crashes"),
       x = "Vehicle manufacture year", y = "Adjusted KSI probability (%)", colour = NULL, fill = NULL,
       caption = "Shading: pointwise 95% crash-robust confidence intervals. Linear year interaction; associations, not design effects.") +
  theme_minimal(base_size = 11) + theme(legend.position = "top", panel.grid.minor = element_blank())
ggsave("outputs/figures/07_year_interaction_probabilities.png", rate_chart,
       width = 10, height = 5.5, dpi = 200, bg = "white")
or_chart <- ggplot(or_by_year, aes(vehicle_year, female_male_adjusted_or)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high), fill = "#2a78d6", alpha = 0.15) +
  geom_line(colour = "#2a78d6", linewidth = 0.9) + geom_point(colour = "#2a78d6", size = 2) +
  geom_hline(yintercept = 1, linetype = "dashed") + scale_x_continuous(breaks = years) +
  labs(title = "Adjusted female-to-male KSI odds ratio by vehicle year",
       subtitle = "Above 1 indicates higher female odds, conditional on the model controls",
       x = "Vehicle manufacture year", y = "Adjusted odds ratio",
       caption = "Shading: pointwise 95% crash-robust confidence intervals. Year is linear on the log-odds scale.") +
  theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank())
ggsave("outputs/figures/07_year_interaction_odds_ratios.png", or_chart,
       width = 8.5, height = 5, dpi = 200, bg = "white")

diagnostics <- tibble(occupants = nobs(fit), crashes = n_distinct(baseline$cohort_keys$accident_no),
  parameters = length(beta), converged = fit$converged, iterations = fit$iter,
  reference_occupants = nrow(reference), reference_crash_year_min = max(years),
  reference_crash_year_max = max(as.integer(as.character(reference$crash_year))))
write_csv(diagnostics, "outputs/tables/07_year_interaction_diagnostics.csv")
saveRDS(list(model = fit, cluster_robust_vcov = V, cohort_keys = baseline$cohort_keys,
  input_md5 = baseline$input_md5, baseline_md5 = unname(tools::md5sum(baseline_path)),
  reference_rule = "Same complete-case occupants in 2020-2024 crashes for all plotted years/sexes",
  plotted_years = years, session_info = sessionInfo()),
  "data/processed/vehicle_year_interaction_model.rds")
cat("\nInteraction test (change in female/male odds ratio per decade):\n")
print(interaction_test, width = Inf)
cat("\nFemale/male adjusted odds ratios by manufacture year:\n")
print(or_by_year)
cat("\nStandardised probability gaps, percentage points:\n")
print(gaps)
cat("\nEndpoint change in probability gap:\n")
print(gap_change)
cat("\nSaved interaction model, tables and two charts.\n")
