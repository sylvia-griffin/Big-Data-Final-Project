# =====================================================================
# 04_cluster.R  (Step 6: Crash scenario clustering)
#
# Run from the project root, after 02_clean.R:
#   source("R/04_cluster.R")
# or in a terminal: Rscript R/04_cluster.R
#
# Cluster VEHICLES within crashes, then compare their occupants' KSI
# rates. Sex, injury, age and vehicle design are NOT clustering inputs.
# A vehicle with two eligible occupants gets the same weight as one
# with one occupant. Different vehicles in a crash may have different
# scenarios, because their impact points can differ.
#
# Required packages (install once if needed):
# install.packages(c("dplyr", "readr", "ggplot2", "klaR", "cluster"))
# k-modes documentation:
# https://search.r-project.org/CRAN/refmans/klaR/html/kmodes.html
# =====================================================================

required_packages <- c("dplyr", "readr", "ggplot2", "klaR", "cluster")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Install these packages first: ", paste(missing_packages, collapse = ", "))
}
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
})

# ---- Settings: fixed seeds make the analysis reproducible ------------
seed <- 20261102L
k_values <- 1:8                 # k = 1 is the no-clustering baseline
selection_sample_size <- 10000L # same random vehicle sample for every k
selection_starts <- 10L         # keep the lowest-cost run for each k
final_starts <- 5L              # refit on ALL eligible vehicles
max_iterations <- 30L
silhouette_sample_size <- 2000L # avoid a full 153k x 153k distance matrix

input_path <- "data/processed/occupants_clean.rds"
if (!file.exists(input_path)) {
  stop("Missing ", input_path, ". Run 02_clean.R from the project root first.")
}
occ <- readRDS(input_path)
required_columns <- c("accident_no", "vehicle_id", "person_id", "sex", "ksi",
                      "speed_band", "crash_type", "impact", "crash_vehicles",
                      "road_geometry", "light_condition")
if (!all(required_columns %in% names(occ))) stop("The clean input is missing required columns.")
if (anyNA(occ[c("accident_no", "vehicle_id", "person_id")]) ||
    anyDuplicated(occ[c("accident_no", "person_id")])) {
  stop("Occupant keys must be present and unique.")
}
if (anyNA(occ$ksi) || !all(occ$ksi %in% c(0L, 1L)) ||
    anyNA(occ$sex) || !all(occ$sex %in% c("Male", "Female"))) {
  stop("Expected a non-missing binary KSI outcome and Male/Female sex labels.")
}

# ---- 1. Crash features and missing-value decisions -------------------
# Road geometry: 1-4 = intersections; 5 = not at intersection, 6 = dead end.
# Codes 7-9 (road closure, private property, unknown) are not assigned
# a road context. Lighting 3-6 all indicate darkness, even when the
# street-lighting status is unknown; code 9 has unknown light conditions.
occ <- occ %>%
  mutate(
    road_context = case_when(
      road_geometry %in% as.character(1:4) ~ "Intersection",
      road_geometry %in% c("5", "6") ~ "Non-intersection"
    ),
    lighting = case_when(
      light_condition == "1" ~ "Daylight",
      light_condition == "2" ~ "Dusk/dawn",
      light_condition %in% as.character(3:6) ~ "Dark"
    )
  )

# All five inputs are nominal categories with equal mismatch weights.
# Single/multi-vehicle status is profiled later, but left out here because
# it largely repeats the collision-with-vehicle vs other-crash distinction.
features <- c("speed_band", "crash_type", "impact", "road_context", "lighting")
profile_features <- c(features, "crash_vehicles")
vehicle_rows <- occ %>%
  select(accident_no, vehicle_id, all_of(profile_features)) %>%
  distinct() %>%
  arrange(accident_no, vehicle_id)
if (anyDuplicated(vehicle_rows[c("accident_no", "vehicle_id")])) {
  stop("Occupants of the same vehicle have conflicting crash features.")
}

complete_vehicle <- complete.cases(vehicle_rows[features])
complete_occupant <- complete.cases(occ[features])
missing_summary <- tibble(
  feature = features,
  vehicles_missing = colSums(is.na(vehicle_rows[features])),
  occupants_missing = colSums(is.na(occ[features]))
)
# Missing counts overlap: a vehicle can lack more than one feature.
# Do not require complete age, weight or era, since these are not inputs.
filter_counts <- tibble(
  stage = c("Clean input", "Complete clustering features", "Unassigned: missing features"),
  vehicles = c(nrow(vehicle_rows), sum(complete_vehicle), sum(!complete_vehicle)),
  occupants = c(nrow(occ), sum(complete_occupant), sum(!complete_occupant))
)
print(filter_counts)
print(missing_summary)

