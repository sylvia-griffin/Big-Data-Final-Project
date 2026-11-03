# Screening scenario: target at least 80% recall in training OOF predictions.
# Run after R/12_predictive_evaluation.R; no model refitting is needed.
# The target is a project assumption, not a Victorian policy requirement.
# Test results were previously inspected: this is a retrospective follow-up,
# not a new independent validation. Never adjust cutoffs using test outcomes.
for (pkg in c("dplyr", "readr", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
target_recall <- 0.80
cv_path <- "data/processed/predictive_cv.rds"
model_path <- "data/processed/predictive_models.rds"
cv <- readRDS(cv_path)
saved <- readRDS(model_path)
parent <- readRDS("data/processed/configuration_interaction_model.rds")
stopifnot(identical(cv$input_md5, saved$input_md5),
  identical(cv$input_md5, parent$input_md5),
  identical(cv$input_md5, unname(tools::md5sum("data/processed/occupants_scenarios.rds"))),
  identical(cv$selected, saved$selected),
  identical(cv$cohort_keys, parent$cohort_keys[cv$train_rows, ]),
  identical(cv$cohort_keys, saved$train_keys))
y_train <- parent$model$model$ksi[cv$train_rows]
stopifnot(!anyNA(y_train), all(y_train %in% 0:1), sum(y_train) > 0)
score <- function(y, p, cutoff) {
  stopifnot(length(y) == length(p), all(is.finite(p)), all(p >= 0 & p <= 1))
  predicted <- p >= cutoff
  tp <- sum(predicted & y == 1); fp <- sum(predicted & y == 0)
  tn <- sum(!predicted & y == 0); fn <- sum(!predicted & y == 1)
  tibble(threshold = cutoff, occupants = length(y), tp = tp, fp = fp, tn = tn, fn = fn,
    recall = tp / (tp + fn), missed_ksi_rate = fn / (tp + fn),
    specificity = tn / (tn + fp), precision = tp / (tp + fp),
    f1 = 2 * tp / (2 * tp + fp + fn), accuracy = (tp + tn) / length(y),
    flagged = tp + fp, flagged_fraction = (tp + fp) / length(y))
}
# The kth highest positive-case probability is the highest cutoff attaining
# the target. Scores tied at the cutoff are all classified positive. Among
# cutoffs meeting the target, this minimises false-positive counts (ties possible).
# Use full precision for classification; round only for display.
thresholds <- vapply(cv$selected, function(candidate) {
  p <- cv$oof[, candidate]
  cutoff <- sort(p[y_train == 1], decreasing = TRUE)[ceiling(target_recall * sum(y_train))]
  stopifnot(score(y_train, p, cutoff)$recall >= target_recall)
  higher <- p[p > cutoff]
  if (length(higher)) stopifnot(score(y_train, p, min(higher))$recall < target_recall)
  cutoff
}, numeric(1))
training_metrics <- bind_rows(lapply(names(thresholds), function(model_name) {
  score(y_train, cv$oof[, cv$selected[[model_name]]], thresholds[[model_name]]) %>%
    mutate(model = model_name, target_recall = target_recall, .before = 1)
}))
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
write_csv(training_metrics, "outputs/tables/07_recall_target_training.csv")

# Only now apply frozen cutoffs to the saved test predictions. Reaching 80%
# in training does not guarantee 80% in test or in a future population.
test <- saved$test_predictions
stopifnot(identical(test[, names(saved$test_keys)], saved$test_keys),
  length(intersect(cv$cohort_keys$accident_no, test$accident_no)) == 0L)
comparison <- bind_rows(lapply(names(thresholds), function(model_name) {
  p <- test[[model_name]]
  bind_rows(score(test$ksi, p, saved$thresholds[[model_name]]) %>%
      mutate(rule = "Original training Youden"),
    score(test$ksi, p, thresholds[[model_name]]) %>%
      mutate(rule = "80% training recall target")) %>% mutate(model = model_name, .before = 1)
}))
write_csv(comparison, "outputs/tables/07_recall_target_test_comparison.csv")
matrices <- bind_rows(lapply(names(thresholds), function(model_name) {
  counts <- table(actual = factor(test$ksi, levels = 0:1, labels = c("Non-KSI", "KSI")),
    predicted = factor(as.integer(test[[model_name]] >= thresholds[[model_name]]),
      levels = 0:1, labels = c("Non-KSI", "KSI")))
  as_tibble(as.data.frame(counts, responseName = "occupants")) %>%
    group_by(actual) %>% mutate(actual_class_pct = 100 * occupants / sum(occupants)) %>%
    ungroup() %>% mutate(model = model_name, threshold = thresholds[[model_name]],
      outcome = case_when(actual == "KSI" & predicted == "KSI" ~ "True positive",
        actual == "KSI" ~ "False negative", predicted == "KSI" ~ "False positive",
        TRUE ~ "True negative"), .before = 1)
}))
write_csv(matrices, "outputs/tables/07_recall_target_confusion_matrices.csv")
# Audit sex-specific detection without choosing sex-specific thresholds.
lookup <- bind_cols(parent$cohort_keys, tibble(sex = parent$model$model$sex))
test_sex <- test %>% left_join(lookup, by = names(parent$cohort_keys))
stopifnot(nrow(test_sex) == nrow(test), !anyNA(test_sex$sex))
by_sex <- bind_rows(lapply(names(thresholds), function(model_name) {
  bind_rows(lapply(levels(test_sex$sex), function(sex_label) {
    keep <- test_sex$sex == sex_label
    score(test$ksi[keep], test[[model_name]][keep], thresholds[[model_name]]) %>%
      mutate(model = model_name, sex = sex_label, .before = 1)
  }))
}))
write_csv(by_sex, "outputs/tables/07_recall_target_test_by_sex.csv")
plot_data <- matrices %>% mutate(actual = factor(actual, levels = c("KSI", "Non-KSI")),
  panel = sprintf("%s\nThreshold = %.4f", model, threshold),
  label = sprintf("%s\n%s\n%.1f%% of actual class", outcome,
    format(occupants, big.mark = ",", trim = TRUE), actual_class_pct))
chart <- ggplot(plot_data, aes(predicted, actual, fill = actual_class_pct)) +
  geom_tile(colour = "white", linewidth = 1.5) +
  geom_text(aes(label = label), size = 3.8, lineheight = 1.2) +
  facet_wrap(~panel, nrow = 1) + coord_equal() +
  scale_fill_gradient(low = "#F0F5FA", high = "#77B5D9", limits = c(0, 100), guide = "none") +
  labs(title = "KSI screening: thresholds targeting 80% training recall",
    subtitle = "Applied unchanged to the existing test set; no test-set threshold tuning",
    x = "Predicted outcome", y = "Actual outcome",
    caption = paste0("KSI = killed or seriously injured. Percentages are within each actual class.\n",
      "Illustrative project target, not an authority-endorsed rule. Retrospective evaluation of 35,305 test occupants.")) +
  theme_minimal(base_size = 12) + theme(panel.grid = element_blank(),
    strip.text = element_text(face = "bold"), plot.caption = element_text(hjust = 0))
ggsave("outputs/figures/07_recall_target_confusion.png", chart,
  width = 11, height = 6, dpi = 180, bg = "white")
saveRDS(list(target_recall = target_recall, thresholds = thresholds,
  classification_rule = "Predict KSI when probability >= the full-precision model-specific threshold",
  selection_rule = "Highest threshold with pooled training OOF recall >= target; ties included",
  selected_models = cv$selected, training_metrics = training_metrics,
  test_comparison = comparison, test_by_sex = by_sex,
  cv_md5 = unname(tools::md5sum(cv_path)), model_md5 = unname(tools::md5sum(model_path)),
  input_md5 = cv$input_md5, session_info = sessionInfo()),
  "data/processed/predictive_screening_thresholds.rds")
print(training_metrics, width = Inf)
print(comparison, width = Inf)
message("Saved 80%-recall screening thresholds and updated matrices; original evaluation is preserved.")
