# =====================================================================
# 03_explore.R  (Step 5: Exploratory analysis)
# Compares the % of women and men killed or seriously injured (KSI),
# broken down by one factor at a time. Saves charts to outputs/figures/
# and tables to outputs/tables/.
# =====================================================================

library(dplyr)
library(readr)
library(ggplot2)   # for charts

# ---- Load the clean table from Step 4 ---------------------------------
occ <- readRDS("data/processed/occupants_clean.rds")
cat("Rows:", nrow(occ), "\n")   # should be 194061

# Colours for the charts: blue for men, orange for women
# (these two are easy to tell apart, including for colour-blind readers)
sex_colours <- c(Male = "#2a78d6", Female = "#eb6834")


# ---- Our three reusable functions ("recipes") -------------------------

# 1. KSI rate for men and women within each group of a column.
#    People with NA in that column are left out.
rate_table <- function(data, column) {
  data %>%
    filter(!is.na(.data[[column]])) %>%
    group_by(group = .data[[column]], sex) %>%
    summarise(people  = n(),
              ksi_pct = round(100 * mean(ksi), 1),
              .groups = "drop")
}

# 2. Women and men side by side, plus the gap:
#    gap_pts = how many percentage points higher women are
#    ratio   = how many times higher women's rate is (1.20 = 20% higher)
gap_table <- function(rates) {
  rates %>%
    group_by(group) %>%
    summarise(women_pct = ksi_pct[sex == "Female"],
              men_pct   = ksi_pct[sex == "Male"],
              gap_pts   = round(women_pct - men_pct, 1),
              ratio     = round(women_pct / men_pct, 2))
}

# 3. Bar chart: one pair of bars (men, women) per group, with labels
plot_rates <- function(rates, title, x_label) {
  ggplot(rates, aes(x = group, y = ksi_pct, fill = sex)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.75) +
    geom_text(aes(label = sprintf("%.1f%%", ksi_pct)),
              position = position_dodge(width = 0.8), vjust = -0.5, size = 3.2) +
    scale_fill_manual(values = sex_colours) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(title = title, x = x_label,
         y = "Killed or seriously injured (%)", fill = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.major.x = element_blank(),
          panel.grid.minor   = element_blank(),
          legend.position    = "top")
}


# ---- 1. Overall: women vs men -----------------------------------------
overall <- occ %>%
  group_by(sex) %>%
  summarise(people = n(), ksi_pct = round(100 * mean(ksi), 1))
overall


# ---- 2. By vehicle era (the key question) -----------------------------
era_rates <- rate_table(occ, "vehicle_era")
era_gap   <- gap_table(era_rates)
era_gap

era_chart <- plot_rates(era_rates,
                        "Serious injury rate by sex and vehicle year of manufacture",
                        "Vehicle year of manufacture")
era_chart   # shows the chart in the Plots panel

# Save the chart and table so they can go in the report
dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/tables",  showWarnings = FALSE, recursive = TRUE)
ggsave("outputs/figures/05_ksi_by_vehicle_era.png", era_chart,
       width = 7, height = 4.2, dpi = 200, bg = "white")
write_csv(era_gap, "outputs/tables/05_gap_by_vehicle_era.csv")

# ---- 3. Do women drive lighter cars? ----------------------------------
# Median = the middle value (half the cars are lighter, half heavier)
occ %>%
  filter(!is.na(tare_kg)) %>%
  group_by(sex) %>%
  summarise(median_weight_kg = median(tare_kg))

# What share of women and men are in each weight quartile?
# prop.table(..., 1) turns counts into proportions across each row
round(prop.table(table(occ$sex, occ$tare_quartile), 1), 2)


# ---- 4. By vehicle weight ---------------------------------------------
weight_rates <- rate_table(occ, "tare_quartile")
weight_gap   <- gap_table(weight_rates)
weight_gap

weight_chart <- plot_rates(weight_rates,
                           "Serious injury rate by sex and vehicle weight",
                           "Vehicle weight (tare) quartile")
weight_chart
ggsave("outputs/figures/05_ksi_by_weight.png", weight_chart,
       width = 7, height = 4.2, dpi = 200, bg = "white")
write_csv(weight_gap, "outputs/tables/05_gap_by_weight.csv")


# ---- 5. By seat (driver vs front passenger) ---------------------------
seat_rates <- rate_table(occ, "seat")
seat_gap   <- gap_table(seat_rates)
seat_gap

seat_chart <- plot_rates(seat_rates,
                         "Serious injury rate by sex and seating position",
                         "Seating position")
seat_chart
ggsave("outputs/figures/05_ksi_by_seat.png", seat_chart,
       width = 7, height = 4.2, dpi = 200, bg = "white")
write_csv(seat_gap, "outputs/tables/05_gap_by_seat.csv")


# ---- 6. By crash type -------------------------------------------------
type_rates <- rate_table(occ, "crash_type")
type_gap   <- gap_table(type_rates)
type_gap

type_chart <- plot_rates(type_rates,
                         "Serious injury rate by sex and crash type",
                         "Crash type")
type_chart
ggsave("outputs/figures/05_ksi_by_crash_type.png", type_chart,
       width = 7, height = 4.2, dpi = 200, bg = "white")
write_csv(type_gap, "outputs/tables/05_gap_by_crash_type.csv")


# ---- 7. By first point of impact --------------------------------------
impact_rates <- rate_table(occ, "impact")
impact_gap   <- gap_table(impact_rates)
impact_gap

impact_chart <- plot_rates(impact_rates,
                           "Serious injury rate by sex and point of impact",
                           "First point of impact")
impact_chart
ggsave("outputs/figures/05_ksi_by_impact.png", impact_chart,
       width = 7, height = 4.2, dpi = 200, bg = "white")
write_csv(impact_gap, "outputs/tables/05_gap_by_impact.csv")


# ---- 8. Single vs multi-vehicle crash ---------------------------------
vehicles_rates <- rate_table(occ, "crash_vehicles")
vehicles_gap   <- gap_table(vehicles_rates)
vehicles_gap

vehicles_chart <- plot_rates(vehicles_rates,
                             "Serious injury rate by sex: single vs multi-vehicle crashes",
                             "Crash")
vehicles_chart
ggsave("outputs/figures/05_ksi_by_crash_vehicles.png", vehicles_chart,
       width = 7, height = 4.2, dpi = 200, bg = "white")
write_csv(vehicles_gap, "outputs/tables/05_gap_by_crash_vehicles.csv")

# ---- 9. Sensitivity check: include people with seatbelt unknown --------
# This table (from Step 3) has seatbelt worn (code 1) AND not known (code 9)
sens <- read_csv("data/processed/occupants_sensitivity.csv",
                 col_types = cols(.default = "c")) %>%
  mutate(
    ksi = as.integer(ksi),
    sex = factor(sex, levels = c("M", "F"), labels = c("Male", "Female")),
    belt_group = ifelse(helmet_belt_worn == "1", "Seatbelt worn", "Seatbelt not known"),
    belt_group = factor(belt_group, levels = c("Seatbelt worn", "Seatbelt not known"))
  )

# Gap within each seatbelt group
sens_gap <- gap_table(rate_table(sens, "belt_group"))
sens_gap

# Gap with both groups combined (as if we had NOT dropped the unknowns)
sens %>%
  group_by(sex) %>%
  summarise(people = n(), ksi_pct = round(100 * mean(ksi), 1))

write_csv(sens_gap, "outputs/tables/05_sensitivity_seatbelt.csv")
