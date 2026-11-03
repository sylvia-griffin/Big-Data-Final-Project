# Step 7: retrospective internal predictive validation, grouped by crash ID.
# Run from the project root after R/10_crash_configuration_interaction.R.
# Earlier full-cohort analyses informed the candidate specifications; this is
# not an untouched external validation. All models below are fitted afresh.
for (pkg in c("dplyr", "readr", "ggplot2", "ranger")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
seed <- 20261103L
parent_path <- "data/processed/configuration_interaction_model.rds"
previous <- readRDS(parent_path)
input_md5 <- unname(tools::md5sum("data/processed/occupants_scenarios.rds"))
stopifnot(identical(previous$input_md5, input_md5))
cohort <- previous$model$model
keys <- previous$cohort_keys
stopifnot(nrow(cohort) == nrow(keys), !anyNA(cohort), !anyNA(keys$accident_no),
          all(cohort$ksi %in% 0:1), !anyDuplicated(keys))
linear_formula <- formula(previous$model)
curved_formula <- update(linear_formula, . ~ . - vehicle_year_10 -
  sex:vehicle_year_10 + splines::ns(vehicle_year_10, df = 4) +
  sex:splines::ns(vehicle_year_10, df = 4))
# ns() learns knots and boundaries inside each training fit; predict.glm()
# reuses those training values. No full-cohort spline basis is reused.
predictors <- setdiff(names(cohort), "ksi")
factor_names <- predictors[vapply(cohort[predictors], is.factor, logical(1))]
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
write_table <- function(x, name) write_csv(x, paste0("outputs/tables/07_predictive_", name, ".csv"))

# Stratify crashes by whether any eligible cohort member has KSI. Grouping
# preserves dependence among occupants; metrics remain occupant-weighted.
crashes <- tibble(accident_no = keys$accident_no, ksi = cohort$ksi) %>%
  group_by(accident_no) %>% summarise(any_ksi = max(ksi), .groups = "drop") %>%
  arrange(accident_no)
split_path <- "data/processed/predictive_split.rds"
if (file.exists(split_path)) {
  saved_split <- readRDS(split_path)
  stopifnot(identical(saved_split$input_md5, input_md5),
            identical(saved_split$cohort_keys, keys), identical(saved_split$seed, seed))
  assignments <- saved_split$crashes
} else {
  set.seed(seed)
  assignments <- crashes %>% mutate(partition = "train", fold = NA_integer_)
  for (stratum in 0:1) {
    eligible <- which(assignments$any_ksi == stratum)
    test_rows <- sample(eligible, size = round(0.2 * length(eligible)))
    assignments$partition[test_rows] <- "test"
    train_rows <- setdiff(eligible, test_rows)
    assignments$fold[train_rows] <- sample(rep(1:5, length.out = length(train_rows)))
  }
  saveRDS(list(seed = seed, input_md5 = input_md5, cohort_keys = keys,
               crashes = assignments), split_path)
}
stopifnot(identical(assignments$accident_no, crashes$accident_no),
          identical(assignments$any_ksi, crashes$any_ksi),
          !anyDuplicated(assignments$accident_no))
membership <- assignments[match(keys$accident_no, assignments$accident_no), ]
train_rows <- which(membership$partition == "train")
test_rows <- which(membership$partition == "test")
stopifnot(length(intersect(keys$accident_no[train_rows], keys$accident_no[test_rows])) == 0,
          all(is.na(membership$fold[test_rows])), all(membership$fold[train_rows] %in% 1:5))
split_summary <- bind_cols(membership, tibble(ksi = cohort$ksi)) %>%
  group_by(partition, fold) %>% summarise(crashes = n_distinct(accident_no),
    occupants = n(), ksi_cases = sum(ksi), ksi_rate = mean(ksi), .groups = "drop")
write_table(split_summary, "split_summary")

# AUC and average precision treat tied scores together. Probabilities are
# clipped only for log loss and calibration logits, never for ranking/Brier.
roc_points <- function(y, p) {
  z <- tibble(score = p, positive = y, negative = 1 - y) %>%
    group_by(score) %>% summarise(tp = sum(positive), fp = sum(negative), .groups = "drop") %>%
    arrange(desc(score)) %>% mutate(tp = cumsum(tp), fp = cumsum(fp),
      sensitivity = tp / sum(y), fpr = fp / sum(1 - y))
  bind_rows(tibble(score = Inf, tp = 0, fp = 0, sensitivity = 0, fpr = 0), z)
}
metrics <- function(y, p) {
  stopifnot(length(y) == length(p), all(is.finite(p)), all(p >= 0 & p <= 1),
            length(unique(y)) == 2L)
  n1 <- sum(y); n0 <- sum(1 - y); clipped <- pmin(pmax(p, 1e-15), 1 - 1e-15)
  roc <- roc_points(y, p)
  average_precision <- sum(diff(roc$sensitivity) * (roc$tp[-1] / (roc$tp[-1] + roc$fp[-1])))
  tibble(occupants = length(y), ksi_cases = n1,
    roc_auc = (sum(rank(p)[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0),
    average_precision = average_precision, brier = mean((y - p)^2),
    log_loss = -mean(y * log(clipped) + (1 - y) * log1p(-clipped)))
}
classification <- function(y, p, threshold) {
  predicted <- p >= threshold
  tp <- sum(predicted & y == 1); fp <- sum(predicted & y == 0)
  tn <- sum(!predicted & y == 0); fn <- sum(!predicted & y == 1)
  tibble(threshold = threshold, tp = tp, fp = fp, tn = tn, fn = fn,
    sensitivity = tp / (tp + fn), specificity = tn / (tn + fp),
    precision = if (tp + fp > 0) tp / (tp + fp) else NA_real_,
    f1 = 2 * tp / (2 * tp + fp + fn), accuracy = (tp + tn) / length(y))
}
fit_logistic <- function(form, rows) {
  fit <- glm(form, data = cohort[rows, ], family = binomial(), na.action = na.fail,
             control = glm.control(maxit = 50))
  stopifnot(fit$converged, all(is.finite(coef(fit))), fit$rank == length(coef(fit)))
  fit
}
# Small prespecified tuning grid to keep runtime modest. No oversampling or
# class weights: target the observed KSI probabilities in this cohort.
rf_grid <- tibble(candidate = c("RF_mtry3", "RF_mtry6"), mtry = c(3L, 6L),
                  min_node_size = 50L, min_bucket = 10L, trees = 300L)
write_table(rf_grid, "rf_grid")
fit_forest <- function(rows, settings, fit_seed, importance = "none") {
  ranger::ranger(x = cohort[rows, predictors],
    y = factor(cohort$ksi[rows], levels = 0:1, labels = c("NoKSI", "KSI")),
    probability = TRUE, num.trees = settings$trees, mtry = settings$mtry,
    min.node.size = settings$min_node_size, min.bucket = settings$min_bucket,
    respect.unordered.factors = "order", importance = importance,
    oob.error = importance != "none", num.threads = 2L, seed = fit_seed,
    na.action = "na.fail", verbose = FALSE)
}
candidate_names <- c("Logistic_linear", "Logistic_curved", rf_grid$candidate)
oof <- matrix(NA_real_, nrow = length(train_rows), ncol = length(candidate_names),
              dimnames = list(NULL, candidate_names))
fold_metrics <- list()
for (fold in 1:5) {
  assessment <- train_rows[membership$fold[train_rows] == fold]
  analysis <- train_rows[membership$fold[train_rows] != fold]
  stopifnot(length(intersect(keys$accident_no[analysis], keys$accident_no[assessment])) == 0)
  for (variable in factor_names) {
    stopifnot(all(unique(cohort[[variable]][assessment]) %in% unique(cohort[[variable]][analysis])))
  }
  message("Cross-validation fold ", fold, "/5: logistic models")
  predictions <- list()
  for (candidate in candidate_names[1:2]) {
    fit <- fit_logistic(if (candidate == "Logistic_linear") linear_formula else curved_formula, analysis)
    predictions[[candidate]] <- predict(fit, newdata = cohort[assessment, ], type = "response")
  }
  for (j in seq_len(nrow(rf_grid))) {
    message("Cross-validation fold ", fold, "/5: ", rf_grid$candidate[j])
    forest <- fit_forest(analysis, rf_grid[j, ], seed + 100L * fold + j)
    predictions[[rf_grid$candidate[j]]] <- predict(forest,
      data = cohort[assessment, predictors], num.threads = 2L)$predictions[, "KSI"]
    rm(forest)
  }
  for (candidate in candidate_names) {
    oof[match(assessment, train_rows), candidate] <- predictions[[candidate]]
    fold_metrics[[length(fold_metrics) + 1L]] <- metrics(cohort$ksi[assessment], predictions[[candidate]]) %>%
      mutate(candidate = candidate, fold = fold, .before = 1)
  }
  gc(verbose = FALSE)
}
stopifnot(!anyNA(oof))
cv_folds <- bind_rows(fold_metrics)
cv_summary <- bind_rows(lapply(candidate_names, function(candidate) {
  metrics(cohort$ksi[train_rows], oof[, candidate]) %>% mutate(candidate = candidate, .before = 1)
}))
# Select within each model family by pooled OOF log loss (lower is better).
# CV scores used to select settings are not an unbiased evaluation of selection.
selected_logistic <- cv_summary %>% filter(grepl("^Logistic", candidate)) %>%
  arrange(log_loss, candidate) %>% slice(1) %>% pull(candidate)
selected_rf <- cv_summary %>% filter(grepl("^RF", candidate)) %>%
  arrange(log_loss, candidate) %>% slice(1) %>% pull(candidate)
selected <- c("Logistic regression" = selected_logistic, "Random forest" = selected_rf)
thresholds <- vapply(selected, function(candidate) {
  curve <- roc_points(cohort$ksi[train_rows], oof[, candidate])
  curve$score[which.max(curve$sensitivity - curve$fpr)]
}, numeric(1))
# Youden's J gives equal weight to sensitivity and specificity. It is an
# illustrative operating point, not a cost-optimised clinical/policy rule.
write_table(cv_folds, "cv_folds")
write_table(cv_summary %>% mutate(selected = candidate %in% selected), "cv_summary")
write_table(tibble(model = names(selected), candidate = unname(selected),
  training_oof_youden_threshold = unname(thresholds)), "selection")
saveRDS(list(oof = oof, train_rows = train_rows, cohort_keys = keys[train_rows, ],
  selected = selected, thresholds = thresholds, cv_summary = cv_summary,
  cv_folds = cv_folds, rf_grid = rf_grid, input_md5 = input_md5),
  "data/processed/predictive_cv.rds")

# Choices are now frozen. Fit on all training crashes and evaluate the test
# set once. Original full-cohort inference models remain separate artifacts.
message("Selected ", selected_logistic, " and ", selected_rf, "; fitting training-set models")
logistic <- fit_logistic(if (selected_logistic == "Logistic_linear") linear_formula else curved_formula, train_rows)
forest <- fit_forest(train_rows, rf_grid[rf_grid$candidate == selected_rf, ], seed + 1000L,
                     importance = "permutation")
test_probabilities <- list(
  "Logistic regression" = as.numeric(predict(logistic, newdata = cohort[test_rows, ], type = "response")),
  "Random forest" = predict(forest, data = cohort[test_rows, predictors], num.threads = 2L)$predictions[, "KSI"],
  "Training prevalence" = rep(mean(cohort$ksi[train_rows]), length(test_rows)))
y_test <- cohort$ksi[test_rows]
test_metrics <- bind_rows(lapply(names(test_probabilities), function(model) {
  metrics(y_test, test_probabilities[[model]]) %>% mutate(model = model, .before = 1)
}))
threshold_metrics <- bind_rows(lapply(names(selected), function(model) {
  bind_rows(classification(y_test, test_probabilities[[model]], 0.5) %>% mutate(rule = "Fixed 0.5"),
    classification(y_test, test_probabilities[[model]], thresholds[[model]]) %>%
      mutate(rule = "Training OOF Youden")) %>% mutate(model = model, .before = 1)
}))
by_sex <- bind_rows(lapply(names(selected), function(model) {
  bind_rows(lapply(levels(cohort$sex), function(sex_label) {
    rows <- cohort$sex[test_rows] == sex_label
    metrics(y_test[rows], test_probabilities[[model]][rows]) %>%
      mutate(model = model, sex = sex_label, observed_rate = mean(y_test[rows]),
             mean_prediction = mean(test_probabilities[[model]][rows]), .before = 1)
  }))
}))
calibration <- bind_rows(lapply(names(selected), function(model) {
  p <- test_probabilities[[model]]; lp <- qlogis(pmin(pmax(p, 1e-15), 1 - 1e-15))
  intercept_fit <- glm(y_test ~ 1 + offset(lp), family = binomial())
  slope_fit <- glm(y_test ~ lp, family = binomial())
  stopifnot(intercept_fit$converged, slope_fit$converged)
  tibble(model = model, calibration_in_the_large = unname(coef(intercept_fit)[1]),
    joint_calibration_intercept = unname(coef(slope_fit)[1]),
    calibration_slope = unname(coef(slope_fit)[2]))
}))
# Calibration diagnostics are descriptive test-set measurements; they are
# not used to recalibrate or change either model after viewing the test set.
write_table(test_metrics, "test_metrics")
write_table(threshold_metrics, "confusion_metrics")
write_table(by_sex, "test_metrics_by_sex")
write_table(calibration, "calibration")
write_table(tibble(variable = names(forest$variable.importance),
  oob_permutation_importance = unname(forest$variable.importance)) %>%
    arrange(desc(oob_permutation_importance)), "rf_importance")
# Ranger's OOB resampling is by occupant, not crash: importance is exploratory,
# not our validation estimate, and does not identify causal effects.
roc_data <- bind_rows(lapply(names(selected), function(model) {
  roc_points(y_test, test_probabilities[[model]]) %>% mutate(model = model)
}))
calibration_bins <- bind_rows(lapply(names(selected), function(model) {
  tibble(observed = y_test, predicted = test_probabilities[[model]]) %>%
    mutate(bin = ntile(predicted, 10)) %>% group_by(bin) %>%
    summarise(occupants = n(), predicted = mean(predicted), observed = mean(observed), .groups = "drop") %>%
    mutate(model = model, .before = 1)
}))
write_table(calibration_bins, "calibration_bins")
colors <- c("Logistic regression" = "#2878B5", "Random forest" = "#D45A31")
roc_plot <- ggplot(roc_data, aes(fpr, sensitivity, colour = model)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey65") +
  geom_line(linewidth = 0.8) + coord_equal() + scale_colour_manual(values = colors) +
  labs(title = "KSI prediction on held-out crashes", subtitle = "80/20 crash-grouped split; settings selected by five-fold grouped CV",
       x = "False positive rate", y = "Sensitivity", colour = NULL) +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
calibration_plot <- ggplot(calibration_bins, aes(predicted, observed, colour = model)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey65") +
  geom_line() + geom_point(size = 2) + coord_equal() + scale_colour_manual(values = colors) +
  labs(title = "How predicted KSI risk compares with observed KSI",
       subtitle = "Held-out crashes; ten equal-count bins per model",
       x = "Mean predicted probability", y = "Observed KSI proportion", colour = NULL,
       caption = "Dashed line: perfect calibration. Descriptive bins; no test-set recalibration.") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave("outputs/figures/07_predictive_roc.png", roc_plot, width = 8, height = 6, dpi = 180, bg = "white")
ggsave("outputs/figures/07_predictive_calibration.png", calibration_plot, width = 8, height = 6, dpi = 180, bg = "white")
saveRDS(list(logistic = logistic, random_forest = forest, selected = selected,
  thresholds = thresholds, predictors = predictors, input_md5 = input_md5,
  parent_md5 = unname(tools::md5sum(parent_path)),
  script_md5 = unname(tools::md5sum("R/12_predictive_evaluation.R")),
  seed = seed, train_keys = keys[train_rows, ], test_keys = keys[test_rows, ],
  test_predictions = bind_cols(keys[test_rows, ], tibble(ksi = y_test), as_tibble(test_probabilities)),
  purpose = "Retrospective internal prediction validation; complete cases; occupant-weighted metrics",
  session_info = sessionInfo()), "data/processed/predictive_models.rds")
capture.output(sessionInfo(), file = "outputs/tables/07_predictive_session_info.txt")
message("Predictive evaluation complete. Test-set metrics:")
print(test_metrics, width = Inf)
print(threshold_metrics, width = Inf)
