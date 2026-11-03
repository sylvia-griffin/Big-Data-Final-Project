# Step 7 robustness: relax linear manufacture-year effects for both sexes.
# Run after R/10_crash_configuration_interaction.R from the project root.
# Same cohort, controls and weight/seat/configuration interactions.
# Natural cubic spline documentation:
# https://stat.ethz.ch/R-manual/R-devel/library/splines/help/ns.html

for (pkg in c("dplyr", "readr", "ggplot2", "sandwich")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
parent_path <- "data/processed/configuration_interaction_model.rds"
previous <- readRDS(parent_path)
stopifnot(identical(previous$input_md5,
  unname(tools::md5sum("data/processed/occupants_scenarios.rds"))))
cohort <- previous$model$model
stopifnot(nrow(cohort) == nrow(previous$cohort_keys))

# Four-df natural spline: three outcome-independent interior knots at the
# 25th/50th/75th percentiles, boundaries at observed extremes.
# Reparameterise into the existing linear term plus three curvature terms.
# Residualising the ns basis against intercept/year and retaining its three
# independent columns preserves exactly the same spline space. This makes
# the linear model nested and the curvature hypotheses explicit.
x <- cohort$vehicle_year_10
knots <- unname(quantile(x, c(.25, .5, .75)))
boundaries <- range(x)
basis <- splines::ns(x, knots = knots, Boundary.knots = boundaries)
linear_design <- cbind(intercept = 1, year = x)
projection <- qr.coef(qr(linear_design), basis)
residual_basis <- basis - linear_design %*% projection
decomposition <- qr(residual_basis, tol = 1e-8)
stopifnot(decomposition$rank == 3L)
columns <- decomposition$pivot[seq_len(decomposition$rank)]
curve_names <- paste0("year_curve", 1:3)
curve_basis <- function(year_10) {
  raw <- splines::ns(year_10, knots = knots, Boundary.knots = boundaries)
  result <- (raw - cbind(1, year_10) %*% projection)[, columns, drop = FALSE]
  colnames(result) <- curve_names
  result
}
cohort[curve_names] <- as.data.frame(curve_basis(x))
fit <- glm(update(formula(previous$model), . ~ . + year_curve1 + year_curve2 + year_curve3 +
                    sex:year_curve1 + sex:year_curve2 + sex:year_curve3),
  data = cohort, family = binomial(), na.action = na.fail, control = glm.control(maxit = 50))
stopifnot(fit$converged, all(is.finite(coef(fit))),
          nobs(fit) == nobs(previous$model),
          identical(rownames(fit$model), rownames(previous$model$model)))
V <- sandwich::vcovCL(fit, cluster = previous$cohort_keys$accident_no,
                      type = "HC1", cadjust = TRUE)
stopifnot(all(is.finite(V)), all(diag(V) > 0))
critical <- qnorm(.975)
wald_test <- function(label, terms) {
  b <- coef(fit)[terms]; covariance <- V[terms, terms, drop = FALSE]
  statistic <- drop(t(b) %*% solve(covariance, b))
  tibble(test = label, wald_chisq = statistic, df = length(terms),
         p_value = pchisq(statistic, length(terms), lower.tail = FALSE))
}
sex_curve <- paste0("sexFemale:", curve_names)
tests <- bind_rows(
  wald_test("Any year curvature (both sexes)", c(curve_names, sex_curve)),
  wald_test("Curvature in the female/male log-odds gap", sex_curve),
  wald_test("Any sex by vehicle-year interaction", c("sexFemale:vehicle_year_10", sex_curve))
)
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
write_csv(tests, "outputs/tables/07_year_robustness_tests.csv")
write_csv(tibble(type = c("Lower boundary", "25% knot", "50% knot", "75% knot", "Upper boundary"),
  manufacture_year = c(boundaries[1], knots, boundaries[2]) * 10 + 2010),
  "outputs/tables/07_year_robustness_knots.csv")

# Identical recent-crash reference population for both models and sexes,
# avoiding manufacture dates after crash dates. Compare the CURRENT fully
# adjusted linear model, not the earlier model with fewer sex interactions.
years <- 1995:2020
reference <- cohort[as.integer(as.character(cohort$crash_year)) >= max(years), ]
stopifnot(nrow(reference) > 0)
models <- list(Linear = previous$model, Curved = fit)
covariances <- list(Linear = previous$cluster_robust_vcov, Curved = V)
new_year <- function(data, year, label) {
  data$sex <- factor(label, levels = levels(cohort$sex))
  data$vehicle_year_10 <- rep((year - 2010) / 10, nrow(data))
  data[curve_names] <- as.data.frame(curve_basis(data$vehicle_year_10))
  data
}
standardise <- function(model, covariance, year, label) {
  d <- new_year(reference, year, label)
  X <- model.matrix(delete.response(terms(model)), d,
                    contrasts.arg = model$contrasts, xlev = model$xlevels)
  stopifnot(identical(colnames(X), names(coef(model))))
  probabilities <- plogis(drop(X %*% coef(model))); p <- mean(probabilities)
  gradient <- colMeans(X * as.numeric(probabilities * (1 - probabilities)))
  variance <- drop(t(gradient) %*% covariance %*% gradient)
  stopifnot(is.finite(variance), variance >= 0)
  error <- sqrt(variance) / (p * (1 - p))
  list(p = p, gradient = gradient, row = tibble(vehicle_year = year, sex = label,
    reference_occupants = nrow(reference), ksi_pct = 100 * p,
    ci_low_pct = 100 * plogis(qlogis(p) - critical * error),
    ci_high_pct = 100 * plogis(qlogis(p) + critical * error)))
}
all_rates <- all_gaps <- endpoints <- list()
for (label in names(models)) {
  model <- models[[label]]; covariance <- covariances[[label]]
  rates <- gaps <- gradients <- vector("list", length(years))
  for (i in seq_along(years)) {
    male <- standardise(model, covariance, years[i], "Male")
    female <- standardise(model, covariance, years[i], "Female")
    rates[[i]] <- bind_rows(male$row, female$row)
    gradient <- female$gradient - male$gradient
    error <- sqrt(drop(t(gradient) %*% covariance %*% gradient))
    gap <- female$p - male$p; gradients[[i]] <- gradient
    gaps[[i]] <- tibble(vehicle_year = years[i], gap_percentage_points = 100 * gap,
      ci_low = 100 * (gap - critical * error), ci_high = 100 * (gap + critical * error))
  }
  rate_table <- bind_rows(rates); gap_table <- bind_rows(gaps)
  all_rates[[label]] <- mutate(rate_table, model = label, .before = 1)
  all_gaps[[label]] <- mutate(gap_table, model = label, .before = 1)
  change <- last(gap_table$gap_percentage_points) - first(gap_table$gap_percentage_points)
  gradient <- gradients[[length(years)]] - gradients[[1]]
  error <- 100 * sqrt(drop(t(gradient) %*% covariance %*% gradient))
  # Change in sex log-OR across the endpoints: other sex interactions cancel.
  contrasts <- lapply(c(first(years), last(years)), function(year) {
    d <- bind_rows(new_year(reference[1, ], year, "Male"),
                   new_year(reference[1, ], year, "Female"))
    X <- model.matrix(delete.response(terms(model)), d,
                      contrasts.arg = model$contrasts, xlev = model$xlevels)
    X[2, ] - X[1, ]
  })
  L <- contrasts[[2]] - contrasts[[1]]
  log_change <- sum(L * coef(model)); log_se <- sqrt(drop(t(L) %*% covariance %*% L))
  endpoints[[label]] <- tibble(model = label, from_year = first(years), to_year = last(years),
    gap_change_points = change, gap_change_ci_low = change - critical * error,
    gap_change_ci_high = change + critical * error,
    gap_change_p = 2 * pnorm(abs(change / error), lower.tail = FALSE),
    ratio_of_sex_odds_ratios = exp(log_change),
    ratio_ci_low = exp(log_change - critical * log_se), ratio_ci_high = exp(log_change + critical * log_se),
    ratio_p = 2 * pnorm(abs(log_change / log_se), lower.tail = FALSE))
}
rates <- bind_rows(all_rates); gaps <- bind_rows(all_gaps); endpoint_tests <- bind_rows(endpoints)
write_csv(rates, "outputs/tables/07_year_robustness_standardised_rates.csv")
write_csv(gaps, "outputs/tables/07_year_robustness_probability_gaps.csv")
write_csv(endpoint_tests, "outputs/tables/07_year_robustness_endpoint_changes.csv")
chart <- ggplot(gaps, aes(vehicle_year, gap_percentage_points, colour = model, fill = model)) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high), alpha = .13, colour = NA) +
  geom_line(linewidth = 1) + geom_hline(yintercept = 0, linetype = "dashed") +
  scale_colour_manual(values = c(Linear = "#2a78d6", Curved = "#eb6834")) +
  scale_fill_manual(values = c(Linear = "#2a78d6", Curved = "#eb6834")) +
  scale_x_continuous(breaks = seq(1995, 2020, 5)) +
  labs(title = "Does the vehicle-year gap persist with a curved relationship?",
    subtitle = "Same cohort and controls; probabilities standardised to 62,244 occupants in 2020-2024 crashes",
    x = "Vehicle manufacture year", y = "Female minus male KSI probability (percentage points)",
    colour = NULL, fill = NULL,
    caption = "Shading: pointwise 95% crash-robust intervals. Curved = natural cubic spline; adjusted associations.") +
  theme_minimal(base_size = 11) + theme(legend.position = "top", panel.grid.minor = element_blank())