eligible_vehicles <- vehicle_rows[complete_vehicle, ]
# Remove the ordered-factor interpretation of speed bands: k-modes counts
# category mismatches; it does not assume that category codes are numbers.
x <- as.data.frame(lapply(eligible_vehicles[features], function(z) factor(as.character(z))))
if (nrow(x) < 20L || nrow(unique(x)) < max(k_values)) {
  stop("Too few complete vehicles or distinct scenarios for the configured k range.")
}

dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
write_csv(filter_counts, "outputs/tables/06_cluster_filter_counts.csv")
write_csv(missing_summary, "outputs/tables/06_cluster_missing.csv")

# ---- 2. Compare k using repeated starts on one vehicle sample --------
# klaR uses simple-matching distance (number of different categories).
# Repeated starts reduce sensitivity to randomly chosen starting modes.
# Ties in klaR's fast algorithm are random; the seed fixes their outcome.
fit_restarts <- function(data, k, n_starts, run_seed, initial_modes = NULL) {
  best_fit <- NULL
  best_cost <- Inf
  runs <- vector("list", n_starts)
  for (s in seq_len(n_starts)) {
    set.seed(run_seed + s)
    start_modes <- if (s == 1L && !is.null(initial_modes)) initial_modes else k
    # A failed/degenerate start should not discard the other valid starts.
    fit_error <- NA_character_
    fit <- tryCatch(
      klaR::kmodes(data, modes = start_modes, iter.max = max_iterations,
                   weighted = FALSE, fast = TRUE),
      error = function(e) { fit_error <<- conditionMessage(e); NULL }
    )
    valid <- !is.null(fit) && nrow(fit$modes) == k && !anyNA(fit$modes) &&
      !anyDuplicated(fit$modes) &&
      length(unique(fit$cluster)) == k && !anyNA(fit$cluster)
    cost <- if (valid) sum(fit$withindiff) else Inf
    runs[[s]] <- tibble(k = k, start = s, seed = run_seed + s,
                        valid = valid, total_mismatches = cost, error = fit_error)
    if (is.finite(cost) && cost < best_cost) {
      best_fit <- fit
      best_cost <- cost
    }
  }
  if (is.null(best_fit)) stop("No valid fit for k = ", k)
  list(fit = best_fit, runs = bind_rows(runs))
}

set.seed(seed)
selection_rows <- sort(sample.int(nrow(x), min(selection_sample_size, nrow(x))))
x_selection <- x[selection_rows, , drop = FALSE]
set.seed(seed + 1L)
silhouette_rows <- sort(sample.int(nrow(x_selection),
                                 min(silhouette_sample_size, nrow(x_selection))))
# With only unordered factors, Gower distance is the fraction of mismatches.
# This differs from the k-modes distance only by the constant feature count.
silhouette_distance <- cluster::daisy(x_selection[silhouette_rows, ], metric = "gower")
selection_fits <- vector("list", length(k_values))
selection_runs <- vector("list", length(k_values))
diagnostics <- vector("list", length(k_values))

for (i in seq_along(k_values)) {
  k <- k_values[i]
  cat("Comparing k =", k, "on", nrow(x_selection), "vehicles ...\n")
  result <- fit_restarts(x_selection, k, if (k == 1L) 1L else selection_starts,
                        seed + 100L * k)
  fit <- result$fit
  selection_fits[[i]] <- fit
  selection_runs[[i]] <- result$runs
  labels <- fit$cluster[silhouette_rows]
  silhouette_mean <- if (k > 1L && length(unique(labels)) > 1L) {
    mean(cluster::silhouette(labels, silhouette_distance)[, "sil_width"])
  } else NA_real_
  diagnostics[[i]] <- tibble(
    k = k, sample_vehicles = nrow(x_selection),
    total_mismatches = sum(fit$withindiff),
    mean_mismatches = sum(fit$withindiff) / nrow(x_selection),
    smallest_cluster_pct = 100 * min(fit$size) / nrow(x_selection),
    mean_silhouette = silhouette_mean
  )
}
k_diagnostics <- bind_rows(diagnostics)
if (any(diff(k_diagnostics$total_mismatches) > 0)) {
  warning("Cost increases for some k values. Consider more starts before interpreting the elbow.")
}

