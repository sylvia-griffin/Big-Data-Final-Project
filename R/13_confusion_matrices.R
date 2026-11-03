# Display existing held-out predictions; no model refitting or threshold tuning.
# Run from the project root after R/12_predictive_evaluation.R.
for (pkg in c("dplyr", "readr", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Install package: ", pkg)
}
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
saved <- readRDS("data/processed/predictive_models.rds")
predictions <- saved$test_predictions
existing <- read_csv("outputs/tables/07_predictive_confusion_metrics.csv", show_col_types = FALSE)
stopifnot(!anyNA(predictions$ksi), all(predictions$ksi %in% 0:1))
matrices <- bind_rows(lapply(names(saved$selected), function(model_name) {
  bind_rows(lapply(c("Training OOF Youden", "Fixed 0.5"), function(rule_name) {
    threshold <- if (rule_name == "Fixed 0.5") 0.5 else saved$thresholds[[model_name]]
    probability <- predictions[[model_name]]
    stopifnot(all(is.finite(probability)), all(probability >= 0 & probability <= 1))
    counts <- table(actual = factor(predictions$ksi, levels = 0:1, labels = c("Non-KSI", "KSI")),
      predicted = factor(as.integer(probability >= threshold), levels = 0:1, labels = c("Non-KSI", "KSI")))
    reference <- existing %>% filter(model == model_name, rule == rule_name)
    stopifnot(nrow(reference) == 1L,
      identical(as.integer(counts), as.integer(c(reference$tn, reference$fn, reference$fp, reference$tp))))
    as.data.frame(counts, responseName = "occupants") %>% as_tibble() %>%
      group_by(actual) %>% mutate(actual_class_pct = 100 * occupants / sum(occupants)) %>%
      ungroup() %>% mutate(model = model_name, rule = rule_name, threshold = threshold,
        outcome = case_when(actual == "KSI" & predicted == "KSI" ~ "True positive",
          actual == "KSI" ~ "False negative",
          predicted == "KSI" ~ "False positive", TRUE ~ "True negative"), .before = 1)
  }))
}))
write_csv(matrices, "outputs/tables/07_predictive_confusion_matrices.csv")
for (rule_name in c("Training OOF Youden", "Fixed 0.5")) {
  plot_data <- matrices %>% filter(rule == rule_name) %>%
    mutate(actual = factor(actual, levels = c("KSI", "Non-KSI")),
      panel = sprintf("%s\nThreshold = %.3f", model, threshold),
      label = sprintf("%s\n%s\n%.1f%% of actual class", outcome,
        format(occupants, big.mark = ",", trim = TRUE), actual_class_pct))
  chart <- ggplot(plot_data, aes(predicted, actual, fill = actual_class_pct)) +
    geom_tile(colour = "white", linewidth = 1.5) +
    geom_text(aes(label = label), size = 3.8, lineheight = 1.2) +
    facet_wrap(~panel, nrow = 1) + coord_equal() +
    scale_fill_gradient(low = "#F0F5FA", high = "#77B5D9", limits = c(0, 100), guide = "none") +
    labs(title = "KSI classification: held-out test occupants",
      subtitle = if (rule_name == "Fixed 0.5") "Fixed probability cutoff of 0.5 for both models"
        else "Cutoffs selected using training cross-validation; no test-set tuning",
      x = "Predicted outcome", y = "Actual outcome",
      caption = paste0("KSI = killed or seriously injured. Non-KSI = neither killed nor seriously injured.\n",
        "Counts and percentages within each actual class; each model uses ",
        format(nrow(predictions), big.mark = ","), " test occupants.")) +
    theme_minimal(base_size = 12) + theme(panel.grid = element_blank(),
      strip.text = element_text(face = "bold"), plot.caption = element_text(hjust = 0))
  suffix <- if (rule_name == "Fixed 0.5") "fixed_05" else "selected"
  ggsave(paste0("outputs/figures/07_predictive_confusion_", suffix, ".png"),
    chart, width = 11, height = 6, dpi = 180, bg = "white")
}
message("Saved both confusion-matrix charts and the count table; counts match prior evaluation.")
