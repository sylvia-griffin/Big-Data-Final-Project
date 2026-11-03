# Balanced precision/recall scenario: maximise training OOF F1.
# Run after R/14_recall_threshold.R; no model refitting is needed.
# F1 is the harmonic mean of precision and recall, not balanced accuracy.
# It does not require equal precision/recall or imply an optimal policy cost.
# Test results were previously inspected: this is a retrospective follow-up,
# not a new independent validation. Never adjust cutoffs using test outcomes.
for (pkg in c("dplyr", "readr", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
cv_path <- "data/processed/predictive_cv.rds"
model_path <- "data/processed/predictive_models.rds"
cv <- readRDS(cv_path)
saved <- readRDS(model_path)
recall_path <- "data/processed/predictive_screening_thresholds.rds"
recall_policy <- readRDS(recall_path)
stopifnot(identical(recall_policy$cv_md5, unname(tools::md5sum(cv_path))),
  identical(recall_policy$model_md5, unname(tools::md5sum(model_path))))
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
# Evaluate all distinct training OOF scores, keeping tied predictions together.
# Maximise F1; exact ties favour higher recall, then the higher threshold.
# No test predictions/outcomes are used in this choice.
thresholds <- vapply(cv$selected, function(candidate) {
  p <- cv$oof[, candidate]
  stopifnot(length(p) == length(y_train), all(is.finite(p)), all(p >= 0 & p <= 1))
  curve <- tibble(threshold = p, positive = y_train) %>%
    group_by(threshold) %>% summarise(positives = sum(positive), total = n(), .groups = "drop") %>%
    arrange(desc(threshold)) %>% mutate(tp = cumsum(positives), flagged = cumsum(total),
      fp = flagged - tp, fn = sum(y_train) - tp,
      f1 = 2 * tp / (2 * tp + fp + fn), recall = tp / sum(y_train)) %>%
    arrange(desc(f1), desc(recall), desc(threshold))
  cutoff <- curve$threshold[1]
  stopifnot(abs(score(y_train, p, cutoff)$f1 - curve$f1[1]) < 1e-12)
  cutoff
}, numeric(1))
training_metrics <- bind_rows(lapply(names(thresholds), function(model_name) {
  score(y_train, cv$oof[, cv$selected[[model_name]]], thresholds[[model_name]]) %>%
    mutate(model = model_name, objective = "Maximum training OOF F1", .before = 1)
}))
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
write_csv(training_metrics, "outputs/tables/07_balanced_f1_training.csv")

# Only now apply frozen cutoffs to the saved test predictions. The optimum
# on training OOF predictions need not be optimal in test or a new population.
test <- saved$test_predictions
stopifnot(identical(test[, names(saved$test_keys)], saved$test_keys),
  length(intersect(cv$cohort_keys$accident_no, test$accident_no)) == 0L)
comparison <- bind_rows(lapply(names(thresholds), function(model_name) {
  p <- test[[model_name]]
  bind_rows(score(test$ksi, p, saved$thresholds[[model_name]]) %>%
      mutate(rule = "Original training Youden"),
    score(test$ksi, p, recall_policy$thresholds[[model_name]]) %>%
      mutate(rule = "80% training recall target"),
    score(test$ksi, p, thresholds[[model_name]]) %>%
      mutate(rule = "Maximum training OOF F1")) %>% mutate(model = model_name, .before = 1)
}))
write_csv(comparison, "outputs/tables/07_balanced_f1_test_comparison.csv")
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
write_csv(matrices, "outputs/tables/07_balanced_f1_confusion_matrices.csv")
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
write_csv(by_sex, "outputs/tables/07_balanced_f1_test_by_sex.csv")
plot_data <- matrices %>% mutate(actual = factor(actual, levels = c("KSI", "Non-KSI")),
  panel = sprintf("%s\nThreshold = %.4f", model, threshold),
  label = sprintf("%s\n%s\n%.1f%% of actual class", outcome,
    format(occupants, big.mark = ",", trim = TRUE), actual_class_pct))
chart <- ggplot(plot_data, aes(predicted, actual, fill = actual_class_pct)) +
  geom_tile(colour = "white", linewidth = 1.5) +
  geom_text(aes(label = label), size = 3.8, lineheight = 1.2) +
  facet_wrap(~panel, nrow = 1) + coord_equal() +
  scale_fill_gradient(low = "#F0F5FA", high = "#77B5D9", limits = c(0, 100), guide = "none") +
  labs(title = "KSI classification: balance precision and recall using F1",
    subtitle = "Applied unchanged to the existing test set; no test-set threshold tuning",
    x = "Predicted outcome", y = "Actual outcome",
    caption = paste0("KSI = killed or seriously injured. Percentages are within each actual class.\n",
      "Cutoffs maximise training OOF F1. Retrospective evaluation of 35,305 test occupants.")) +
  theme_minimal(base_size = 12) + theme(panel.grid = element_blank(),
    strip.text = element_text(face = "bold"), plot.caption = element_text(hjust = 0))
ggsave("outputs/figures/07_balanced_f1_confusion.png", chart,
  width = 11, height = 6, dpi = 180, bg = "white")
saveRDS(list(objective = "Maximum training OOF F1", thresholds = thresholds,
  classification_rule = "Predict KSI when probability >= the full-precision model-specific threshold",
  selection_rule = "Maximise pooled training OOF F1; exact ties favour recall, then threshold",
  selected_models = cv$selected, training_metrics = training_metrics,
  test_comparison = comparison, test_by_sex = by_sex,
  cv_md5 = unname(tools::md5sum(cv_path)), model_md5 = unname(tools::md5sum(model_path)),
  input_md5 = cv$input_md5, session_info = sessionInfo()),
  "data/processed/predictive_balanced_thresholds.rds")
print(training_metrics, width = Inf)
print(comparison, width = Inf)
message("Saved balanced-F1 thresholds and matrices; earlier scenarios remain available.")