# Choose an elbow reproducibly: largest distance below the straight line
# joining the first and last points of the normalised cost curve.
# This is a heuristic, not proof of a uniquely optimal k. Silhouette and
# cluster sizes are saved as additional diagnostics, not tuned to sex/KSI.
cost_range <- first(k_diagnostics$total_mismatches) - last(k_diagnostics$total_mismatches)
if (cost_range <= 0) stop("The cost curve has no variation; inspect the input.")
k_diagnostics <- k_diagnostics %>%
  mutate(
    normalised_k = (k - min(k)) / (max(k) - min(k)),
    normalised_cost = (total_mismatches - last(total_mismatches)) / cost_range,
    elbow_distance = 1 - normalised_k - normalised_cost
  )
candidates <- which(k_diagnostics$k > min(k_values) & k_diagnostics$k < max(k_values))
selected_row <- candidates[which.max(k_diagnostics$elbow_distance[candidates])]
selected_k <- k_diagnostics$k[selected_row]
k_diagnostics$selected <- k_diagnostics$k == selected_k
print(k_diagnostics %>% select(k, mean_mismatches, smallest_cluster_pct, mean_silhouette, selected))
cat("Elbow heuristic selected k =", selected_k, "\n")
write_csv(k_diagnostics, "outputs/tables/06_cluster_k_diagnostics.csv")
write_csv(bind_rows(selection_runs), "outputs/tables/06_cluster_selection_starts.csv")

elbow_chart <- ggplot(k_diagnostics, aes(k, mean_mismatches)) +
  geom_line(colour = "#2a78d6") + geom_point(size = 2.5, colour = "#2a78d6") +
  geom_vline(xintercept = selected_k, linetype = "dashed", colour = "#eb6834") +
  scale_x_continuous(breaks = k_values) +
  labs(title = "Choosing the number of crash scenarios",
       subtitle = paste("Lowest cost across repeated starts; selected k =", selected_k),
       x = "Number of clusters (k)", y = "Mean mismatched features per vehicle",
       caption = paste("Same random sample of", format(nrow(x_selection), big.mark = ","),
                       "vehicles. Dashed line: normalised elbow heuristic.")) +
  theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank())
ggsave("outputs/figures/06_cluster_elbow.png", elbow_chart,
       width = 7.5, height = 4.5, dpi = 200, bg = "white")

# ---- 3. Refit the selected k using all eligible vehicles --------------
# First start uses the best sample modes; the others use random starts.
cat("Refitting k =", selected_k, "on all", nrow(x), "eligible vehicles ...\n")
final_result <- fit_restarts(x, selected_k, final_starts, seed + 10000L,
                            initial_modes = selection_fits[[selected_row]]$modes)
final_fit <- final_result$fit
write_csv(final_result$runs, "outputs/tables/06_cluster_final_starts.csv")

# Number clusters from largest to smallest for easier reading. The ID
# itself has no statistical meaning and may change if inputs change.
old_ids <- order(-as.integer(table(factor(final_fit$cluster, levels = seq_len(selected_k)))))
id_map <- match(seq_len(selected_k), old_ids)
eligible_vehicles$cluster_id <- id_map[final_fit$cluster]
fitted_modes <- as_tibble(final_fit$modes[old_ids, , drop = FALSE]) %>%
  mutate(cluster_id = row_number(), .before = 1)

# ---- 4. Profile and name the scenarios -------------------------------
# Save ALL category proportions as well as modes, so a modal label is
# never mistaken for a description that applies to every vehicle.
profile_distribution <- bind_rows(lapply(profile_features, function(nm) {
  eligible_vehicles %>%
    transmute(cluster_id, feature = nm, category = as.character(.data[[nm]])) %>%
    count(cluster_id, feature, category, name = "vehicles") %>%
    group_by(cluster_id, feature) %>%
    mutate(pct = 100 * vehicles / sum(vehicles)) %>% ungroup()
}))
modal_profile <- profile_distribution %>%
  arrange(cluster_id, feature, desc(vehicles), category) %>%
  group_by(cluster_id, feature) %>% slice_head(n = 1) %>% ungroup()

# Names come only from modal crash features. They describe speed ZONES,
# not measured driving speeds; rear impact does not prove a rear-end crash.
type_names <- c("Collision with vehicle" = "vehicle collision",
                "Hit fixed object" = "fixed-object collision",
                "Rollover" = "rollover", "Other" = "other crash")
