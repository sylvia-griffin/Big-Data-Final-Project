# =====================================================================
# 02_clean.R  (Step 4: Cleaning and creating variables)
# Reads the final table from Step 3 and creates the grouped variables
# we need for charts and models. No people are removed here: missing
# or impossible values are set to NA (R's word for "missing").
# =====================================================================

library(dplyr)
library(readr)

# ---- Read the Step 3 output ----------------------------------------
# Read everything as text first so codes like "01" stay as they are
occ <- read_csv("data/processed/occupants_final.csv",
                col_types = cols(.default = "c"))
cat("Rows read:", nrow(occ), "\n")   # should be 194061

# Turn the number columns back into numbers
occ <- occ %>%
  mutate(
    ksi                = as.integer(ksi),
    vehicle_year_manuf = as.integer(vehicle_year_manuf),
    tare_weight        = as.integer(tare_weight),
    other_max_tare     = as.integer(other_max_tare),
    n_other_vehicles   = as.integer(n_other_vehicles),
    other_heavy_flag   = as.integer(other_heavy_flag)
  )

# ---- Sex and seat: give the codes readable names -------------------
# "Male" comes first, so later results compare women AGAINST men
occ <- occ %>%
  mutate(
    sex  = factor(sex, levels = c("M", "F"), labels = c("Male", "Female")),
    seat = factor(seating_position, levels = c("D", "LF"),
                  labels = c("Driver", "Front passenger"))
  )

# ---- Vehicle era ----------------------------------------------------
# Years before 1960 or after 2025 are impossible or errors (e.g. year 0),
# so they become NA. Then we group the years into 4 eras.
occ <- occ %>%
  mutate(
    vehicle_year = ifelse(vehicle_year_manuf < 1960 | vehicle_year_manuf > 2025,
                          NA, vehicle_year_manuf),
    vehicle_era = case_when(
      vehicle_year < 2000 ~ "Pre-2000",
      vehicle_year < 2010 ~ "2000-2009",
      vehicle_year < 2016 ~ "2010-2015",
      vehicle_year >= 2016 ~ "2016+"
    ),
    vehicle_era = factor(vehicle_era,
                         levels = c("Pre-2000", "2000-2009", "2010-2015", "2016+"))
  )

# Check: how many people in each era, and how many missing (NA)?
table(occ$vehicle_era, useNA = "ifany")

# ---- Vehicle weight (tare) ------------------------------------------
# Tare = the car's empty weight in kg. Under 600 kg or over 3,500 kg is
# not realistic for a car, wagon or ute, so those become NA.
# ntile(x, 4) splits the cars into 4 equal-sized groups (quartiles),
# from lightest to heaviest.
occ <- occ %>%
  mutate(
    tare_kg       = ifelse(tare_weight < 600 | tare_weight > 3500, NA, tare_weight),
    tare_quartile = ntile(tare_kg, 4),
    tare_quartile = factor(tare_quartile,
                           labels = c("Q1 lightest", "Q2", "Q3", "Q4 heaviest"))
  )

# Check: weight range in each quartile
occ %>%
  group_by(tare_quartile) %>%
  summarise(people = n(), min_kg = min(tare_kg), max_kg = max(tare_kg))

# ---- Age band ---------------------------------------------------------
# The data already has age groups, but too many small ones. We combine
# them into 4 bands. Children under 16 and "Unknown" become NA:
# children's bodies are different, so they would muddy a men vs women
# comparison.
occ <- occ %>%
  mutate(
    age_band = case_when(
      age_group %in% c("16-17", "18-21", "22-25") ~ "16-25",
      age_group %in% c("26-29", "30-39")          ~ "26-39",
      age_group %in% c("40-49", "50-59")          ~ "40-59",
      age_group %in% c("60-64", "65-69", "70+")   ~ "60+"
    ),
    age_band = factor(age_band, levels = c("16-25", "26-39", "40-59", "60+"))
  )

table(occ$age_band, useNA = "ifany")

# ---- Speed zone -------------------------------------------------------
# 777 = other, 888 = off road, 999 = not known, so those become NA.
# Then we group the speed limits into 4 bands.
occ <- occ %>%
  mutate(
    speed_limit = as.integer(speed_zone),
    speed_limit = ifelse(speed_limit %in% c(777, 888, 999), NA, speed_limit),
    speed_band = case_when(
      speed_limit <= 50 ~ "50 or less",
      speed_limit <= 70 ~ "60-70",
      speed_limit <= 90 ~ "75-90",
      speed_limit > 90  ~ "100-110"
    ),
    speed_band = factor(speed_band,
                        levels = c("50 or less", "60-70", "75-90", "100-110"))
  )

table(occ$speed_band, useNA = "ifany")

# ---- Crash type -------------------------------------------------------
# The data has 9 accident types, but most are rare. We keep the 3 big
# ones and group the rest as "Other".
# (1 = collision with vehicle, 4 = hit fixed object e.g. tree or pole,
#  6 = vehicle overturned / rollover)
occ <- occ %>%
  mutate(
    crash_type = case_when(
      accident_type == "1" ~ "Collision with vehicle",
      accident_type == "4" ~ "Hit fixed object",
      accident_type == "6" ~ "Rollover",
      TRUE                 ~ "Other"
    ),
    crash_type = factor(crash_type, levels = c("Collision with vehicle",
                                               "Hit fixed object",
                                               "Rollover", "Other"))
  )

table(occ$crash_type, useNA = "ifany")

# ---- Impact point -----------------------------------------------------
# Where the car was first hit. The raw codes mix letters (F = front,
# R = rear) and numbers for corners and sides, so we group them.
# 9, 0, S and blank mean not known / not applicable, so they become NA.
occ <- occ %>%
  mutate(
    impact = case_when(
      initial_impact %in% c("F", "1", "5")      ~ "Front",
      initial_impact %in% c("2", "3", "6", "7") ~ "Side",
      initial_impact %in% c("R", "4", "8")      ~ "Rear",
      initial_impact %in% c("T", "U", "N")      ~ "Other"
    ),
    impact = factor(impact, levels = c("Front", "Side", "Rear", "Other"))
  )

table(occ$impact, useNA = "ifany")

# ---- Single or multi-vehicle crash ------------------------------------
# Uses the "other vehicle" count we made in Step 3
occ <- occ %>%
  mutate(
    crash_vehicles = ifelse(n_other_vehicles == 0, "Single vehicle", "Multi vehicle"),
    crash_vehicles = factor(crash_vehicles,
                            levels = c("Single vehicle", "Multi vehicle"))
  )

table(occ$crash_vehicles, useNA = "ifany")

# ---- Final check: how much is missing in each new column? -------------
new_columns <- c("sex", "seat", "vehicle_era", "tare_quartile", "age_band",
                 "speed_band", "crash_type", "impact", "crash_vehicles")

colSums(is.na(occ[new_columns]))

# How many people have ALL of these filled in?
# (This is roughly how many the models in Step 7 will be able to use.)
sum(complete.cases(occ[new_columns]))

# ---- Save the clean table ---------------------------------------------
# CSV = opens anywhere (Excel etc.)
# RDS = R's own format; it remembers the category order we set with
#       factor(), so it is the better one to load in later R scripts.
write_csv(occ, "data/processed/occupants_clean.csv")
saveRDS(occ,   "data/processed/occupants_clean.rds")
cat("Saved occupants_clean.csv and occupants_clean.rds:", nrow(occ), "rows\n")
