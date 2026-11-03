# Step 6 follow-up: defined crash scenarios and descriptive KSI comparisons.
# Run from the project root: source("R/05_crash_scenarios.R")
# Adds supplied DCA descriptions, maps codes, and saves tables and charts.
# Definitions checked against the official VicRoads DCA chart on 03/11/2026:
# https://opendata.transport.vic.gov.au/dataset/victoria-road-crash-data/resource/b658d974-4ff1-4de2-9c12-e47bb0fdbbac
# The combined groups below are project choices, not official group labels.
# Existing impact (front/side/rear) remains a separate variable.

library(dplyr)
library(readr)
library(ggplot2)

occ <- readRDS("data/processed/occupants_clean.rds")
accident <- read_csv(
  "data/raw/accident.csv",
  col_select = c(ACCIDENT_NO, DCA_CODE, DCA_DESC),
  col_types = cols(.default = "c")
) %>%
  transmute(accident_no = ACCIDENT_NO, raw_dca_code = DCA_CODE,
            dca_desc = DCA_DESC, source_matched = TRUE)

stopifnot(!anyNA(accident$accident_no),
          !anyDuplicated(accident$accident_no),
          !anyDuplicated(occ[c("accident_no", "person_id")]))

prepared <- occ %>%
  left_join(accident, by = "accident_no", relationship = "many-to-one")
if (anyNA(prepared$source_matched)) stop("Some occupants have no matching accident.")
same_code <- (is.na(prepared$dca_code) & is.na(prepared$raw_dca_code)) |
  (!is.na(prepared$dca_code) & !is.na(prepared$raw_dca_code) &
     prepared$dca_code == prepared$raw_dca_code)
if (!all(same_code)) stop("DCA codes disagree between the clean and raw data.")

prepared <- prepared %>%
  select(-raw_dca_code, -source_matched) %>%
  mutate(dca_status = case_when(
    is.na(dca_code) ~ "Missing code",
    dca_code == "199" ~ "Unknown manoeuvre (code 199)",
    is.na(dca_desc) ~ "Missing description",
    TRUE ~ "Description available"
  ))

# Exact equality checks ensure the join preserves original rows, order,
# column types and values. Unknown codes remain in the data.
stopifnot(identical(occ, prepared[names(occ)]))

# Include all codes present in the raw accident file, even those with no
# occupants in our filtered study sample. Counts below use distinct units.
raw_codes <- accident %>%
  count(raw_dca_code, dca_desc, name = "raw_crashes") %>%
  rename(dca_code = raw_dca_code)
study_codes <- prepared %>%
  group_by(dca_code, dca_desc) %>%
  summarise(occupants = n(),
            vehicles = n_distinct(accident_no, vehicle_id),
            crashes = n_distinct(accident_no), .groups = "drop")
inventory <- raw_codes %>%
  left_join(study_codes, by = c("dca_code", "dca_desc"), relationship = "one-to-one") %>%
  mutate(across(c(occupants, vehicles, crashes), ~coalesce(.x, 0L))) %>%
  arrange(dca_code, dca_desc)
coverage <- prepared %>% count(dca_status, name = "occupants")
stopifnot(sum(inventory$occupants) == nrow(occ))

dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
write_csv(inventory, "outputs/tables/06_dca_code_inventory.csv")
write_csv(coverage, "outputs/tables/06_dca_coverage.csv")
saveRDS(prepared, "data/processed/occupants_scenario_ready.rds")
cat("Preserved all", nrow(prepared), "occupants and their original values.\n")
cat("Inventoried", nrow(inventory), "code/description pairs.\n")
print(coverage)

# ---- Defined configurations -----------------------------------------
# Explicit lists avoid treating unused/new codes as validated categories.
# Rear-end: 130 same-lane, 154 pulling-out rear-end. Codes 131/132 are
# turning-related rear collisions and stay in the broader other group.
# Head-on: strictly 120. The chart's overtaking code 150 also includes
# sideswipe, so it is not treated as an unambiguous head-on collision.
# Run-off-road: explicitly leaves the carriageway, including off its end.
# Codes 151/174/184 do not establish a departure; 179/189 are nonspecific.
code_groups <- list(
  "Rear-end" = c(130L, 154L),
  "Head-on (not overtaking)" = 120L,
  "Adjacent-direction intersection" = 110:119,
  "Opposing-direction turning" = 121:125,
  "Run-off-road" = c(170:173, 175L, 180:183),
  "Loss of control on carriageway" = c(174L, 184L),
  "Other known configurations" = c(100:109, 129L, 131:137, 139L, 140:149,
                                    150:153, 159L, 160:167, 169L, 179L,
                                    189L, 190:194, 198L),
  "Unknown (DCA 199)" = 199L
)
mapping <- bind_rows(lapply(names(code_groups), function(label) {
  tibble(dca_code = as.character(code_groups[[label]]), crash_configuration = label)
}))
stopifnot(!anyDuplicated(mapping$dca_code))
scenario_levels <- c(names(code_groups), "Missing DCA", "Unmapped DCA")
scenarios <- prepared %>%
  left_join(mapping, by = "dca_code", relationship = "many-to-one") %>%
  mutate(crash_configuration = case_when(
    is.na(dca_code) ~ "Missing DCA",
    is.na(crash_configuration) ~ "Unmapped DCA",
    TRUE ~ crash_configuration
  ),
  crash_configuration = factor(crash_configuration, levels = scenario_levels))