ggsave("outputs/figures/07_year_robustness_probability_gap.png", chart,
       width = 10, height = 5.5, dpi = 200, bg = "white")
write_csv(bind_rows(lapply(names(models), function(label) tibble(model = label,
  occupants = nobs(models[[label]]), parameters = length(coef(models[[label]])),
  converged = models[[label]]$converged, iterations = models[[label]]$iter))),
  "outputs/tables/07_year_robustness_diagnostics.csv")
saveRDS(list(model = fit, cluster_robust_vcov = V, cohort_keys = previous$cohort_keys,
  input_md5 = previous$input_md5, parent_md5 = unname(tools::md5sum(parent_path)),
  spline = list(knots = knots, boundaries = boundaries, projection = projection,
                columns = columns, curve_names = curve_names),
  reference_rule = "Same complete-case occupants in 2020-2024 crashes for all plotted years/sexes",
  session_info = sessionInfo()), "data/processed/year_robustness_model.rds")
cat("\nCrash-robust curvature tests:\n"); print(tests, width = Inf)
cat("\nEndpoint changes, 1995 to 2020:\n"); print(endpoint_tests, width = Inf)
cat("\nSelected probability gaps:\n"); print(filter(gaps, vehicle_year %in% c(1995, 2000, 2010, 2020)), width = Inf)
