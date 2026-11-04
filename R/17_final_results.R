# One consistent final research table, plus matched curved-year sensitivity.
# Run from project root after R/16_impact_interaction.R.
for (pkg in c("dplyr", "readr", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
path <- "data/processed/final_association_models.rds"
saved <- readRDS(path)
stopifnot(identical(saved$input_md5,
  unname(tools::md5sum("data/processed/occupants_scenarios.rds"))))
cohort <- saved$models$Primary$model$model
critical <- qnorm(.975)
add_curves <- function(d) {
  s <- saved$spline; x <- d$vehicle_year_10
  raw <- splines::ns(x, knots = s$knots, Boundary.knots = s$boundaries)
  d[s$curve_names] <- as.data.frame((raw - cbind(1, x) %*% s$projection)[, s$columns])
  d
}
# Reference populations are fixed for the delta-method intervals. Covariance
# of paired male/female predictions is retained; rows are not independent tests.
standardise <- function(bundle, reference, sex_label, curved) {
  d <- reference; d$sex <- factor(sex_label, levels = levels(cohort$sex))
  if (curved) d <- add_curves(d)
  fit <- bundle$model; beta <- coef(fit); V <- bundle$cluster_robust_vcov
  X <- model.matrix(delete.response(terms(fit)), d,
    contrasts.arg = fit$contrasts, xlev = fit$xlevels)
  stopifnot(identical(colnames(X), names(beta)))
  p <- plogis(drop(X %*% beta)); mean_p <- mean(p)
  g <- colMeans(X * as.numeric(p * (1 - p)))
  se_logit <- sqrt(drop(t(g) %*% V %*% g)) / (mean_p * (1 - mean_p))
  list(p = mean_p, gradient = g,
    low = plogis(qlogis(mean_p) - critical * se_logit),
    high = plogis(qlogis(mean_p) + critical * se_logit))
}
compare_sexes <- function(bundle, reference, curved) {
  male <- standardise(bundle, reference, "Male", curved)
  female <- standardise(bundle, reference, "Female", curved)
  V <- bundle$cluster_robust_vcov
  gradient <- female$gradient - male$gradient
  gap <- female$p - male$p
  se <- sqrt(drop(t(gradient) %*% V %*% gradient))
  # Marginal OR from the standardised mean probabilities, not exp(sexFemale).
  log_or <- qlogis(female$p) - qlogis(male$p)
  or_gradient <- female$gradient / (female$p * (1 - female$p)) -
    male$gradient / (male$p * (1 - male$p))
  or_se <- sqrt(drop(t(or_gradient) %*% V %*% or_gradient))
  list(gradient = gradient, row = tibble(reference_occupants = nrow(reference),
    male_ksi_pct = 100 * male$p, male_ci_low = 100 * male$low, male_ci_high = 100 * male$high,
    female_ksi_pct = 100 * female$p, female_ci_low = 100 * female$low, female_ci_high = 100 * female$high,
    gap_percentage_points = 100 * gap, gap_ci_low = 100 * (gap - critical * se),
    gap_ci_high = 100 * (gap + critical * se), gap_p_value = 2 * pnorm(abs(gap / se), lower.tail = FALSE),
    marginal_sex_odds_ratio = exp(log_or), or_ci_low = exp(log_or - critical * or_se),
    or_ci_high = exp(log_or + critical * or_se)))
}
recent <- cohort[as.integer(as.character(cohort$crash_year)) >= 2020L, ]
specs <- list(list(question = "Q1 Overall", comparison = "All eligible complete cases",
  reference = "Full modelling cohort", data = cohort))
for (year in c(1995, 2000, 2010, 2020)) {
  d <- recent; d$vehicle_year_10 <- (year - 2010) / 10
  specs[[length(specs) + 1L]] <- list(question = "Q2 Vehicle year", comparison = as.character(year),
    reference = "Same occupants in 2020-2024 crashes; year set to comparison", data = d)
}
for (weight in c(1000, 1500, 2000)) {
  d <- cohort; d$tare_500kg <- (weight - 1500) / 500
  specs[[length(specs) + 1L]] <- list(question = "Q2 Vehicle weight", comparison = paste(weight, "kg"),
    reference = "Full modelling cohort; weight set to comparison", data = d)
}
for (seat_label in levels(cohort$seat)) {
  d <- cohort; d$seat <- factor(seat_label, levels = levels(cohort$seat))
  specs[[length(specs) + 1L]] <- list(question = "Q4 Seating", comparison = seat_label,
    reference = "Full modelling cohort; seat set to comparison", data = d)
}
# Keep each configuration/impact's observed combinations of other features,
# avoiding artificial assignments of crash scenarios onto incompatible rows.
for (variable in c("crash_configuration", "impact")) {
  for (level in levels(cohort[[variable]])) {
    specs[[length(specs) + 1L]] <- list(
      question = if (variable == "impact") "Q3 Impact" else "Q3 Configuration", comparison = level,
      reference = paste("Observed occupants within", variable, "group; same rows for both sexes"),
      data = cohort[cohort[[variable]] == level, ])
  }
}
results <- changes <- list()
for (model_label in names(saved$models)) {
  message("Standardising final results: ", model_label)
  bundle <- saved$models[[model_label]]; pairs <- list()
  for (i in seq_along(specs)) {
    spec <- specs[[i]]
    comparison <- compare_sexes(bundle, spec$data, model_label == "Curved")
    pairs[[paste(spec$question, spec$comparison, sep = "|")]] <- comparison
    results[[length(results) + 1L]] <- comparison$row %>%
      mutate(model = model_label, question = spec$question, comparison = spec$comparison,
        reference_population = spec$reference, .before = 1)
  }
  # Differences of gaps use the joint covariance, not overlap of separate CIs.
  contrast_specs <- list(
    c("Q2 Vehicle year", "1995", "2020"),
    c("Q2 Vehicle weight", "1000 kg", "2000 kg"),
    c("Q4 Seating", "Driver", "Front passenger"))
  for (s in contrast_specs) {
    first <- pairs[[paste(s[1], s[2], sep = "|")]]
    last <- pairs[[paste(s[1], s[3], sep = "|")]]
    gradient <- last$gradient - first$gradient
    estimate <- last$row$gap_percentage_points - first$row$gap_percentage_points
    se <- 100 * sqrt(drop(t(gradient) %*% bundle$cluster_robust_vcov %*% gradient))
    changes[[length(changes) + 1L]] <- tibble(model = model_label, question = s[1],
      from = s[2], to = s[3], gap_change_points = estimate,
      ci_low = estimate - critical * se, ci_high = estimate + critical * se,
      p_value = 2 * pnorm(abs(estimate / se), lower.tail = FALSE))
  }
}
all_results <- bind_rows(results) %>% group_by(model, question) %>%
  mutate(gap_p_holm_within_section = p.adjust(gap_p_value, "holm")) %>% ungroup() %>%
  arrange(match(model, c("Primary", "Curved")), match(question, c("Q1 Overall",
    "Q2 Vehicle year", "Q2 Vehicle weight", "Q3 Configuration", "Q3 Impact", "Q4 Seating")))
changes <- bind_rows(changes)
primary <- filter(all_results, model == "Primary")
sensitivity <- filter(all_results, model == "Curved")
write_csv(primary, "outputs/tables/07_final_research_results.csv")
write_csv(sensitivity, "outputs/tables/07_final_sensitivity_results.csv")
write_csv(changes, "outputs/tables/07_final_gap_changes.csv")
impact <- filter(primary, question == "Q3 Impact")
plot_data <- impact %>% mutate(comparison = factor(comparison, levels = rev(levels(cohort$impact))))
chart <- ggplot(plot_data, aes(gap_percentage_points, comparison)) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
  geom_errorbar(aes(xmin = gap_ci_low, xmax = gap_ci_high), orientation = "y", width = .15) +
  geom_point(size = 3, colour = "#2878B5") +
  labs(title = "Adjusted female-minus-male KSI gap by impact location",
    subtitle = "Final primary model: all five sex interactions retained",
    x = "Difference in KSI probability (percentage points)", y = "Initial impact location",
    caption = "Pointwise 95% crash-robust intervals. Each impact group supplies its own reference population.") +
  theme_minimal(base_size = 11)
ggsave("outputs/figures/07_final_impact_probability_gaps.png", chart,
  width = 10, height = 5.2, dpi = 180, bg = "white")

# Plain Markdown report: all main rows come from one model, with the matched
# curved-year results in a separate sensitivity section.
tests <- read_csv("outputs/tables/07_final_interaction_tests.csv", show_col_types = FALSE)
fmt_p <- function(p) ifelse(p < .001, "<0.001", sprintf("%.3f", p))
format_rows <- function(d) sprintf("| %s | %s | %.2f%% | %.2f%% | %.2f (%.2f to %.2f) | %.2f (%.2f to %.2f) |",
  d$question, d$comparison, d$male_ksi_pct, d$female_ksi_pct, d$gap_percentage_points,
  d$gap_ci_low, d$gap_ci_high, d$marginal_sex_odds_ratio, d$or_ci_low, d$or_ci_high)
primary_tests <- filter(tests, model == "Primary")
year_changes <- filter(changes, question == "Q2 Vehicle year")
report <- c("# Final research results", "",
  "Outcome: killed or seriously injured (KSI), not fatality alone. All main estimates below come from the same final primary model, including sex interactions with manufacturing year, weight, seat, crash configuration and impact location. Age band, speed band, vehicle-count group and crash year are also adjusted for. The same 175,453 occupants from 100,085 crashes are used for both fitted specifications; no new exclusions were introduced.", "",
  "## Consistent primary results table", "",
  "Values are model-standardised probabilities, not raw observed rates. Positive gaps and odds ratios above one indicate higher female estimates. Intervals are pointwise 95% intervals using crash-cluster-robust HC1 covariance and the delta method. The odds ratio is calculated from the two standardised mean probabilities (a marginal OR), not a single regression coefficient.", "",
  "| Research topic | Comparison | Male KSI | Female KSI | Female-minus-male gap, percentage points (95% CI) | Marginal female/male OR (95% CI) |",
  "|---|---|---:|---:|---:|---:|", format_rows(primary), "",
  "## Tests of differences in the sex association", "",
  "These joint tests concern conditional odds-ratio interactions. They are different from tests of the standardised probability gap. Raw p-values and Holm adjustments across the five primary interaction questions are shown; neither establishes causation.", "",
  "| Interaction | Degrees of freedom | p-value | Holm-adjusted p-value |",
  "|---|---:|---:|---:|",
  sprintf("| %s | %d | %s | %s |", primary_tests$test, primary_tests$df,
    fmt_p(primary_tests$p_value), fmt_p(primary_tests$p_holm_five_interactions)), "",
  "## Interpretation of the current results", "",
  "The overall standardised comparison supports higher female KSI odds/probability in this cohort, but the association is not uniform across circumstances. Front, side and rear impact groups have positive female-minus-male gaps; the Other impact interval includes zero. Run-off-road and loss-of-control configuration intervals also include zero, so an established reversal should not be claimed. A significant joint interaction does not establish a difference between every pair of categories.", "",
  "The seating comparison supports a larger female-minus-male gap among front passengers. Weight illustrates the importance of scale: the conditional sex-by-weight odds interaction has little evidence of variation, while the absolute probability gap falls with weight. These statements can both hold as baseline KSI probability changes. The absolute weight and seating gap-change intervals are supplied in `07_final_gap_changes.csv`.", "",
  "The primary model's relative sex odds vary with year, but the absolute 1995-to-2020 gap-change interval includes zero. The matched curved-year model also permits either narrowing or widening at those endpoints. A steady widening or closing of the gap with newer design is therefore not robustly established. Observed associations do not identify a causal vehicle-design effect.", "",
  "## Vehicle-year sensitivity, retaining sex x impact", "",
  "The sensitivity model permits a four-df natural spline for year with separate curves by sex and keeps all other controls/interactions. It is compared against the current primary model, not the earlier year-only interaction model.", "",
  "| Model | Change in female-minus-male gap, 2020 minus 1995 (percentage points, 95% CI) | p-value |",
  "|---|---:|---:|",
  sprintf("| %s | %.2f (%.2f to %.2f) | %s |", year_changes$model,
    year_changes$gap_change_points, year_changes$ci_low, year_changes$ci_high, fmt_p(year_changes$p_value)), "",
  "All curved-model comparisons are saved in `outputs/tables/07_final_sensitivity_results.csv`; year, weight and seating gap contrasts with joint uncertainty are in `07_final_gap_changes.csv`.", "",
  "## How to read the reference populations", "",
  "For every row, exactly the same reference occupants/covariates are used for male and female predictions. Overall estimates use the full cohort. Year rows use the same 62,244 occupants in 2020-2024 crashes with manufacture year set to the indicated value. Weight and seat rows use the full cohort with the named variable set to the indicated value. Configuration and impact rows use each group's observed covariate distribution, retaining plausible combinations with other crash characteristics. Therefore reference populations differ across configuration/impact rows: comparing their absolute gaps is not a causal effect of changing crash circumstances. The joint interaction tests assess heterogeneity after adjustment.", "",
  "## Scope and limitations", "",
  "These are adjusted associations among belted male/female drivers and left-front passengers aged 16+ with complete data in cars, station wagons and utes in recorded Victorian crashes. Manufacturing year is a proxy for design era and is not an identified design intervention. Broad age/speed categories and other unmeasured circumstances leave possible residual confounding. Other impact/configuration categories are heterogeneous, and some configuration-by-impact cells are sparse (see the support table). No three-way interactions are fitted.", "",
  "The reference-covariate distributions are treated as fixed in the delta-method intervals. Displayed intervals are pointwise; within-section Holm-adjusted gap p-values are provided in the CSVs. Exclusion/missing-data sensitivity is deferred at the user's request, not completed. The separate predictive evaluation/threshold scenarios remain based on their previously fitted models and were not rerun or relabelled as validation of this updated association model.", "",
  "Reproduce with `R/16_impact_interaction.R` followed by `R/17_final_results.R`. Detailed coefficients, all interaction tests, support counts and model diagnostics are under `outputs/tables/`. Model provenance and covariance matrices are in `data/processed/final_association_models.rds`.")
dir.create("report", recursive = TRUE, showWarnings = FALSE)
writeLines(report, "report/final_research_results.md")
saveRDS(list(primary = primary, sensitivity = sensitivity, gap_changes = changes,
  parent_md5 = unname(tools::md5sum(path)), input_md5 = saved$input_md5,
  session_info = sessionInfo()), "data/processed/final_research_results.rds")
print(impact, width = Inf)
print(changes, width = Inf)
message("Saved consistent primary table, matched sensitivity results and report/final_research_results.md")