# Keep names short by using the modal features that DIFFER across clusters.
# Shared modal features and their proportions remain in the profile table.
name_features <- features[vapply(fitted_modes[features], n_distinct, integer(1)) > 1L]
cluster_names <- tibble(
  cluster_id = fitted_modes$cluster_id,
  cluster_name = vapply(seq_len(selected_k), function(i) {
    m <- fitted_modes[i, ]
    phrases <- c(speed_band = paste0(m$speed_band, " km/h zone"),
                 crash_type = unname(type_names[as.character(m$crash_type)]),
                 impact = paste(tolower(as.character(m$impact)), "impact"),
                 road_context = tolower(as.character(m$road_context)),
                 lighting = tolower(as.character(m$lighting)))
    paste0("C", i, ": ", paste(phrases[name_features], collapse = "; "))
  }, character(1))
)
cluster_profiles <- eligible_vehicles %>%
  group_by(cluster_id) %>%
  summarise(vehicles = n(), crashes = n_distinct(accident_no), .groups = "drop") %>%
  mutate(vehicles_pct = 100 * vehicles / sum(vehicles)) %>%
  left_join(cluster_names, by = "cluster_id")
for (nm in profile_features) {
  values <- modal_profile %>% filter(feature == nm) %>% select(cluster_id, category, pct)
  names(values)[2:3] <- c(paste0(nm, "_mode"), paste0(nm, "_mode_pct"))
  cluster_profiles <- left_join(cluster_profiles, values, by = "cluster_id")
}
print(cluster_profiles, width = Inf)
write_csv(cluster_profiles, "outputs/tables/06_cluster_profiles.csv")
write_csv(profile_distribution, "outputs/tables/06_cluster_profile_distribution.csv")
write_csv(fitted_modes, "outputs/tables/06_cluster_modes.csv")

feature_labels <- c(speed_band = "Speed zone", crash_type = "Crash type",
                    impact = "Impact", road_context = "Road layout",
                    lighting = "Lighting", crash_vehicles = "Vehicles")
wrap_text <- function(z, width) vapply(z, function(s) paste(strwrap(s, width), collapse = "\n"), character(1))
profile_plot_data <- modal_profile %>%
  mutate(feature = factor(feature, levels = profile_features, labels = feature_labels[profile_features]),
         cluster = factor(paste0("C", cluster_id), levels = paste0("C", rev(seq_len(selected_k)))),
         label = paste0(wrap_text(category, 18), "\n", sprintf("%.1f%%", pct)))
