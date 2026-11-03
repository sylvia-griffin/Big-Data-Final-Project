# Step 7: sex x vehicle weight, retaining sex x manufacture year.
# Run from the project root after R/07_vehicle_year_interaction.R.
# Same cohort and controls; crash-cluster-robust HC1 confidence intervals.
# https://sandwich.r-forge.r-project.org/reference/vcovCL.html

for (pkg in c("dplyr", "readr", "ggplot2", "sandwich")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
parent_path <- "data/processed/vehicle_year_interaction_model.rds"
previous <- readRDS(parent_path)
stopifnot(identical(previous$input_md5,
  unname(tools::md5sum("data/processed/occupants_scenarios.rds"))))
cohort <- previous$model$model
stopifnot(nrow(cohort) == nrow(previous$cohort_keys))
model_formula <- update(formula(previous$model), . ~ . + sex:tare_500kg)
fit <- glm(model_formula, data = cohort, family = binomial(),
           na.action = na.fail, control = glm.control(maxit = 50))
stopifnot(fit$converged, !anyNA(coef(fit)), all(is.finite(coef(fit))),
          nobs(fit) == nobs(previous$model),
          identical(rownames(fit$model), rownames(cohort)))
V <- sandwich::vcovCL(fit, cluster = previous$cohort_keys$accident_no,
                      type = "HC1", cadjust = TRUE)
stopifnot(all(is.finite(V)), all(diag(V) > 0))
beta <- coef(fit); se <- sqrt(diag(V)); critical <- qnorm(0.975)
weight_term <- "sexFemale:tare_500kg"
year_term <- "sexFemale:vehicle_year_10"
stopifnot(all(c(weight_term, year_term) %in% names(beta)))
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

coefficients <- tibble(term = names(beta), log_odds = unname(beta), robust_se = unname(se),
  odds_ratio = exp(beta), ci_low = exp(beta - critical * se),
  ci_high = exp(beta + critical * se), p_value = 2 * pnorm(abs(beta / se), lower.tail = FALSE))
write_csv(coefficients, "outputs/tables/07_weight_interaction_coefficients.csv")
# Both interaction estimates are exported because adding weight can change
# the earlier year estimate. These are ratios of sex odds ratios, not risks.
tests <- coefficients %>% filter(term %in% c(weight_term, year_term)) %>%
  mutate(unit = ifelse(term == weight_term, "Per 500 kg heavier", "Per 10 newer manufacture years"),
         wald_chisq = (log_odds / robust_se)^2, df = 1L) %>%
  rename(ratio_of_odds_ratios = odds_ratio)
write_csv(tests, "outputs/tables/07_weight_interaction_tests.csv")

# 1000-2000 kg covers a substantial observed range for both sexes.
# The fit uses all eligible weights; bins provide support counts, not inputs.
weights <- seq(1000, 2000, by = 250)
support <- cohort %>% mutate(tare_kg = tare_500kg * 500 + 1500,
  weight_band = cut(tare_kg, breaks = c(-Inf, 1000, 1250, 1500, 1750, 2000, Inf),
                    right = FALSE)) %>% count(weight_band, sex, name = "occupants")
write_csv(support, "outputs/tables/07_weight_interaction_support.csv")

# Conditional sex ORs must specify manufacture year when its interaction
# remains in the model. Use 2010 (the centred reference), explicitly labelled.
or_rows <- bind_rows(lapply(weights, function(weight) {
  L <- setNames(rep(0, length(beta)), names(beta))
  L["sexFemale"] <- 1; L[weight_term] <- (weight - 1500) / 500
  estimate <- sum(L * beta); error <- sqrt(drop(t(L) %*% V %*% L))
  tibble(tare_kg = weight, manufacture_year = 2010L,
         female_male_adjusted_or = exp(estimate),
         ci_low = exp(estimate - critical * error), ci_high = exp(estimate + critical * error))
}))
write_csv(or_rows, "outputs/tables/07_weight_interaction_sex_or.csv")

# Standardise over ALL baseline occupants: keep their actual manufacturing
# years and other controls, assigning the same weight/sex to everyone in
# turn. This preserves valid vehicle/crash-year pairs. The two sexes use
# identical covariate distributions; these are associations, not causal effects.
standardise <- function(weight, label) {
  d <- cohort
  d$sex <- factor(label, levels = levels(cohort$sex))
  d$tare_500kg <- (weight - 1500) / 500
  X <- model.matrix(delete.response(terms(fit)), d,
                    contrasts.arg = fit$contrasts, xlev = fit$xlevels)
  stopifnot(identical(colnames(X), names(beta)))
  probabilities <- plogis(drop(X %*% beta)); p <- mean(probabilities)
  gradient <- colMeans(X * as.numeric(probabilities * (1 - probabilities)))
  variance <- drop(t(gradient) %*% V %*% gradient)
  stopifnot(is.finite(variance), variance >= 0)
  error <- sqrt(variance) / (p * (1 - p))
  list(p = p, gradient = gradient,
    row = tibble(tare_kg = weight, sex = label, reference_occupants = nrow(cohort),
      ksi_pct = 100 * p, ci_low_pct = 100 * plogis(qlogis(p) - critical * error),
      ci_high_pct = 100 * plogis(qlogis(p) + critical * error)))
}
rate_rows <- gap_rows <- gradients <- vector("list", length(weights))
for (i in seq_along(weights)) {
  male <- standardise(weights[i], "Male"); female <- standardise(weights[i], "Female")
  rate_rows[[i]] <- bind_rows(male$row, female$row)
  gradient <- female$gradient - male$gradient
  error <- sqrt(drop(t(gradient) %*% V %*% gradient))
  gap <- female$p - male$p
  gradients[[i]] <- gradient
  gap_rows[[i]] <- tibble(tare_kg = weights[i], gap_percentage_points = 100 * gap,
    ci_low = 100 * (gap - critical * error), ci_high = 100 * (gap + critical * error))
}
rates <- bind_rows(rate_rows); gaps <- bind_rows(gap_rows)
change <- last(gaps$gap_percentage_points) - first(gaps$gap_percentage_points)
gradient <- gradients[[length(weights)]] - gradients[[1]]
error <- 100 * sqrt(drop(t(gradient) %*% V %*% gradient))
gap_change <- tibble(from_kg = first(weights), to_kg = last(weights),
  change_percentage_points = change, ci_low = change - critical * error,
  ci_high = change + critical * error, p_value = 2 * pnorm(abs(change / error), lower.tail = FALSE))
write_csv(rates, "outputs/tables/07_weight_interaction_standardised_rates.csv")
write_csv(gaps, "outputs/tables/07_weight_interaction_probability_gaps.csv")
write_csv(gap_change, "outputs/tables/07_weight_interaction_gap_change.csv")

chart <- ggplot(gaps, aes(tare_kg, gap_percentage_points)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high), fill = "#2a78d6", alpha = 0.15) +
  geom_line(colour = "#2a78d6", linewidth = 0.9) + geom_point(colour = "#2a78d6", size = 2) +
  geom_hline(yintercept = 0, linetype = "dashed") + scale_x_continuous(breaks = weights) +
  labs(title = "Adjusted female-minus-male KSI probability gap by vehicle weight",
       subtitle = paste("Same", format(nrow(cohort), big.mark = ","),
                        "reference occupants; sex by vehicle-year interaction retained"),
       x = "Vehicle tare weight (kg)", y = "Female minus male KSI probability (percentage points)",
       caption = paste0(
         "Shading: pointwise 95% crash-robust confidence intervals. Linear weight effects; adjusted associations.\n",
         "Odds-scale sex x weight interaction p = ",
         format.pval(tests$p_value[tests$term == weight_term], digits = 3),
         ". Probability gaps can change even with a constant odds ratio.")) +
  theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank())
ggsave("outputs/figures/07_weight_interaction_probability_gap.png", chart,
       width = 10, height = 5.5, dpi = 200, bg = "white")
write_csv(tibble(occupants = nobs(fit), crashes = n_distinct(previous$cohort_keys$accident_no),
  parameters = length(beta), converged = fit$converged, iterations = fit$iter),
  "outputs/tables/07_weight_interaction_diagnostics.csv")
saveRDS(list(model = fit, cluster_robust_vcov = V, cohort_keys = previous$cohort_keys,
  input_md5 = previous$input_md5, parent_md5 = unname(tools::md5sum(parent_path)),
  reference_rule = "Full baseline cohort; observed years and controls retained for all weights/sexes",
  plotted_weights = weights, session_info = sessionInfo()),
  "data/processed/weight_interaction_model.rds")
cat("\nWeight and retained year interaction tests:\n"); print(tests, width = Inf)
cat("\nSex odds ratios at manufacture year 2010:\n"); print(or_rows)
cat("\nStandardised KSI probability gaps:\n"); print(gaps)
cat("\nEndpoint gap change:\n"); print(gap_change)
cat("\nSaved weight interaction model, tables and chart.\n")
