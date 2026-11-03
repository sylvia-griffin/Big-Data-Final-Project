# Step 7: sex x crash configuration, retaining year, weight and seat interactions.
# Run after R/09_seat_interaction.R from the project root.
# Joint crash-robust Wald test first; scenario-specific comparisons second.

for (pkg in c("dplyr", "readr", "ggplot2", "sandwich")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
parent_path <- "data/processed/seat_interaction_model.rds"
previous <- readRDS(parent_path)
stopifnot(identical(previous$input_md5,
  unname(tools::md5sum("data/processed/occupants_scenarios.rds"))))
cohort <- previous$model$model
stopifnot(nrow(cohort) == nrow(previous$cohort_keys))
fit <- glm(update(formula(previous$model), . ~ . + sex:crash_configuration),
  data = cohort, family = binomial(), na.action = na.fail, control = glm.control(maxit = 50))
stopifnot(fit$converged, all(is.finite(coef(fit))),
          nobs(fit) == nobs(previous$model),
          identical(rownames(fit$model), rownames(cohort)))
V <- sandwich::vcovCL(fit, cluster = previous$cohort_keys$accident_no,
                      type = "HC1", cadjust = TRUE)
stopifnot(all(is.finite(V)), all(diag(V) > 0))
beta <- coef(fit); se <- sqrt(diag(V)); critical <- qnorm(0.975)
scenarios <- levels(cohort$crash_configuration)
interaction_terms <- grep("^sexFemale:crash_configuration", names(beta), value = TRUE)
stopifnot(length(interaction_terms) == length(scenarios) - 1L)
b <- beta[interaction_terms]; covariance <- V[interaction_terms, interaction_terms]
wald <- drop(t(b) %*% solve(covariance, b))
joint_test <- tibble(test = "Equal female/male odds ratios across crash configurations",
  wald_chisq = wald, df = length(b), p_value = pchisq(wald, length(b), lower.tail = FALSE))
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
write_csv(joint_test, "outputs/tables/07_configuration_interaction_joint_test.csv")
write_csv(tibble(term = names(beta), log_odds = unname(beta), robust_se = unname(se),
  odds_ratio = exp(beta), ci_low = exp(beta - critical * se), ci_high = exp(beta + critical * se),
  p_value = 2 * pnorm(abs(beta / se), lower.tail = FALSE)),
  "outputs/tables/07_configuration_interaction_coefficients.csv")
support <- cohort %>% group_by(crash_configuration, sex) %>%
  summarise(occupants = n(), ksi_cases = sum(ksi), observed_ksi_pct = 100 * mean(ksi), .groups = "drop")
write_csv(support, "outputs/tables/07_configuration_interaction_support.csv")

# Sex ORs depend on year, weight and seat because their interactions remain.
# Fix these at 2010, 1500 kg and Driver. No three-way interactions are fitted.
or_rows <- bind_rows(lapply(scenarios, function(scenario) {
  L <- setNames(rep(0, length(beta)), names(beta)); L["sexFemale"] <- 1
  term <- paste0("sexFemale:crash_configuration", scenario)
  if (scenario != scenarios[1]) {
    stopifnot(term %in% names(beta)); L[term] <- 1
  }
  estimate <- sum(L * beta); error <- sqrt(drop(t(L) %*% V %*% L))
  tibble(crash_configuration = scenario, seat = "Driver", manufacture_year = 2010L,
    tare_kg = 1500L, female_male_adjusted_or = exp(estimate),
    ci_low = exp(estimate - critical * error), ci_high = exp(estimate + critical * error),
    p_value = 2 * pnorm(abs(estimate / error), lower.tail = FALSE))
})) %>% mutate(p_holm = p.adjust(p_value, method = "holm"))
# Holm adjustment applies to the seven sex-OR-versus-one tests, not to the
# global interaction test. Displayed 95% intervals are pointwise.
write_csv(or_rows, "outputs/tables/07_configuration_interaction_sex_or.csv")

# Within each configuration, use its own observed covariate distribution
# for BOTH sexes. This avoids constructing implausible combinations such
# as forcing multi-vehicle configurations onto single-vehicle crashes.
# Reference populations differ across configurations; absolute probabilities
# across rows are not causal scenario comparisons. Unknowns were excluded
# at baseline; no additional exclusions are introduced here.
standardise <- function(reference, label) {
  d <- reference; d$sex <- factor(label, levels = levels(cohort$sex))
  X <- model.matrix(delete.response(terms(fit)), d,
                    contrasts.arg = fit$contrasts, xlev = fit$xlevels)
  stopifnot(identical(colnames(X), names(beta)))
  probabilities <- plogis(drop(X %*% beta)); p <- mean(probabilities)
  gradient <- colMeans(X * as.numeric(probabilities * (1 - probabilities)))
  variance <- drop(t(gradient) %*% V %*% gradient)
  stopifnot(is.finite(variance), variance >= 0)
  error <- sqrt(variance) / (p * (1 - p))
  list(p = p, gradient = gradient, row = tibble(sex = label,
    reference_occupants = nrow(reference), ksi_pct = 100 * p,
    ci_low_pct = 100 * plogis(qlogis(p) - critical * error),
    ci_high_pct = 100 * plogis(qlogis(p) + critical * error)))
}
rate_rows <- gap_rows <- vector("list", length(scenarios))
for (i in seq_along(scenarios)) {
  reference <- cohort[cohort$crash_configuration == scenarios[i], ]
  male <- standardise(reference, "Male"); female <- standardise(reference, "Female")
  rate_rows[[i]] <- bind_rows(male$row, female$row) %>%
    mutate(crash_configuration = scenarios[i], .before = 1)
  gradient <- female$gradient - male$gradient
  error <- sqrt(drop(t(gradient) %*% V %*% gradient)); gap <- female$p - male$p
  gap_rows[[i]] <- tibble(crash_configuration = scenarios[i], reference_occupants = nrow(reference),
    gap_percentage_points = 100 * gap,
    ci_low = 100 * (gap - critical * error), ci_high = 100 * (gap + critical * error))
}
rates <- bind_rows(rate_rows); gaps <- bind_rows(gap_rows)
write_csv(rates, "outputs/tables/07_configuration_interaction_standardised_rates.csv")
write_csv(gaps, "outputs/tables/07_configuration_interaction_probability_gaps.csv")

plot_data <- or_rows %>% mutate(crash_configuration = factor(crash_configuration, levels = rev(scenarios)))
chart <- ggplot(plot_data, aes(female_male_adjusted_or, crash_configuration)) +
  geom_vline(xintercept = 1, linetype = "dashed") +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.15, orientation = "y", colour = "#2a78d6") +
  geom_point(size = 2.5, colour = "#2a78d6") +
  scale_x_log10() +
  scale_y_discrete(labels = function(z) vapply(z, function(s) paste(strwrap(s, 28), collapse = "\n"), character(1))) +
  labs(title = "Adjusted female-to-male KSI odds ratios by crash configuration",
    subtitle = "Reference: drivers, manufacture year 2010, tare weight 1,500 kg",
    x = "Adjusted odds ratio (log scale; above 1 = higher female odds)", y = NULL,
    caption = "Pointwise 95% crash-robust intervals; not simultaneous. Other known configurations is a mixed group.") +
  theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank())
ggsave("outputs/figures/07_configuration_interaction_odds_ratios.png", chart,
       width = 10, height = 6.5, dpi = 200, bg = "white")
write_csv(tibble(occupants = nobs(fit), crashes = n_distinct(previous$cohort_keys$accident_no),
  parameters = length(beta), converged = fit$converged, iterations = fit$iter),
  "outputs/tables/07_configuration_interaction_diagnostics.csv")
saveRDS(list(model = fit, cluster_robust_vcov = V, cohort_keys = previous$cohort_keys,
  input_md5 = previous$input_md5, parent_md5 = unname(tools::md5sum(parent_path)),
  reference_rule = "Within each configuration, same observed covariates for both sexes",
  session_info = sessionInfo()), "data/processed/configuration_interaction_model.rds")
cat("\nJoint interaction test:\n"); print(joint_test)
cat("\nSex ORs at Driver, 2010, 1500 kg:\n"); print(or_rows, width = Inf)
cat("\nWithin-configuration standardised probability gaps:\n"); print(gaps, width = Inf)
