# Step 7: sex x seating position, retaining year and weight interactions.
# Run from the project root after R/08_weight_interaction.R.
# Descriptive association model; crash-cluster-robust HC1 inference.

for (pkg in c("dplyr", "readr", "ggplot2", "sandwich")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
parent_path <- "data/processed/weight_interaction_model.rds"
previous <- readRDS(parent_path)
stopifnot(identical(previous$input_md5,
  unname(tools::md5sum("data/processed/occupants_scenarios.rds"))))
cohort <- previous$model$model
stopifnot(nrow(cohort) == nrow(previous$cohort_keys))
fit <- glm(update(formula(previous$model), . ~ . + sex:seat), data = cohort,
           family = binomial(), na.action = na.fail, control = glm.control(maxit = 50))
stopifnot(fit$converged, !anyNA(coef(fit)), all(is.finite(coef(fit))),
          nobs(fit) == nobs(previous$model),
          identical(rownames(fit$model), rownames(cohort)))
V <- sandwich::vcovCL(fit, cluster = previous$cohort_keys$accident_no,
                      type = "HC1", cadjust = TRUE)
stopifnot(all(is.finite(V)), all(diag(V) > 0))
beta <- coef(fit); se <- sqrt(diag(V)); critical <- qnorm(0.975)
interaction_term <- "sexFemale:seatFront passenger"
stopifnot(interaction_term %in% names(beta))
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

coefficients <- tibble(term = names(beta), log_odds = unname(beta), robust_se = unname(se),
  odds_ratio = exp(beta), ci_low = exp(beta - critical * se), ci_high = exp(beta + critical * se),
  p_value = 2 * pnorm(abs(beta / se), lower.tail = FALSE))
test <- coefficients %>% filter(term == interaction_term) %>%
  rename(passenger_driver_ratio_of_sex_odds_ratios = odds_ratio) %>%
  mutate(wald_chisq = (log_odds / robust_se)^2, df = 1L)
write_csv(coefficients, "outputs/tables/07_seat_interaction_coefficients.csv")
write_csv(test, "outputs/tables/07_seat_interaction_test.csv")
write_csv(cohort %>% group_by(seat, sex) %>%
  summarise(occupants = n(), ksi_cases = sum(ksi), observed_ksi_pct = 100 * mean(ksi), .groups = "drop"),
  "outputs/tables/07_seat_interaction_support.csv")

seats <- c("Driver", "Front passenger")
# Conditional sex odds ratios use manufacture year 2010 and tare 1500 kg
# because sex interactions with both variables remain in the model.
or_rows <- bind_rows(lapply(seats, function(seat_label) {
  L <- setNames(rep(0, length(beta)), names(beta)); L["sexFemale"] <- 1
  L[interaction_term] <- as.integer(seat_label == "Front passenger")
  estimate <- sum(L * beta); error <- sqrt(drop(t(L) %*% V %*% L))
  tibble(seat = seat_label, manufacture_year = 2010L, tare_kg = 1500L,
         female_male_adjusted_or = exp(estimate),
         ci_low = exp(estimate - critical * error), ci_high = exp(estimate + critical * error))
}))
write_csv(or_rows, "outputs/tables/07_seat_interaction_sex_or.csv")

# Use the SAME full-cohort covariate distribution for all four sex/seat
# combinations. This avoids comparing groups with different ages/vehicles.
# These are model-standardised associations, not effects of changing seats.
# Delta-method intervals treat the empirical covariate distribution as fixed.
standardise <- function(seat_label, sex_label) {
  d <- cohort
  d$sex <- factor(sex_label, levels = levels(cohort$sex))
  d$seat <- factor(seat_label, levels = levels(cohort$seat))
  X <- model.matrix(delete.response(terms(fit)), d,
                     contrasts.arg = fit$contrasts, xlev = fit$xlevels)
  stopifnot(identical(colnames(X), names(beta)))
  probabilities <- plogis(drop(X %*% beta)); p <- mean(probabilities)
  gradient <- colMeans(X * as.numeric(probabilities * (1 - probabilities)))
  variance <- drop(t(gradient) %*% V %*% gradient)
  stopifnot(is.finite(variance), variance >= 0)
  error <- sqrt(variance) / (p * (1 - p))
  list(p = p, gradient = gradient, row = tibble(seat = seat_label, sex = sex_label,
    reference_occupants = nrow(cohort), ksi_pct = 100 * p,
    ci_low_pct = 100 * plogis(qlogis(p) - critical * error),
    ci_high_pct = 100 * plogis(qlogis(p) + critical * error)))
}
rate_rows <- gap_rows <- gradients <- vector("list", length(seats))
for (i in seq_along(seats)) {
  male <- standardise(seats[i], "Male"); female <- standardise(seats[i], "Female")
  rate_rows[[i]] <- bind_rows(male$row, female$row)
  gradient <- female$gradient - male$gradient
  error <- sqrt(drop(t(gradient) %*% V %*% gradient)); gap <- female$p - male$p
  gradients[[i]] <- gradient
  gap_rows[[i]] <- tibble(seat = seats[i], gap_percentage_points = 100 * gap,
    ci_low = 100 * (gap - critical * error), ci_high = 100 * (gap + critical * error))
}
rates <- bind_rows(rate_rows); gaps <- bind_rows(gap_rows)
change <- gaps$gap_percentage_points[2] - gaps$gap_percentage_points[1]
gradient <- gradients[[2]] - gradients[[1]]
error <- 100 * sqrt(drop(t(gradient) %*% V %*% gradient))
gap_difference <- tibble(contrast = "Front passenger minus Driver: female-male probability gap",
  difference_percentage_points = change, ci_low = change - critical * error,
  ci_high = change + critical * error, p_value = 2 * pnorm(abs(change / error), lower.tail = FALSE))
write_csv(rates, "outputs/tables/07_seat_interaction_standardised_rates.csv")
write_csv(gaps, "outputs/tables/07_seat_interaction_probability_gaps.csv")
write_csv(gap_difference, "outputs/tables/07_seat_interaction_gap_difference.csv")

plot_data <- rates %>% mutate(seat = factor(seat, levels = seats),
                              sex = factor(sex, levels = c("Male", "Female")))
chart <- ggplot(plot_data, aes(seat, ksi_pct, colour = sex)) +
  geom_pointrange(aes(ymin = ci_low_pct, ymax = ci_high_pct),
                  position = position_dodge(width = 0.35), linewidth = 0.7) +
  scale_colour_manual(values = c(Male = "#2a78d6", Female = "#eb6834")) +
  labs(title = "Adjusted KSI probability by sex and seating position",
       subtitle = paste("Same", format(nrow(cohort), big.mark = ","),
                        "reference occupants; year and weight interactions retained"),
       x = NULL, y = "Adjusted KSI probability (%)", colour = NULL,
       caption = "Intervals: pointwise 95% crash-robust confidence intervals. Standardised associations, not causal seat effects.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", panel.grid.minor = element_blank())
ggsave("outputs/figures/07_seat_interaction_probabilities.png", chart,
       width = 10, height = 5.5, dpi = 200, bg = "white")
write_csv(tibble(occupants = nobs(fit), crashes = n_distinct(previous$cohort_keys$accident_no),
  parameters = length(beta), converged = fit$converged, iterations = fit$iter),
  "outputs/tables/07_seat_interaction_diagnostics.csv")
saveRDS(list(model = fit, cluster_robust_vcov = V, cohort_keys = previous$cohort_keys,
  input_md5 = previous$input_md5, parent_md5 = unname(tools::md5sum(parent_path)),
  reference_rule = "Same full baseline cohort for all four sex/seat combinations",
  session_info = sessionInfo()), "data/processed/seat_interaction_model.rds")
cat("\nSeat interaction test:\n"); print(test, width = Inf)
cat("\nConditional female/male odds ratios (2010, 1500 kg):\n"); print(or_rows)
cat("\nStandardised probabilities:\n"); print(rates)
cat("\nFemale-male probability gaps:\n"); print(gaps)
cat("\nDifference between gaps:\n"); print(gap_difference, width = Inf)