profile_chart <- ggplot(profile_plot_data, aes(feature, cluster, fill = pct)) +
  geom_tile(colour = "white", linewidth = 1) +
  geom_text(aes(label = label), size = 3) +
  scale_fill_gradient(low = "#f1f5fb", high = "#95b8e7", limits = c(0, 100)) +
  labs(title = "Crash scenario profiles",
       subtitle = "Most common category and its share of vehicles in each cluster",
       x = NULL, y = NULL, fill = "Vehicles (%)",
       caption = "Single/multi-vehicle status is shown for context; it was not a clustering input.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(), legend.position = "bottom")
ggsave("outputs/figures/06_cluster_profiles.png", profile_chart,
       width = 10, height = max(4.5, selected_k * 0.85 + 1.8), dpi = 200, bg = "white")

# ---- 5. Attach clusters to occupants and compare KSI by sex -----------
assignments <- eligible_vehicles %>% select(accident_no, vehicle_id, cluster_id) %>%
  left_join(cluster_names, by = "cluster_id")
clustered_occ <- occ %>%
  left_join(assignments, by = c("accident_no", "vehicle_id"), relationship = "many-to-one") %>%
  mutate(cluster_status = ifelse(is.na(cluster_id), "Missing clustering features", "Assigned"))
stopifnot(nrow(clustered_occ) == nrow(occ),
          sum(!is.na(clustered_occ$cluster_id)) == sum(complete_occupant))

# Denominators are PEOPLE here, whereas profile denominators are VEHICLES.
# Rates, gaps and ratios retain full precision in the CSVs.
cluster_rates <- clustered_occ %>% filter(!is.na(cluster_id)) %>%
  group_by(cluster_id, cluster_name, sex, .drop = FALSE) %>%
  summarise(people = n(), ksi_count = sum(ksi),
            ksi_pct = if (n() > 0) 100 * mean(ksi) else NA_real_, .groups = "drop") %>%
  filter(!is.na(cluster_name))
cluster_gap <- cluster_rates %>%
  group_by(cluster_id, cluster_name) %>%
  summarise(
    women_n = sum(people[sex == "Female"]), men_n = sum(people[sex == "Male"]),
    women_ksi = sum(ksi_count[sex == "Female"]), men_ksi = sum(ksi_count[sex == "Male"]),
    .groups = "drop"
  ) %>%
  mutate(women_pct = ifelse(women_n > 0, 100 * women_ksi / women_n, NA_real_),
         men_pct = ifelse(men_n > 0, 100 * men_ksi / men_n, NA_real_),
         gap_pts = women_pct - men_pct,
         ratio = ifelse(men_pct > 0, women_pct / men_pct, NA_real_))

# Show whether excluded records and the mix of scenarios differ by sex.
coverage <- clustered_occ %>% group_by(cluster_status, sex) %>%
  summarise(people = n(), ksi_count = sum(ksi), ksi_pct = 100 * mean(ksi), .groups = "drop")
sex_mix <- cluster_rates %>% group_by(sex) %>%
  mutate(pct_of_sex_in_cluster = 100 * people / sum(people)) %>% ungroup()
write_csv(cluster_rates, "outputs/tables/06_ksi_by_cluster_sex.csv")
write_csv(cluster_gap, "outputs/tables/06_gap_by_cluster.csv")
write_csv(coverage, "outputs/tables/06_cluster_coverage_by_sex.csv")
write_csv(sex_mix, "outputs/tables/06_cluster_mix_by_sex.csv")
write_csv(assignments, "data/processed/vehicle_cluster_assignments.csv")
write_csv(clustered_occ, "data/processed/occupants_clustered.csv")
saveRDS(clustered_occ, "data/processed/occupants_clustered.rds")

rate_plot_data <- cluster_rates %>%
  mutate(cluster_label = factor(cluster_name, levels = rev(cluster_names$cluster_name)))
ksi_chart <- ggplot(rate_plot_data, aes(ksi_pct, cluster_label, fill = sex)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7, orientation = "y") +
  geom_text(aes(label = sprintf("%.1f%%", ksi_pct)), hjust = -0.15,
            position = position_dodge(width = 0.8), size = 3.2) +
  scale_fill_manual(values = c(Male = "#2a78d6", Female = "#eb6834")) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_y_discrete(labels = function(z) wrap_text(z, 43)) +
  labs(title = "KSI rate by sex within crash scenarios",
       subtitle = "Clusters use crash features only; rates use occupants as the denominator",
       x = "Killed or seriously injured (%)", y = NULL, fill = NULL,
       caption = "Names summarise distinguishing modal features. Descriptive comparisons; other differences remain.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top", panel.grid.major.y = element_blank(),
        panel.grid.minor = element_blank())
ggsave("outputs/figures/06_ksi_by_cluster.png", ksi_chart,
       width = 10, height = max(4.5, selected_k * 1.15 + 1.8), dpi = 200, bg = "white")

# Save enough information to reproduce and audit the selected fit.
model_record <- list(
  method = "klaR k-modes; equal-weight simple-matching distance",
  features = features, seed = seed, selected_k = selected_k,
  selection_rule = "Maximum normalised elbow distance on k = 1:8",
  selection_starts = selection_starts, final_starts = final_starts,
  max_iterations = max_iterations, selection_vehicle_rows = selection_rows,
  selection_vehicle_keys = eligible_vehicles[selection_rows, c("accident_no", "vehicle_id")],
  diagnostics = k_diagnostics, model = final_fit, old_to_new_cluster_id = id_map,
  input_md5 = unname(tools::md5sum(input_path)), session_info = sessionInfo()
)
saveRDS(model_record, "data/processed/cluster_model.rds")
capture.output(sessionInfo(), file = "outputs/tables/06_cluster_session_info.txt")
cat("\nKSI comparisons by cluster:\n")
print(cluster_gap %>% select(-cluster_name), width = Inf)
cat("\nCoverage by sex:\n")
print(coverage)
cat("\nSaved Step 6 tables and figures, plus occupants_clustered.csv/.rds.\n",
    "These are descriptive scenario comparisons; adjusted inference belongs in Step 7.\n",
    "Take screenshots of the elbow plot, profiles and this console output for the report.\n")