stopifnot(identical(occ, scenarios[names(occ)]),
          !anyNA(scenarios$crash_configuration),
          all(scenarios$ksi %in% c(0L, 1L)), !anyNA(scenarios$sex),
          all(scenarios$sex %in% c("Male", "Female")))
if (any(scenarios$crash_configuration == "Unmapped DCA")) {
  warning("New or unmapped DCA codes retained explicitly; review the mapping audit.")
}

mapping_audit <- inventory %>%
  left_join(mapping, by = "dca_code", relationship = "many-to-one") %>%
  mutate(crash_configuration = case_when(
    is.na(dca_code) ~ "Missing DCA",
    is.na(crash_configuration) ~ "Unmapped DCA",
    TRUE ~ crash_configuration
  ))
scenario_counts <- scenarios %>%
  group_by(crash_configuration) %>%
  summarise(occupants = n(), vehicles = n_distinct(accident_no, vehicle_id),
            crashes = n_distinct(accident_no), .groups = "drop")
stopifnot(sum(scenario_counts$occupants) == nrow(occ))
write_csv(mapping, "outputs/tables/06_dca_mapping.csv")
write_csv(mapping_audit, "outputs/tables/06_dca_mapping_audit.csv")
write_csv(scenario_counts, "outputs/tables/06_crash_configuration_counts.csv")

# ---- Separate comparisons for configuration and impact --------------
# Each rate uses occupants of that sex within that category as denominator.
# Unknowns are retained and displayed explicitly, not silently dropped.
# These are descriptive rates, not adjusted odds or significance tests.
compare_scenarios <- function(data, column, stem, title) {
  rates <- data %>%
    transmute(scenario = as.character(.data[[column]]), sex, ksi) %>%
    mutate(scenario = coalesce(scenario, "Unknown / not applicable")) %>%
    group_by(scenario, sex) %>%
    summarise(people = n(), ksi_count = sum(ksi), .groups = "drop") %>%
    mutate(ksi_pct = 100 * ksi_count / people)
  gaps <- rates %>% group_by(scenario) %>%
    summarise(women_n = sum(people[sex == "Female"]),
              men_n = sum(people[sex == "Male"]),
              women_ksi = sum(ksi_count[sex == "Female"]),
              men_ksi = sum(ksi_count[sex == "Male"]), .groups = "drop") %>%
    mutate(women_pct = ifelse(women_n > 0, 100 * women_ksi / women_n, NA_real_),
           men_pct = ifelse(men_n > 0, 100 * men_ksi / men_n, NA_real_),
           gap_pts = women_pct - men_pct,
           rate_ratio = ifelse(men_pct > 0, women_pct / men_pct, NA_real_))
  stopifnot(sum(rates$people) == nrow(data),
            sum(rates$ksi_count) == sum(data$ksi))
  write_csv(rates, paste0("outputs/tables/06_ksi_by_", stem, "_sex.csv"))
  write_csv(gaps, paste0("outputs/tables/06_gap_by_", stem, ".csv"))

  order <- if (is.factor(data[[column]])) levels(data[[column]]) else unique(rates$scenario)
  order <- unique(c(order, "Unknown / not applicable"))
  plot_data <- rates %>% mutate(scenario = factor(scenario, levels = rev(order)))
  chart <- ggplot(plot_data, aes(ksi_pct, scenario, fill = sex)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7, orientation = "y") +
    geom_text(aes(label = sprintf("%.1f%% (n=%s)", ksi_pct,
                                  format(people, big.mark = ",", trim = TRUE))),
              position = position_dodge(width = 0.8), hjust = -0.1, size = 3) +
    scale_fill_manual(values = c(Male = "#2a78d6", Female = "#eb6834")) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.42))) +
    scale_y_discrete(labels = function(z) vapply(z, function(s)
      paste(strwrap(s, 29), collapse = "\n"), character(1))) +
    labs(title = title, subtitle = "Belted drivers and front passengers; unadjusted rates",
         x = "Killed or seriously injured (%)", y = NULL, fill = NULL,
         caption = "n = occupants of that sex in the category. Unknown categories are retained; small groups need caution.") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "top", panel.grid.major.y = element_blank(),
          panel.grid.minor = element_blank())
  dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
  ggsave(paste0("outputs/figures/06_ksi_by_", stem, ".png"), chart,
         width = 10, height = max(4.8, n_distinct(rates$scenario) * 0.8 + 1.7),
         dpi = 200, bg = "white")
  cat("\n", title, "\n")
  print(gaps, width = Inf)
  invisible(gaps)
}
compare_scenarios(scenarios, "crash_configuration", "crash_configuration",
                  "KSI by sex and crash configuration")
compare_scenarios(scenarios, "impact", "scenario_impact",
                  "KSI by sex and initial impact point")

write_csv(scenarios, "data/processed/occupants_scenarios.csv")
saveRDS(scenarios, "data/processed/occupants_scenarios.rds")
cat("\nSaved occupants_scenarios.csv/.rds, mappings, counts and comparisons.\n")
cat("All", nrow(scenarios), "occupants retained. Adjusted modelling is the next step.\n")
