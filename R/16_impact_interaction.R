# Final association model: add sex x impact to all existing interactions.
# Run from the project root after R/10_crash_configuration_interaction.R.
# Primary specification retains linear year; matched spline is sensitivity.
# This extends full-cohort inference, not the separate prediction models.
for (pkg in c("dplyr", "readr", "sandwich")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr)})
parent_path <- "data/processed/configuration_interaction_model.rds"
previous <- readRDS(parent_path)
stopifnot(identical(previous$input_md5,
  unname(tools::md5sum("data/processed/occupants_scenarios.rds"))))
cohort <- previous$model$model
keys <- previous$cohort_keys
stopifnot(nrow(cohort) == nrow(keys), !anyNA(cohort), !anyDuplicated(keys))
fit_model <- function(form, data) {
  fit <- glm(form, data = data, family = binomial(), na.action = na.fail,
             control = glm.control(maxit = 50))
  stopifnot(fit$converged, all(is.finite(coef(fit))), fit$rank == length(coef(fit)),
            nobs(fit) == nrow(cohort), identical(rownames(fit$model), rownames(cohort)))
  V <- sandwich::vcovCL(fit, cluster = keys$accident_no, type = "HC1", cadjust = TRUE)
  stopifnot(all(is.finite(V)), all(diag(V) > 0))
  list(model = fit, cluster_robust_vcov = V)
}
primary_formula <- update(formula(previous$model), . ~ . + sex:impact)
message("Fitting final linear-year association model with sex x impact")
primary <- fit_model(primary_formula, cohort)

# Same four-df natural spline construction as R/11, now retaining sex x impact.
x <- cohort$vehicle_year_10
knots <- unname(quantile(x, c(.25, .5, .75))); boundaries <- range(x)
basis <- splines::ns(x, knots = knots, Boundary.knots = boundaries)
design <- cbind(1, x)
projection <- qr.coef(qr(design), basis)
residual <- basis - design %*% projection
decomposition <- qr(residual, tol = 1e-8)
stopifnot(decomposition$rank == 3L)
columns <- decomposition$pivot[1:3]; curve_names <- paste0("year_curve", 1:3)
curved_data <- cohort
curved_data[curve_names] <- as.data.frame(residual[, columns])
message("Fitting matched curved-year sensitivity model")
curved <- fit_model(update(primary_formula, . ~ . + year_curve1 + year_curve2 +
  year_curve3 + sex:year_curve1 + sex:year_curve2 + sex:year_curve3), curved_data)
models <- list(Primary = primary, Curved = curved)
wald <- function(bundle, terms, label) {
  b <- coef(bundle$model)[terms]
  V <- bundle$cluster_robust_vcov[terms, terms, drop = FALSE]
  statistic <- drop(t(b) %*% solve(V, b))
  tibble(test = label, df = length(b), wald_chisq = statistic,
         p_value = pchisq(statistic, length(b), lower.tail = FALSE))
}
tests <- bind_rows(lapply(names(models), function(label) {
  bundle <- models[[label]]; terms <- names(coef(bundle$model))
  groups <- list(
    "Sex x manufacture year" = c("sexFemale:vehicle_year_10",
      if (label == "Curved") paste0("sexFemale:", curve_names)),
    "Sex x weight" = "sexFemale:tare_500kg",
    "Sex x seat" = "sexFemale:seatFront passenger",
    "Sex x configuration" = grep("^sexFemale:crash_configuration", terms, value = TRUE),
    "Sex x impact" = grep("^sexFemale:impact", terms, value = TRUE))
  stopifnot(length(groups[["Sex x impact"]]) == 3L,
            length(groups[["Sex x configuration"]]) == 6L)
  bind_rows(lapply(names(groups), function(test) wald(bundle, groups[[test]], test))) %>%
    mutate(model = label, p_holm_five_interactions = p.adjust(p_value, "holm"), .before = 1)
}))
curvature_tests <- bind_rows(
  wald(curved, c(curve_names, paste0("sexFemale:", curve_names)), "Any year curvature"),
  wald(curved, paste0("sexFemale:", curve_names), "Curvature of the sex odds gap"))
coefficients <- bind_rows(lapply(names(models), function(label) {
  beta <- coef(models[[label]]$model); se <- sqrt(diag(models[[label]]$cluster_robust_vcov))
  tibble(model = label, term = names(beta), log_odds = unname(beta), robust_se = unname(se),
    odds_ratio = exp(beta), ci_low = exp(beta - qnorm(.975) * se),
    ci_high = exp(beta + qnorm(.975) * se), p_value = 2 * pnorm(abs(beta / se), lower.tail = FALSE))
}))
diagnostics <- bind_rows(lapply(names(models), function(label) {
  fit <- models[[label]]$model
  tibble(model = label, occupants = nobs(fit), crashes = n_distinct(keys$accident_no),
    ksi_cases = sum(cohort$ksi), parameters = length(coef(fit)), converged = fit$converged)
}))
support <- cohort %>% group_by(impact, sex) %>% summarise(occupants = n(),
  ksi_cases = sum(ksi), observed_ksi_pct = 100 * mean(ksi), .groups = "drop")
joint_support <- cohort %>% group_by(crash_configuration, impact, sex) %>%
  summarise(occupants = n(), ksi_cases = sum(ksi), .groups = "drop")
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
write_csv(tests, "outputs/tables/07_final_interaction_tests.csv")
write_csv(curvature_tests, "outputs/tables/07_final_curvature_tests.csv")
write_csv(coefficients, "outputs/tables/07_final_coefficients.csv")
write_csv(diagnostics, "outputs/tables/07_final_model_diagnostics.csv")
write_csv(support, "outputs/tables/07_impact_interaction_support.csv")
write_csv(joint_support, "outputs/tables/07_impact_configuration_support.csv")
saveRDS(list(models = models, cohort_keys = keys, input_md5 = previous$input_md5,
  parent_md5 = unname(tools::md5sum(parent_path)),
  spline = list(knots = knots, boundaries = boundaries, projection = projection,
                columns = columns, curve_names = curve_names),
  purpose = "Final full-cohort associations; primary linear year, matched curved sensitivity",
  session_info = sessionInfo()), "data/processed/final_association_models.rds")
print(tests, width = Inf)
print(curvature_tests, width = Inf)
